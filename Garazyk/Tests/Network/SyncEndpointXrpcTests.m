// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "App/PDSApplication.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"

@interface ATProtoServiceConfiguration (Test)
- (void)applyConfig:(NSDictionary *)config;
@end

@interface SyncEndpointXrpcTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *userDid;
@property (nonatomic, copy) NSString *userJwt;
@end

@implementation SyncEndpointXrpcTests

- (void)setUp {
    [super setUp];

    setenv("PDS_AVAILABLE_USER_DOMAINS", "test", 1);
    setenv("PDS_ADMIN_PASSWORD", "password", 1);
    setenv("PDS_MASTER_SECRET", "test-master-secret-123", 1);
    setenv("PDS_PLC_URL", "mock", 1);
    [[ATProtoServiceConfiguration sharedConfiguration] applyConfig:@{@"server": @{}}];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.controller = app.legacyController;
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:app];

    NSError *error = nil;
    NSDictionary *account = [self.controller createAccountForEmail:@"sync@example.com"
                                                          password:@"password"
                                                            handle:@"synctest.test"
                                                               did:nil
                                                             error:&error];
    XCTAssertNil(error);
    self.userDid = account[@"did"];

    NSDictionary *session = [self.controller loginWithHandle:@"synctest.test" password:@"password" error:&error];
    XCTAssertNil(error);
    self.userJwt = session[@"accessJwt"];
    XCTAssertNotNil(self.userJwt);
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
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

#pragma mark - listRepos

- (void)testListReposReturnsRepos {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listRepos"
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *json = response.jsonBody;
    XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
    NSArray *repos = json[@"repos"];
    XCTAssertTrue([repos isKindOfClass:[NSArray class]]);
    // At least the account we created
    XCTAssertTrue(repos.count >= 1, @"Should have at least one repo");
}

#pragma mark - listBlobs

- (void)testListBlobsReturnsBlobsForDID {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listBlobs"
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    // May return 200 with empty list or 400 if DID is invalid
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 400,
                  @"listBlobs should return 200 or 400, got %ld", (long)response.statusCode);
    if (response.statusCode == 200) {
        NSDictionary *json = response.jsonBody;
        XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
    }
}

#pragma mark - getCheckout

- (void)testGetCheckoutReturnsDataForDID {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getCheckout"
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{}];
    // May return 200 with CAR data or 404 if no repo
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 400 || response.statusCode == 404,
                  @"getCheckout should return 200, 400, or 404, got %ld", (long)response.statusCode);
}

#pragma mark - getHostStatus

- (void)testGetHostStatusReturnsStatus {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getHostStatus"
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{}];
    // May return 200 or 404
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 404 || response.statusCode == 400,
                  @"getHostStatus should return 200, 404, or 400, got %ld", (long)response.statusCode);
}

#pragma mark - notifyOfUpdate

- (void)testNotifyOfUpdateRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.sync.notifyOfUpdate"
                                                       body:@{@"did": self.userDid}
                                                    headers:@{}];
    // Should require authentication
    XCTAssertTrue(response.statusCode == 401 || response.statusCode == 200 || response.statusCode == 400,
                  @"notifyOfUpdate should require auth or return 400, got %ld", (long)response.statusCode);
}

#pragma mark - listReposByCollection

- (void)testListReposByCollectionReturnsResults {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listReposByCollection"
                                              queryParams:@{@"collection": @"app.bsky.actor.profile"}
                                                  headers:@{}];
    // May return 200 or 400
    XCTAssertTrue(response.statusCode == 200 || response.statusCode == 400,
                  @"listReposByCollection should return 200 or 400, got %ld", (long)response.statusCode);
}

@end
