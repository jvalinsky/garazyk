// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "App/PDSApplication.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "Admin/PDSAdminAuth.h"

@interface AdminAuthXrpcTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *adminDid;
@property (nonatomic, copy) NSString *adminJwt;
@property (nonatomic, copy) NSString *userDid;
@property (nonatomic, copy) NSString *userJwt;
@property (nonatomic, copy) NSString *userRefreshJwt;
@end

@implementation AdminAuthXrpcTests

- (void)setUp {
    [super setUp];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:self.tempURL.path];
    self.controller = app.legacyController;
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher application:app];

    NSError *error = nil;
    NSDictionary *adminAccount = [self.controller createAccountForEmail:@"admin@example.com"
                                                               password:@"password"
                                                                 handle:@"administrator.test"
                                                                    did:nil
                                                                  error:&error];
    XCTAssertNil(error);
    self.adminDid = adminAccount[@"did"];

    setenv("PDS_ADMIN_PASSWORD", "password", 1);
    NSError *adminAuthError = nil;
    BOOL adminAuthSuccess = [[PDSAdminAuth sharedAuth] authenticateWithPassword:@"password" error:&adminAuthError];
    XCTAssertTrue(adminAuthSuccess);
    XCTAssertNil(adminAuthError);
    self.adminJwt = [PDSAdminAuth sharedAuth].adminToken;
    XCTAssertNotNil(self.adminJwt);
    NSString *adminAuthHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    XCTAssertTrue([[PDSAdminAuth sharedAuth] isAuthenticatedWithRequest:@{@"authorization": adminAuthHeader}]);

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
    self.userRefreshJwt = session[@"refreshJwt"];
    XCTAssertNotNil(self.userJwt);
    XCTAssertNotNil(self.userRefreshJwt);
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

- (NSNumber *)inviteEnabledForAccountDid:(NSString *)did error:(NSError **)error {
    PDSDatabase *db = [self.controller serviceDatabaseWithError:error];
    if (!db) {
        return nil;
    }

    NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:@"SELECT invite_enabled FROM accounts WHERE did = ?"
                                                           params:@[did]
                                                            error:error];
    if (!rows || rows.count == 0) {
        return nil;
    }
    id value = rows.firstObject[@"invite_enabled"];
    return [value respondsToSelector:@selector(integerValue)] ? @([value integerValue]) : nil;
}

- (NSNumber *)disabledCountForInviteCodesForAccountDid:(NSString *)did error:(NSError **)error {
    PDSDatabase *db = [self.controller serviceDatabaseWithError:error];
    if (!db) {
        return nil;
    }

    NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:@"SELECT COUNT(*) AS disabled_count FROM invite_codes WHERE account_did = ? AND disabled = 1"
                                                           params:@[did]
                                                            error:error];
    if (!rows || rows.count == 0) {
        return nil;
    }
    id value = rows.firstObject[@"disabled_count"];
    return [value respondsToSelector:@selector(integerValue)] ? @([value integerValue]) : nil;
}

- (nullable PDSDatabaseAccount *)accountForDid:(NSString *)did error:(NSError **)error {
    return [self.controller.serviceDatabases getAccountByDid:did error:error];
}

- (nullable NSDictionary *)latestTakedownForSubjectType:(NSString *)subjectType
                                              subjectID:(NSString *)subjectID
                                                  error:(NSError **)error {
    PDSDatabase *db = [self.controller serviceDatabaseWithError:error];
    if (!db) {
        return nil;
    }

    NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:
                                     @"SELECT subjectType, subjectId, takedownRef, applied FROM admin_takedowns WHERE subjectType = ? AND subjectId = ? ORDER BY createdAt DESC LIMIT 1"
                                                              params:@[subjectType, subjectID]
                                                               error:error];
    if (!rows || rows.count == 0) {
        return nil;
    }
    return rows.firstObject;
}

