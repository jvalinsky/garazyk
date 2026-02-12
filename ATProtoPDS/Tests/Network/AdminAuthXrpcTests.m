#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface AdminAuthXrpcTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *adminDid;
@property (nonatomic, copy) NSString *adminJwt;
@property (nonatomic, copy) NSString *userDid;
@property (nonatomic, copy) NSString *userJwt;
@end

@implementation AdminAuthXrpcTests

- (void)setUp {
    [super setUp];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    self.controller = [[PDSController alloc] initWithDirectory:self.tempURL.path serviceMaxSize:10 userDatabaseSize:10];
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher controller:self.controller];

    NSError *error = nil;
    NSDictionary *adminAccount = [self.controller createAccountForEmail:@"admin@example.com"
                                                               password:@"password"
                                                                 handle:@"admin.test"
                                                                    did:nil
                                                                  error:&error];
    XCTAssertNil(error);
    self.adminDid = adminAccount[@"did"];
    self.adminJwt = adminAccount[@"accessJwt"];
    XCTAssertNotNil(self.adminJwt);

    NSDictionary *userAccount = [self.controller createAccountForEmail:@"user@example.com"
                                                              password:@"password"
                                                                handle:@"user.test"
                                                                   did:nil
                                                                 error:&error];
    XCTAssertNil(error);
    self.userDid = userAccount[@"did"];

    NSString *inviteCode = [NSString stringWithFormat:@"TEST-%@", [[NSUUID UUID] UUIDString]];
    BOOL createdInvite = [self.controller.serviceDatabases createInviteCode:inviteCode
                                                                  forAccount:self.userDid
                                                                     maxUses:3
                                                                       error:&error];
    XCTAssertTrue(createdInvite);
    XCTAssertNil(error);

    NSDictionary *session = [self.controller loginWithHandle:@"user.test" password:@"password" error:&error];
    XCTAssertNil(error);
    self.userJwt = session[@"accessJwt"];
    XCTAssertNotNil(self.userJwt);
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
}

- (HttpResponse *)sendJsonRequestWithPath:(NSString *)path
                                     body:(NSDictionary *)body
                                  headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSMutableDictionary *allHeaders = [@{@"content-type": @"application/json"} mutableCopy];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                                                  methodString:@"POST"
                                                          path:path
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:allHeaders
                                                          body:bodyData
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (HttpResponse *)sendGetRequestWithPath:(NSString *)path
                              queryString:(NSString *)queryString
                              queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                                  headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *allHeaders = [NSMutableDictionary dictionary];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:path
                                                   queryString:queryString ?: @""
                                                   queryParams:queryParams ?: @{}
                                                       version:@"1.1"
                                                       headers:allHeaders
                                                          body:[NSData data]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (void)testGetAccountInfoRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getAccountInfo"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetAccountInfosRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getAccountInfos"
                                              queryString:[NSString stringWithFormat:@"dids=%@", self.userDid]
                                              queryParams:@{@"dids": self.userDid}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetAccountInfoNonAdminForbidden {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getAccountInfo"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testGetAccountInfosNonAdminForbidden {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getAccountInfos"
                                              queryString:[NSString stringWithFormat:@"dids=%@", self.userDid]
                                              queryParams:@{@"dids": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testGetAccountInfoAdminSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getAccountInfo"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"did"], self.userDid);
    XCTAssertEqualObjects(response.jsonBody[@"handle"], @"user.test");
    XCTAssertNotNil(response.jsonBody[@"indexedAt"]);
}

- (void)testGetAccountInfosAdminSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    NSString *queryString = [NSString stringWithFormat:@"dids=%@&dids=%@", self.userDid, self.adminDid];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getAccountInfos"
                                              queryString:queryString
                                              queryParams:@{@"dids": self.adminDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *infos = response.jsonBody[@"infos"];
    XCTAssertTrue([infos isKindOfClass:[NSArray class]]);
    XCTAssertEqual(infos.count, 2);
}

- (void)testGetInviteCodesRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getInviteCodes"
                                              queryString:@"limit=10"
                                              queryParams:@{@"limit": @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetInviteCodesNonAdminForbidden {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getInviteCodes"
                                              queryString:@"limit=10"
                                              queryParams:@{@"limit": @"10"}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testGetInviteCodesAdminSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getInviteCodes"
                                              queryString:@"limit=10"
                                              queryParams:@{@"limit": @"10"}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *codes = response.jsonBody[@"codes"];
    XCTAssertTrue([codes isKindOfClass:[NSArray class]]);
    XCTAssertGreaterThan(codes.count, 0);

    NSDictionary *first = codes.firstObject;
    XCTAssertNotNil(first[@"code"]);
    XCTAssertNotNil(first[@"available"]);
    XCTAssertNotNil(first[@"disabled"]);
    XCTAssertNotNil(first[@"forAccount"]);
    XCTAssertNotNil(first[@"createdBy"]);
    XCTAssertNotNil(first[@"createdAt"]);
    XCTAssertNotNil(first[@"uses"]);
}

- (void)testModerateAccountRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateAccount"
                                                      body:@{@"did": self.userDid, @"reason": @"test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testModerateAccountNonAdminForbidden {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateAccount"
                                                      body:@{@"did": self.userDid, @"reason": @"test"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testTakeDownAccountRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.takeDownAccount"
                                                      body:@{@"did": self.userDid, @"reason": @"test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testLabelCreateRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.label.createLabel"
                                                      body:@{@"src": self.adminDid, @"uri": @"at://did:plc:test/app.bsky.feed.post/1", @"val": @"spam"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testLabelCreateNonAdminForbidden {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.label.createLabel"
                                                      body:@{@"src": self.adminDid, @"uri": @"at://did:plc:test/app.bsky.feed.post/1", @"val": @"spam"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

@end
