// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

#import "Admin/PDSAdminAuth.h"
#import "App/PDSController.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/PDSHttpPDSAdminRoutePack.h"
#import "Network/PDSHttpServerBuilder.h"

@interface HttpServer (PDSHttpPDSAdminRoutePackTesting)
- (HttpResponse *)dispatchRequest:(HttpRequest *)request;
- (nullable RequestHandler)handlerForRoute:(NSString *)path
                                    method:(NSString *)method
                                parameters:(NSDictionary<NSString *, NSString *> *_Nullable *_Nullable)parameters;
@end

@interface PDSHttpPDSAdminRoutePackTests : XCTestCase
@property(nonatomic, strong) HttpServer *server;
@property(nonatomic, strong) PDSServiceDatabases *databases;
@property(nonatomic, copy) NSString *testDirectory;
@property(nonatomic, copy) NSString *adminToken;
@property(nonatomic, strong) NSDictionary<NSString *, id> *savedEnvValues;
@end

@implementation PDSHttpPDSAdminRoutePackTests

- (NSArray<NSString *> *)managedEnvKeys {
    return @[@"PDS_ADMIN_PASSWORD", @"PDS_ISSUER", @"PDS_REQUIRE_ISSUER", @"PDS_DISABLE_X_ADMIN_TOKEN_HEADER"];
}

- (void)setUp {
    [super setUp];

    NSMutableDictionary<NSString *, id> *saved = [NSMutableDictionary dictionary];
    for (NSString *key in [self managedEnvKeys]) {
        const char *value = getenv(key.UTF8String);
        saved[key] = value ? [NSString stringWithUTF8String:value] : [NSNull null];
    }
    self.savedEnvValues = [saved copy];

    setenv("PDS_ADMIN_PASSWORD", "route-test-password", 1);
    setenv("PDS_ISSUER", "https://administrator.pds.example", 1);
    unsetenv("PDS_REQUIRE_ISSUER");
    unsetenv("PDS_DISABLE_X_ADMIN_TOKEN_HEADER");

    [[PDSAdminAuth sharedAuth] logout];
    (void)[PDSController sharedController];
    NSError *authError = nil;
    XCTAssertTrue([[PDSAdminAuth sharedAuth] authenticateWithPassword:@"route-test-password" error:&authError]);
    XCTAssertNil(authError);
    self.adminToken = [PDSAdminAuth sharedAuth].adminToken;

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"PDSHttpPDSAdminRoutePackTests-%@", NSUUID.UUID.UUIDString]];
    self.databases = [[PDSServiceDatabases alloc] initWithDirectory:self.testDirectory
                                                     serviceMaxSize:4
                                                    didCacheMaxSize:2
                                                  sequencerMaxSize:2];
    self.server = [HttpServer serverWithPort:0];
    [PDSHttpPDSAdminRoutePack registerRoutesWithServer:self.server serviceDatabases:self.databases];
}

- (void)tearDown {
    [[PDSAdminAuth sharedAuth] logout];
    for (NSString *key in [self managedEnvKeys]) {
        id originalValue = self.savedEnvValues[key];
        if ([originalValue isKindOfClass:[NSString class]]) {
            setenv(key.UTF8String, [(NSString *)originalValue UTF8String], 1);
        } else {
            unsetenv(key.UTF8String);
        }
    }
    if (self.testDirectory.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    }
    self.server = nil;
    self.databases = nil;
    self.testDirectory = nil;
    self.adminToken = nil;
    self.savedEnvValues = nil;
    [super tearDown];
}

