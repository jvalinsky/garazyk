// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
// S20 sub-task C: verifies sub-task B's typed-accessor fixes actually reject
// each type-confusion payload with a 400 InvalidRequest response instead of
// crashing the process. See docs/plans/workstreams/01-security-and-protocol-correctness.md,
// S20 sub-task C.
//
// The "wrong type" set is chosen per field relative to its expected type,
// not a single fixed {null, @1, @[], @{}, @true} set applied uniformly:
// @1/@true are themselves valid NSNumber instances, so testing them against
// a field that expects NSNumber would assert the wrong thing. Each case
// below supplies the subset of {NSNull, @1, @YES, @[], @{}, @"a string"}
// that is genuinely the wrong type for that field.
#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "App/PDSApplication.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/Crypto/JWT.h"

@interface ATProtoServiceConfiguration (Test)
- (void)applyConfig:(NSDictionary *)config;
@end

@interface XRPCFieldCrashSafetyCase : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSDictionary *baseBody;
@property (nonatomic, copy) NSString *field;
@property (nonatomic, copy) NSArray *wrongTypeValues;
@property (nonatomic, assign) BOOL requiresAuth;
@end

@implementation XRPCFieldCrashSafetyCase
@end

@interface XRPCAddRouteCrashSafetyTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *userDid;
@property (nonatomic, copy) NSString *userJwt;
@property (nonatomic, copy) NSString *authHeader;
@end

@implementation XRPCAddRouteCrashSafetyTests

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
    NSDictionary *account = [self.controller createAccountForEmail:@"crashsafety@example.com"
                                                          password:@"password"
                                                            handle:@"crashsafety.test"
                                                               did:nil
                                                             error:&error];
    XCTAssertNil(error);
    self.userDid = account[@"did"];

    NSDictionary *session = [self.controller loginWithHandle:@"crashsafety.test" password:@"password" error:&error];
    XCTAssertNil(error);
    self.userJwt = session[@"accessJwt"];
    XCTAssertNotNil(self.userJwt);
    self.authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
}

- (void)tearDown {
    [self.controller stopServer];
    self.dispatcher = nil;
    self.controller = nil;
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

- (NSArray<XRPCFieldCrashSafetyCase *> *)cases {
    NSArray *stringWrongTypes = @[[NSNull null], @1, @YES, @[], @{}];
    NSArray *numberWrongTypes = @[[NSNull null], @"not-a-number", @[], @{}];

    NSMutableArray<XRPCFieldCrashSafetyCase *> *cases = [NSMutableArray array];

    void (^addCase)(NSString *, NSString *, NSDictionary *, NSString *, NSArray *, BOOL) =
        ^(NSString *name, NSString *path, NSDictionary *baseBody, NSString *field, NSArray *wrongValues, BOOL requiresAuth) {
        XRPCFieldCrashSafetyCase *c = [[XRPCFieldCrashSafetyCase alloc] init];
        c.name = name;
        c.path = path;
        c.baseBody = baseBody;
        c.field = field;
        c.wrongTypeValues = wrongValues;
        c.requiresAuth = requiresAuth;
        [cases addObject:c];
    };

    // com.atproto.server.deactivateAccount — deleteAfter (NSString, optional)
    addCase(@"deactivateAccount.deleteAfter", @"/xrpc/com.atproto.server.deactivateAccount",
            @{}, @"deleteAfter", stringWrongTypes, YES);

    // com.atproto.server.deleteAccount — did/password/token (NSString, required auth)
    addCase(@"deleteAccount.did", @"/xrpc/com.atproto.server.deleteAccount",
            @{@"password": @"password", @"token": @"tok"}, @"did", stringWrongTypes, YES);
    addCase(@"deleteAccount.password", @"/xrpc/com.atproto.server.deleteAccount",
            @{@"did": @"did:plc:whatever", @"token": @"tok"}, @"password", stringWrongTypes, YES);
    addCase(@"deleteAccount.token", @"/xrpc/com.atproto.server.deleteAccount",
            @{@"did": @"did:plc:whatever", @"password": @"password"}, @"token", stringWrongTypes, YES);

    // com.atproto.server.createAppPassword — name (NSString), privileged (NSNumber, optional)
    addCase(@"createAppPassword.name", @"/xrpc/com.atproto.server.createAppPassword",
            @{}, @"name", stringWrongTypes, YES);
    addCase(@"createAppPassword.privileged", @"/xrpc/com.atproto.server.createAppPassword",
            @{@"name": @"my-app"}, @"privileged", numberWrongTypes, YES);

    // app.bsky.graph.muteActor — actor (NSString)
    addCase(@"muteActor.actor", @"/xrpc/app.bsky.graph.muteActor",
            @{}, @"actor", stringWrongTypes, YES);

    // com.atproto.identity.updateHandle — handle (NSString)
    addCase(@"updateHandle.handle", @"/xrpc/com.atproto.identity.updateHandle",
            @{}, @"handle", stringWrongTypes, YES);

    // com.atproto.repo.deleteBlob — blob (NSString ATProtoCID)
    addCase(@"deleteBlob.blob", @"/xrpc/com.atproto.repo.deleteBlob",
            @{}, @"blob", stringWrongTypes, YES);

    return cases;
}

- (void)testTypeConfusionPayloadsReturnInvalidRequestNotCrash {
    for (XRPCFieldCrashSafetyCase *testCase in self.cases) {
        for (id wrongValue in testCase.wrongTypeValues) {
            NSMutableDictionary *body = [testCase.baseBody mutableCopy];
            body[testCase.field] = wrongValue;

            NSDictionary *headers = testCase.requiresAuth ? @{@"authorization": self.authHeader} : @{};
            HttpResponse *response = [self sendJsonRequestWithPath:testCase.path body:body headers:headers];

            // The process is still alive to observe this at all — the crash
            // this sub-task guards against is an uncaught
            // NSInvalidArgumentException tearing down the whole test binary,
            // which would prevent any assertion below (or any later test in
            // this suite) from ever running.
            XCTAssertEqual(response.statusCode, HttpStatusBadRequest,
                            @"%@ with wrong-typed value %@ (class %@) should return 400, got %ld",
                            testCase.name, wrongValue, [wrongValue class], (long)response.statusCode);
            XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest",
                                  @"%@ with wrong-typed value %@ should report InvalidRequest, got %@",
                                  testCase.name, wrongValue, response.jsonBody[@"error"]);
        }
    }
}

@end
