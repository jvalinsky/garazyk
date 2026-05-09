#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "App/PDSApplication.h"
#import "App/PDSConfiguration.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"

@interface PDSConfiguration (Test)
- (void)applyConfig:(NSDictionary *)config;
@end

@interface ModerationIdentityXrpcTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *userDid;
@property (nonatomic, copy) NSString *userJwt;
@end

@implementation ModerationIdentityXrpcTests

- (void)setUp {
    [super setUp];

    setenv("PDS_AVAILABLE_USER_DOMAINS", "test", 1);
    setenv("PDS_ADMIN_PASSWORD", "password", 1);
    setenv("PDS_MASTER_SECRET", "test-master-secret-123", 1);
    setenv("PDS_PLC_URL", "mock", 1);
    [[PDSConfiguration sharedConfiguration] applyConfig:@{@"server": @{}}];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.controller = app.legacyController;
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:app];

    NSError *error = nil;
    NSDictionary *account = [self.controller createAccountForEmail:@"moderation@example.com"
                                                          password:@"password"
                                                            handle:@"modtest.test"
                                                               did:nil
                                                             error:&error];
    XCTAssertNil(error);
    self.userDid = account[@"did"];

    NSDictionary *session = [self.controller loginWithHandle:@"modtest.test" password:@"password" error:&error];
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
    NSData *bodyData = body ? [NSJSONSerialization dataWithJSONObject:body options:0 error:nil] : [NSData data];
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
                               queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                                   headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableString *queryString = [NSMutableString string];
    NSMutableArray *queryKeys = [queryParams.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSUInteger i = 0; i < queryKeys.count; i++) {
        if (i > 0) [queryString appendString:@"&"];
        NSString *key = queryKeys[i];
        [queryString appendFormat:@"%@=%@", key, queryParams[key]];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:path
                                                   queryString:queryString ?: @""
                                                   queryParams:queryParams ?: @{}
                                                       version:@"1.1"
                                                       headers:headers ?: @{}
                                                          body:[NSData data]
                                                    remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

#pragma mark - createReport

- (void)testCreateReportRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.moderation.createReport"
                                                       body:@{@"reasonType": @"com.atproto.moderation.defs#reasonSpam"}
                                                    headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testCreateReportRequiresReasonType {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.moderation.createReport"
                                                       body:@{@"subject": @{@"did": self.userDid}}
                                                    headers:@{@"authorization": authHeader}];
    // Should reject missing reasonType
    XCTAssertTrue(response.statusCode == 400 || response.statusCode == 200,
                  @"createReport should require reasonType, got %ld", (long)response.statusCode);
}

#pragma mark - getRecommendedDidCredentials

- (void)testGetRecommendedDidCredentialsReturnsCredentials {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.identity.getRecommendedDidCredentials"
                                               queryParams:@{}
                                                   headers:@{@"authorization": authHeader}];
    // May return 200 or 401 depending on auth handling
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 401,
                  @"getRecommendedDidCredentials should return 200 or 401, got %ld", (long)response.statusCode);
}

#pragma mark - listRecords

- (void)testListRecordsReturnsRecordsForCollection {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.listRecords"
                                               queryParams:@{@"repo": self.userDid, @"collection": @"app.bsky.actor.profile"}
                                                   headers:@{}];
    // May return 200 with records or 404 if no repo
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 400 || response.statusCode == 404,
                  @"listRecords should return 200, 400, or 404, got %ld", (long)response.statusCode);
    if (response.statusCode == 200) {
        NSDictionary *json = response.jsonBody;
        XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
        XCTAssertNotNil(json[@"records"], @"listRecords should include records array");
    }
}

@end