- (HttpRequest *)requestWithMethod:(HttpMethod)method
                       methodString:(NSString *)methodString
                               path:(NSString *)path
                            headers:(NSDictionary<NSString *, NSString *> *)headers
                           jsonBody:(nullable NSDictionary *)jsonBody {
    NSData *body = [NSData data];
    NSMutableDictionary<NSString *, NSString *> *allHeaders = [headers mutableCopy] ?: [NSMutableDictionary dictionary];
    if (jsonBody) {
        body = [NSJSONSerialization dataWithJSONObject:jsonBody options:0 error:nil];
        allHeaders[@"Content-Type"] = @"application/json";
    }
    return [[HttpRequest alloc] initWithMethod:method
                                  methodString:methodString
                                          path:path
                                   queryString:@""
                                    queryParams:@{}
                                       version:@"HTTP/1.1"
                                       headers:allHeaders
                                          body:body
                                 remoteAddress:@"127.0.0.1"];
}

- (NSDictionary *)authorizedHeaders {
    return @{@"Authorization": [NSString stringWithFormat:@"Bearer %@", self.adminToken]};
}

- (NSDictionary *)jsonFromResponse:(HttpResponse *)response {
    XCTAssertGreaterThan(response.body.length, 0);
    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
    return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

- (NSString *)encodedDID:(NSString *)did {
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"-._~"];
    return [did stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: did;
}

- (void)testBuilderRegistersPrivatePDSAdminRoutes {
    HttpServer *builderServer = [HttpServer serverWithPort:0];
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    builder.serviceDatabases = self.databases;
    builder.enableOAuth = NO;
    builder.enableXrpc = NO;
    builder.enableMSTViewer = NO;
    builder.enableNodeInfo = NO;

    NSError *error = nil;
    XCTAssertTrue([builder configureServer:builderServer error:&error]);
    XCTAssertNil(error);

    RequestHandler handler = [builderServer handlerForRoute:@"/admin/api/accounts/did%3Aplc%3Aalice/sessions"
                                                     method:@"GET"
                                                 parameters:nil];
    XCTAssertNotNil(handler);
}

- (void)testSessionsRequireAdminAuthentication {
    HttpRequest *request = [self requestWithMethod:HttpMethodGET
                                      methodString:@"GET"
                                              path:@"/admin/api/accounts/did%3Aplc%3Aalice/sessions"
                                           headers:@{}
                                          jsonBody:nil];
    HttpResponse *response = [self.server dispatchRequest:request];

    XCTAssertEqual(response.statusCode, HttpStatusUnauthorized);
}

- (void)testListSessionsReturnsTargetDIDHashIDsOnly {
    NSString *targetDID = @"did:plc:target";
    NSString *otherDID = @"did:plc:other";
    XCTAssertTrue([self.databases storeRefreshToken:@"raw-refresh-token-target" forAccountDid:targetDID error:nil]);
    XCTAssertTrue([self.databases storeRefreshToken:@"raw-refresh-token-other" forAccountDid:otherDID error:nil]);

    NSString *path = [NSString stringWithFormat:@"/admin/api/accounts/%@/sessions", [self encodedDID:targetDID]];
    HttpRequest *request = [self requestWithMethod:HttpMethodGET
                                      methodString:@"GET"
                                              path:path
                                           headers:[self authorizedHeaders]
                                          jsonBody:nil];
    HttpResponse *response = [self.server dispatchRequest:request];
    NSDictionary *json = [self jsonFromResponse:response];
    NSArray *sessions = json[@"sessions"];

    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqual(sessions.count, 1U);
    NSDictionary *session = sessions.firstObject;
    XCTAssertEqualObjects(session[@"did"], targetDID);
    XCTAssertEqual([(NSString *)session[@"id"] length], 64U);
    XCTAssertNotEqualObjects(session[@"id"], @"raw-refresh-token-target");
    NSString *body = [[NSString alloc] initWithData:response.body encoding:NSUTF8StringEncoding];
    XCTAssertFalse([body containsString:@"raw-refresh-token-target"]);
}

- (void)testRevokeSessionByHashID {
    NSString *targetDID = @"did:plc:revoke";
    XCTAssertTrue([self.databases storeRefreshToken:@"raw-refresh-token-revoke" forAccountDid:targetDID error:nil]);

    NSString *path = [NSString stringWithFormat:@"/admin/api/accounts/%@/sessions", [self encodedDID:targetDID]];
    HttpResponse *listResponse = [self.server dispatchRequest:[self requestWithMethod:HttpMethodGET
                                                                         methodString:@"GET"
                                                                                 path:path
                                                                              headers:[self authorizedHeaders]
                                                                             jsonBody:nil]];
    NSString *sessionID = [self jsonFromResponse:listResponse][@"sessions"][0][@"id"];
    XCTAssertEqual(sessionID.length, 64U);

    NSString *revokePath = [NSString stringWithFormat:@"/admin/api/accounts/%@/sessions/revoke", [self encodedDID:targetDID]];
    HttpResponse *revokeResponse = [self.server dispatchRequest:[self requestWithMethod:HttpMethodPOST
                                                                           methodString:@"POST"
                                                                                   path:revokePath
                                                                                headers:[self authorizedHeaders]
                                                                               jsonBody:@{@"id": sessionID}]];
    XCTAssertEqual(revokeResponse.statusCode, HttpStatusOK);

    HttpResponse *afterResponse = [self.server dispatchRequest:[self requestWithMethod:HttpMethodGET
                                                                          methodString:@"GET"
                                                                                  path:path
                                                                               headers:[self authorizedHeaders]
                                                                              jsonBody:nil]];
    NSArray *sessions = [self jsonFromResponse:afterResponse][@"sessions"];
    XCTAssertEqual(sessions.count, 0U);
}

- (void)testTargetDIDAppPasswordLifecycle {
    NSString *targetDID = @"did:plc:passwords";
    NSString *basePath = [NSString stringWithFormat:@"/admin/api/accounts/%@/app-passwords", [self encodedDID:targetDID]];

    HttpResponse *createResponse = [self.server dispatchRequest:[self requestWithMethod:HttpMethodPOST
                                                                           methodString:@"POST"
                                                                                   path:basePath
                                                                                headers:[self authorizedHeaders]
                                                                               jsonBody:@{@"name": @"ops", @"privileged": @YES}]];
    NSDictionary *created = [self jsonFromResponse:createResponse];
    XCTAssertEqual(createResponse.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(created[@"did"], targetDID);
    XCTAssertEqualObjects(created[@"name"], @"ops");
    XCTAssertTrue([(NSString *)created[@"password"] length] > 0);

    HttpResponse *listResponse = [self.server dispatchRequest:[self requestWithMethod:HttpMethodGET
                                                                         methodString:@"GET"
                                                                                 path:basePath
                                                                              headers:[self authorizedHeaders]
                                                                             jsonBody:nil]];
    NSArray *passwords = [self jsonFromResponse:listResponse][@"passwords"];
    XCTAssertEqual(passwords.count, 1U);
    XCTAssertEqualObjects(passwords.firstObject[@"did"], targetDID);
    XCTAssertEqualObjects(passwords.firstObject[@"name"], @"ops");
    XCTAssertNil(passwords.firstObject[@"password"]);

    NSString *revokePath = [basePath stringByAppendingString:@"/revoke"];
    HttpResponse *revokeResponse = [self.server dispatchRequest:[self requestWithMethod:HttpMethodPOST
                                                                           methodString:@"POST"
                                                                                   path:revokePath
                                                                                headers:[self authorizedHeaders]
                                                                               jsonBody:@{@"name": @"ops"}]];
    XCTAssertEqual(revokeResponse.statusCode, HttpStatusOK);

    HttpResponse *afterResponse = [self.server dispatchRequest:[self requestWithMethod:HttpMethodGET
                                                                          methodString:@"GET"
                                                                                  path:basePath
                                                                               headers:[self authorizedHeaders]
                                                                              jsonBody:nil]];
    NSArray *afterPasswords = [self jsonFromResponse:afterResponse][@"passwords"];
    XCTAssertEqual(afterPasswords.count, 0U);
}

@end