- (NSString *)expectedIssuer {
    NSString *configuredIssuer = [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"];
    if ([configuredIssuer isKindOfClass:[NSString class]] && configuredIssuer.length > 0) {
        return configuredIssuer;
    }

    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NSString *host = config.serverHost;
    NSString *normalized = [[host ?: @"" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL local = normalized.length == 0 ||
                 [normalized isEqualToString:@"localhost"] ||
                 [normalized isEqualToString:@"127.0.0.1"] ||
                 [normalized isEqualToString:@"::1"] ||
                 [normalized isEqualToString:@"0.0.0.0"];
    if (local) {
        host = @"localhost";
    }
    NSString *scheme = local ? @"http" : @"https";
    NSUInteger port = config.serverPort > 0 ? config.serverPort : 2583;
    BOOL defaultPort = ([scheme isEqualToString:@"https"] && port == 443) ||
                       ([scheme isEqualToString:@"http"] && port == 80);
    if (defaultPort) {
        return [NSString stringWithFormat:@"%@://%@", scheme, host];
    }
    return [NSString stringWithFormat:@"%@://%@:%lu", scheme, host, (unsigned long)port];
}

- (nullable NSString *)mintAdminTokenWithIssuer:(NSString *)issuer
                                       audience:(NSString *)audience
                                          scope:(NSString *)scope
                                          error:(NSError **)error {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSInteger issuedAt = (NSInteger)now;
    NSInteger expiresAt = issuedAt + 600;
    NSMutableDictionary *claims = [NSMutableDictionary dictionary];
    claims[@"sub"] = self.adminDid;
    claims[@"scope"] = scope ?: @"admin";
    claims[@"iss"] = issuer;
    claims[@"aud"] = audience;
    claims[@"iat"] = @(issuedAt);
    claims[@"exp"] = @(expiresAt);
    return [self.controller.jwtMinter signPayload:claims error:error];
}

- (void)testGetAccountInfoReturnsUnauthorizedWithoutAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getAccountInfo"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetAccountInfosReturnsUnauthorizedWithoutAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getAccountInfos"
                                              queryString:[NSString stringWithFormat:@"dids=%@", self.userDid]
                                              queryParams:@{@"dids": self.userDid}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetAccountInfoReturnsForbiddenForNonAdmin {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getAccountInfo"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testGetAccountInfosReturnsForbiddenForNonAdmin {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getAccountInfos"
                                              queryString:[NSString stringWithFormat:@"dids=%@", self.userDid]
                                              queryParams:@{@"dids": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testAdminEndpointRejectsTokenWithIssuerMismatch {
    NSString *expectedIssuer = [self expectedIssuer];
    NSError *error = nil;
    NSString *token = [self mintAdminTokenWithIssuer:@"https://issuer-mismatch.example"
                                             audience:expectedIssuer
                                                scope:@"admin"
                                                error:&error];
    XCTAssertNotNil(token);
    XCTAssertNil(error);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", token];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getAccountInfo"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (void)testAdminEndpointRejectsTokenWithAudienceMismatch {
    NSString *expectedIssuer = [self expectedIssuer];
    NSError *error = nil;
    NSString *token = [self mintAdminTokenWithIssuer:expectedIssuer
                                             audience:@"https://audience-mismatch.example"
                                                scope:@"admin"
                                                error:&error];
    XCTAssertNotNil(token);
    XCTAssertNil(error);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", token];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getAccountInfo"
                                              queryString:[NSString stringWithFormat:@"did=%@", self.userDid]
                                              queryParams:@{@"did": self.userDid}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
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

- (void)testGetInviteCodesReturnsUnauthorizedWithoutAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.getInviteCodes"
                                              queryString:@"limit=10"
                                              queryParams:@{@"limit": @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetInviteCodesReturnsForbiddenForNonAdmin {
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

- (void)testSearchAccountsReturnsUnauthorizedWithoutAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.searchAccounts"
                                              queryString:@"limit=10"
                                              queryParams:@{@"limit": @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testSearchAccountsAdminSuccessWithEmailFilter {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.admin.searchAccounts"
                                              queryString:@"email=user%40example.com&limit=10"
                                              queryParams:@{@"email": @"user@example.com", @"limit": @"10"}
                                                  headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    NSArray *accounts = response.jsonBody[@"accounts"];
    XCTAssertTrue([accounts isKindOfClass:[NSArray class]]);
    XCTAssertEqual(accounts.count, 1);
    XCTAssertEqualObjects(accounts.firstObject[@"did"], self.userDid);
}

- (void)testSendEmailReturnsUnauthorizedWithoutAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.sendEmail"
                                                      body:@{
                                                          @"recipientDid": self.userDid,
                                                          @"senderDid": self.adminDid,
                                                          @"content": @"Test moderation email"
                                                      }
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testSendEmailReturnsSuccessForAdmin {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.sendEmail"
                                                      body:@{
                                                          @"recipientDid": self.userDid,
                                                          @"senderDid": self.adminDid,
                                                          @"content": @"Test moderation email",
                                                          @"subject": @"Notice"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"sent"], @YES);
}

- (void)testUpdateAccountEmailAdminSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.updateAccountEmail"
                                                      body:@{@"account": self.userDid, @"email": @"updated-user@example.com"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSError *error = nil;
    PDSDatabaseAccount *account = [self accountForDid:self.userDid error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(account.email, @"updated-user@example.com");
}

- (void)testUpdateAccountHandleAdminSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.updateAccountHandle"
                                                      body:@{@"did": self.userDid, @"handle": @"user-renamed.test"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSError *error = nil;
    PDSDatabaseAccount *account = [self accountForDid:self.userDid error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(account.handle, @"user-renamed.test");
}

- (void)testUpdateAccountPasswordAdminSuccess {
    NSError *error = nil;
    PDSDatabaseAccount *before = [self accountForDid:self.userDid error:&error];
    XCTAssertNil(error);
    NSData *beforeHash = before.passwordHash;
    XCTAssertNotNil(beforeHash);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.updateAccountPassword"
                                                      body:@{@"did": self.userDid, @"password": @"new-password-123"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    PDSDatabaseAccount *after = [self accountForDid:self.userDid error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(after.passwordHash);
    XCTAssertFalse([beforeHash isEqualToData:after.passwordHash]);

    NSDictionary *oldLogin = [self.controller loginWithHandle:@"user.test" password:@"password" error:&error];
    XCTAssertNil(oldLogin);
    XCTAssertNotNil(error);
    error = nil;

    NSDictionary *newLogin = [self.controller loginWithHandle:@"user.test" password:@"new-password-123" error:&error];
    XCTAssertNotNil(newLogin);
    XCTAssertNil(error);

    NSDictionary *refreshed = [self.controller refreshSessionWithRefreshToken:self.userRefreshJwt error:&error];
    XCTAssertNil(refreshed);
    XCTAssertNotNil(error);
}

- (void)testUpdateAccountSigningKeyReturnsSuccessForAdmin {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.updateAccountSigningKey"
                                                      body:@{
                                                          @"did": self.userDid,
                                                          @"signingKey": @"did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

// MARK: - Deprecated Endpoints (410 Gone - migrated to tools.ozone.*)

- (void)testModerateAccountReturnsUnauthorizedWithoutAuth {
    // DEPRECATED: com.atproto.admin.moderateAccount -> tools.ozone.moderation.emitEvent
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateAccount"
                                                      body:@{@"did": self.userDid, @"reason": @"test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 410);  // HttpStatusGone - endpoint deprecated
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"MethodNotSupported");
}

- (void)testModerateAccountReturnsForbiddenForNonAdmin {
    // DEPRECATED: com.atproto.admin.moderateAccount -> tools.ozone.moderation.emitEvent
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateAccount"
                                                      body:@{@"did": self.userDid, @"reason": @"test"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 410);  // HttpStatusGone - endpoint deprecated
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"MethodNotSupported");
}

- (void)testModerateAccountAdminSuccessPersistsStatus {
    // DEPRECATED: com.atproto.admin.moderateAccount -> tools.ozone.moderation.emitEvent
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateAccount"
                                                      body:@{
                                                          @"did": self.userDid,
                                                          @"action": @"takedown",
                                                          @"reason": @"policy"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 410);  // HttpStatusGone - endpoint deprecated
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"MethodNotSupported");
}

- (void)testModerateRecordAdminSuccessPersistsStatus {
    // DEPRECATED: com.atproto.admin.moderateRecord -> tools.ozone.moderation.emitEvent
    NSString *recordURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/1", self.userDid];
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.moderateRecord"
                                                      body:@{
                                                          @"uri": recordURI,
                                                          @"action": @"takedown",
                                                          @"reason": @"policy"
                                                      }
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 410);  // HttpStatusGone - endpoint deprecated
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"MethodNotSupported");
}

- (void)testTakeDownAccountReturnsUnauthorizedWithoutAuth {
    // DEPRECATED: com.atproto.admin.takeDownAccount -> tools.ozone.moderation.emitEvent
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.takeDownAccount"
                                                      body:@{@"did": self.userDid, @"reason": @"test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 410);  // HttpStatusGone - endpoint deprecated
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"MethodNotSupported");
}

- (void)testAdminDeleteAccountReturnsUnauthorizedWithoutAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.deleteAccount"
                                                      body:@{@"did": self.userDid}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testAdminDeleteAccountReturnsForbiddenForNonAdmin {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.deleteAccount"
                                                      body:@{@"did": self.userDid}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testAdminDeleteAccountSuccess {
    NSError *error = nil;
    NSDictionary *target = [self.controller createAccountForEmail:@"target@example.com"
                                                          password:@"password"
                                                            handle:@"target.test"
                                                               did:nil
                                                             error:&error];
    XCTAssertNotNil(target);
    XCTAssertNil(error);

    NSString *targetDid = target[@"did"];
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.deleteAccount"
                                                      body:@{@"did": targetDid}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSDictionary *account = [self.controller getAccountForDid:targetDid error:&error];
    XCTAssertNil(account);
}

- (void)testDisableAccountInvitesReturnsUnauthorizedWithoutAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.disableAccountInvites"
                                                      body:@{@"account": self.userDid}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testDisableAccountInvitesReturnsForbiddenForNonAdmin {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.disableAccountInvites"
                                                      body:@{@"account": self.userDid}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testEnableDisableAccountInvitesAdminSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];

    HttpResponse *enableResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.enableAccountInvites"
                                                            body:@{@"account": self.userDid}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(enableResponse.statusCode, 200);

    NSError *error = nil;
    NSNumber *enabledValue = [self inviteEnabledForAccountDid:self.userDid error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(enabledValue.integerValue, 1);

    HttpResponse *disableResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.disableAccountInvites"
                                                             body:@{@"account": self.userDid}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(disableResponse.statusCode, 200);

    NSNumber *disabledValue = [self inviteEnabledForAccountDid:self.userDid error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(disabledValue.integerValue, 0);
}

- (void)testDisableInviteCodesReturnsUnauthorizedWithoutAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.disableInviteCodes"
                                                      body:@{@"accounts": @[self.userDid]}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testDisableInviteCodesAdminSuccess {
    NSError *error = nil;
    NSString *extraInviteCode = [NSString stringWithFormat:@"EXTRA-%@", [[NSUUID UUID] UUIDString]];
    BOOL createdInvite = [self.controller.serviceDatabases createInviteCode:extraInviteCode
                                                                  forAccount:self.userDid
                                                                     maxUses:2
                                                                       error:&error];
    XCTAssertTrue(createdInvite);
    XCTAssertNil(error);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.adminJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.admin.disableInviteCodes"
                                                      body:@{@"codes": @[extraInviteCode], @"accounts": @[self.userDid]}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSNumber *disabledCount = [self disabledCountForInviteCodesForAccountDid:self.userDid error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(disabledCount);
    XCTAssertGreaterThanOrEqual(disabledCount.integerValue, 2);
}

- (void)testLabelCreateReturnsUnauthorizedWithoutAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.label.createLabel"
                                                      body:@{@"src": self.adminDid, @"uri": @"at://did:plc:test/app.bsky.feed.post/1", @"val": @"spam"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testLabelCreateReturnsForbiddenForNonAdmin {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.label.createLabel"
                                                      body:@{@"src": self.adminDid, @"uri": @"at://did:plc:test/app.bsky.feed.post/1", @"val": @"spam"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

@end
