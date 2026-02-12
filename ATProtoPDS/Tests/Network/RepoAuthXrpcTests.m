#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface RepoAuthXrpcTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) XrpcDispatcher *dispatcher;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *did1;
@property (nonatomic, copy) NSString *did2;
@property (nonatomic, copy) NSString *accessJwt1;
@property (nonatomic, copy) NSString *refreshJwt1;
@end

@implementation RepoAuthXrpcTests

- (void)setUp {
    [super setUp];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    self.controller = [[PDSController alloc] initWithDirectory:self.tempURL.path serviceMaxSize:10 userDatabaseSize:10];
    self.dispatcher = [[XrpcDispatcher alloc] init];
    [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher controller:self.controller];

    NSError *error = nil;
    NSDictionary *account1 = [self.controller createAccountForEmail:@"repoauth1@example.com"
                                                          password:@"password"
                                                            handle:@"repoauth1.test"
                                                               did:nil
                                                             error:&error];
    XCTAssertNil(error);
    self.did1 = account1[@"did"];

    NSDictionary *account2 = [self.controller createAccountForEmail:@"repoauth2@example.com"
                                                          password:@"password"
                                                            handle:@"repoauth2.test"
                                                               did:nil
                                                             error:&error];
    XCTAssertNil(error);
    self.did2 = account2[@"did"];

    NSDictionary *session = [self.controller loginWithHandle:@"repoauth1.test" password:@"password" error:&error];
    XCTAssertNil(error);
    self.accessJwt1 = session[@"accessJwt"];
    self.refreshJwt1 = session[@"refreshJwt"];
    XCTAssertNotNil(self.accessJwt1);
    XCTAssertNotNil(self.refreshJwt1);
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.tempURL error:nil];
    [super tearDown];
}

- (NSString *)iso8601String {
    if (@available(macOS 10.12, iOS 10.0, *)) {
        NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        return [formatter stringFromDate:[NSDate date]];
    }
    return [[NSDate date] description];
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
                                 headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *allHeaders = [NSMutableDictionary dictionary];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:path
                                                   queryString:@""
                                                   queryParams:@{}
                                                       version:@"1.1"
                                                       headers:allHeaders
                                                          body:nil
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (HttpResponse *)sendGetRequestWithPath:(NSString *)path
                             queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                                 headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *allHeaders = [NSMutableDictionary dictionary];
    if (headers) {
        [allHeaders addEntriesFromDictionary:headers];
    }

    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                  methodString:@"GET"
                                                          path:path
                                                   queryString:@""
                                                   queryParams:queryParams ?: @{}
                                                       version:@"1.1"
                                                       headers:allHeaders
                                                          body:nil
                                                 remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [[HttpResponse alloc] init];
    [self.dispatcher handleRequest:request response:response];
    return response;
}

- (HttpResponse *)sendRawPostRequestWithPath:(NSString *)path
                                    bodyData:(NSData *)bodyData
                                     headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableDictionary *allHeaders = [NSMutableDictionary dictionary];
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

- (void)testDeleteRecordRequiresAuth {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"delete auth test",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.controller createRecordForDid:self.did1
                                                     collection:@"app.bsky.feed.post"
                                                        record:record
                                                validationMode:PDSValidationModeRequired
                                                         error:nil];
    XCTAssertNotNil(created);
    NSString *uri = created[@"uri"];
    NSString *rkey = [[uri componentsSeparatedByString:@"/"] lastObject];

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.deleteRecord"
                                                      body:@{@"repo": self.did1,
                                                             @"collection": @"app.bsky.feed.post",
                                                             @"rkey": rkey}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutRecordRequiresAuth {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"put auth test",
        @"createdAt": [self iso8601String]
    };
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.putRecord"
                                                      body:@{@"repo": self.did1,
                                                             @"collection": @"app.bsky.feed.post",
                                                             @"rkey": @"auth-test",
                                                             @"record": record}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testApplyWritesRequiresAuth {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"apply auth test",
        @"createdAt": [self iso8601String]
    };
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.applyWrites"
                                                      body:@{@"repo": self.did1,
                                                             @"writes": @[@{@"action": @"create",
                                                                            @"collection": @"app.bsky.feed.post",
                                                                            @"record": record}]}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testPutRecordRepoMismatchForbidden {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"put mismatch test",
        @"createdAt": [self iso8601String]
    };
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.putRecord"
                                                      body:@{@"repo": self.did2,
                                                             @"collection": @"app.bsky.feed.post",
                                                             @"rkey": @"auth-mismatch",
                                                             @"record": record}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testDeleteSessionRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deleteSession"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testDeleteSessionRevokesRefreshTokens {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deleteSession"
                                                      body:@{}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody isKindOfClass:[NSDictionary class]]);
    XCTAssertEqual(((NSDictionary *)response.jsonBody).count, 0U);

    NSError *error = nil;
    NSDictionary *refreshed = [self.controller refreshAccessToken:self.refreshJwt1 error:&error];
    XCTAssertNil(refreshed);
    XCTAssertNotNil(error);
}

- (void)testCreateInviteCodeRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createInviteCode"
                                                      body:@{@"useCount": @1}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testCreateInviteCodeCreatesInviteInDatabase {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createInviteCode"
                                                      body:@{@"useCount": @2}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody isKindOfClass:[NSDictionary class]]);
    NSString *code = ((NSDictionary *)response.jsonBody)[@"code"];
    XCTAssertNotNil(code);
    XCTAssertTrue([code isKindOfClass:[NSString class]]);
    XCTAssertTrue(code.length > 0);

    NSError *error = nil;
    NSString *dbCode = [self.controller.serviceDatabases getInviteCodeForAccount:self.did1 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(dbCode);
    XCTAssertEqualObjects(dbCode, code);
}

- (void)testCreateInviteCodesRejectsOtherAccounts {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createInviteCodes"
                                                      body:@{@"codeCount": @1,
                                                             @"useCount": @1,
                                                             @"forAccounts": @[self.did2]}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testCreateInviteCodesCreatesMultipleForSelf {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createInviteCodes"
                                                      body:@{@"codeCount": @3,
                                                             @"useCount": @1}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    NSArray *codesByAccount = response.jsonBody[@"codes"];
    XCTAssertNotNil(codesByAccount);
    XCTAssertTrue([codesByAccount isKindOfClass:[NSArray class]]);
    XCTAssertEqual(codesByAccount.count, 1U);

    NSDictionary *entry = codesByAccount.firstObject;
    XCTAssertEqualObjects(entry[@"account"], self.did1);
    NSArray *codes = entry[@"codes"];
    XCTAssertNotNil(codes);
    XCTAssertTrue([codes isKindOfClass:[NSArray class]]);
    XCTAssertEqual(codes.count, 3U);
}

- (void)testCreateAppPasswordRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createAppPassword"
                                                      body:@{@"name": @"test-app"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testAppPasswordAllowsCreateSessionAndCanBeRevoked {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    HttpResponse *createdResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createAppPassword"
                                                             body:@{@"name": @"test-app"}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(createdResponse.statusCode, 200);
    NSString *appPassword = createdResponse.jsonBody[@"password"];
    XCTAssertNotNil(appPassword);
    XCTAssertTrue([appPassword isKindOfClass:[NSString class]]);
    XCTAssertTrue(appPassword.length > 0);

    HttpResponse *listResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.server.listAppPasswords"
                                                     headers:@{@"authorization": authHeader}];
    XCTAssertEqual(listResponse.statusCode, 200);
    NSArray *passwords = listResponse.jsonBody[@"passwords"];
    XCTAssertNotNil(passwords);
    XCTAssertTrue([passwords isKindOfClass:[NSArray class]]);
    XCTAssertTrue(passwords.count >= 1U);
    NSDictionary *first = passwords.firstObject;
    XCTAssertNil(first[@"password"]);

    HttpResponse *sessionResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createSession"
                                                            body:@{@"identifier": @"repoauth1.test",
                                                                   @"password": appPassword}
                                                         headers:@{}];
    XCTAssertEqual(sessionResponse.statusCode, 200);
    XCTAssertNotNil(sessionResponse.jsonBody[@"accessJwt"]);

    HttpResponse *revokeResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.revokeAppPassword"
                                                           body:@{@"name": @"test-app"}
                                                        headers:@{@"authorization": authHeader}];
    XCTAssertEqual(revokeResponse.statusCode, 200);

    HttpResponse *sessionAfterRevoke = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createSession"
                                                                body:@{@"identifier": @"repoauth1.test",
                                                                       @"password": appPassword}
                                                             headers:@{}];
    XCTAssertEqual(sessionAfterRevoke.statusCode, 401);
}

- (void)testGetAccountInviteCodesRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.server.getAccountInviteCodes"
                                               queryParams:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetAccountInviteCodesReturnsInviteCodeObjects {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *createCodeResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createInviteCode"
                                                                body:@{@"useCount": @2}
                                                             headers:@{@"authorization": authHeader}];
    XCTAssertEqual(createCodeResponse.statusCode, 200);
    NSString *createdCode = createCodeResponse.jsonBody[@"code"];
    XCTAssertNotNil(createdCode);

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.server.getAccountInviteCodes"
                                               queryParams:@{@"includeUsed": @"true"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    NSArray *codes = response.jsonBody[@"codes"];
    XCTAssertNotNil(codes);
    XCTAssertTrue([codes isKindOfClass:[NSArray class]]);
    XCTAssertTrue(codes.count >= 1U);

    NSDictionary *first = codes.firstObject;
    XCTAssertTrue([first isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(first[@"code"], createdCode);
    XCTAssertNotNil(first[@"available"]);
    XCTAssertNotNil(first[@"disabled"]);
    XCTAssertEqualObjects(first[@"forAccount"], self.did1);
    XCTAssertEqualObjects(first[@"createdBy"], self.did1);
    XCTAssertNotNil(first[@"createdAt"]);
    XCTAssertTrue([first[@"uses"] isKindOfClass:[NSArray class]]);
}

- (void)testRequestEmailConfirmationRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestEmailConfirmation"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRequestEmailConfirmationSucceedsWithAuth {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestEmailConfirmation"
                                                      body:@{}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody isKindOfClass:[NSDictionary class]]);
    XCTAssertEqual(((NSDictionary *)response.jsonBody).count, 0U);
}

- (void)testRequestEmailUpdateRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestEmailUpdate"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRequestEmailUpdateReturnsTokenRequired {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestEmailUpdate"
                                                      body:@{}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"tokenRequired"], @NO);
}

- (void)testUpdateEmailRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.updateEmail"
                                                      body:@{@"email": @"updated@example.com"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUpdateEmailUpdatesAccountEmail {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.updateEmail"
                                                      body:@{@"email": @"updated@example.com"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSError *error = nil;
    NSDictionary *account = [self.controller getAccountForDid:self.did1 error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(account[@"email"], @"updated@example.com");
}

- (void)testIdentityUpdateHandleRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.updateHandle"
                                                      body:@{@"handle": @"repoauth1-renamed.test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testIdentityUpdateHandleUpdatesAccountHandle {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.updateHandle"
                                                      body:@{@"handle": @"repoauth1-renamed.test"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSError *error = nil;
    NSDictionary *account = [self.controller getAccountForDid:self.did1 error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(account[@"handle"], @"repoauth1-renamed.test");

    NSDictionary *session = [self.controller loginWithHandle:@"repoauth1-renamed.test" password:@"password" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(session[@"accessJwt"]);
}

- (void)testRefreshIdentityReturnsIdentityInfo {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.refreshIdentity"
                                                      body:@{@"identifier": @"repoauth1.test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"did"], self.did1);
    XCTAssertNotNil(response.jsonBody[@"didDoc"]);
    XCTAssertNotNil(response.jsonBody[@"handle"]);
}

- (void)testReserveSigningKeyReturnsDidKey {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.reserveSigningKey"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    NSString *signingKey = response.jsonBody[@"signingKey"];
    XCTAssertNotNil(signingKey);
    XCTAssertTrue([signingKey hasPrefix:@"did:key:"]);
}

- (void)testRequestAndResetPasswordFlowWithDidToken {
    HttpResponse *requestMissingEmail = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestPasswordReset"
                                                                 body:@{}
                                                              headers:@{}];
    XCTAssertEqual(requestMissingEmail.statusCode, 400);

    HttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestPasswordReset"
                                                             body:@{@"email": @"repoauth1@example.com"}
                                                          headers:@{}];
    XCTAssertEqual(requestResponse.statusCode, 200);

    HttpResponse *resetResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.resetPassword"
                                                           body:@{@"token": self.did1,
                                                                  @"password": @"new-password-123"}
                                                        headers:@{}];
    XCTAssertEqual(resetResponse.statusCode, 200);

    HttpResponse *sessionResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createSession"
                                                            body:@{@"identifier": @"repoauth1.test",
                                                                   @"password": @"new-password-123"}
                                                         headers:@{}];
    XCTAssertEqual(sessionResponse.statusCode, 200);
}

- (void)testIdentitySignAndSubmitPlcOperation {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    HttpResponse *requestSignature = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.requestPlcOperationSignature"
                                                              body:@{}
                                                           headers:@{@"authorization": authHeader}];
    XCTAssertEqual(requestSignature.statusCode, 200);

    HttpResponse *signResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.signPlcOperation"
                                                          body:@{}
                                                       headers:@{@"authorization": authHeader}];
    XCTAssertEqual(signResponse.statusCode, 200);
    NSDictionary *operation = signResponse.jsonBody[@"operation"];
    XCTAssertNotNil(operation);
    XCTAssertEqualObjects(operation[@"did"], self.did1);
    XCTAssertNotNil(operation[@"sig"]);

    HttpResponse *submitResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.identity.submitPlcOperation"
                                                            body:@{@"operation": operation}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(submitResponse.statusCode, 200);
}

- (void)testConfirmEmailAndRequestAccountDeleteRequireAuth {
    HttpResponse *confirmWithoutAuth = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.confirmEmail"
                                                                body:@{@"email": @"repoauth1@example.com", @"token": @"123456"}
                                                             headers:@{}];
    XCTAssertEqual(confirmWithoutAuth.statusCode, 401);

    HttpResponse *deleteWithoutAuth = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
                                                               body:@{}
                                                            headers:@{}];
    XCTAssertEqual(deleteWithoutAuth.statusCode, 401);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *confirmWithAuth = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.confirmEmail"
                                                             body:@{@"email": @"repoauth1@example.com", @"token": @"123456"}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(confirmWithAuth.statusCode, 200);

    HttpResponse *deleteWithAuth = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
                                                            body:@{}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(deleteWithAuth.statusCode, 200);
}

- (void)testRepoListMissingBlobsRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.listMissingBlobs"
                                               queryParams:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRepoListMissingBlobsReturnsEmptyList {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.listMissingBlobs"
                                               queryParams:@{@"limit": @"10"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertNotNil(response.jsonBody[@"blobs"]);
    XCTAssertTrue([response.jsonBody[@"blobs"] isKindOfClass:[NSArray class]]);
}

- (void)testRepoImportRepoRequiresAuth {
    NSData *carData = [@"fakecar" dataUsingEncoding:NSUTF8StringEncoding];
    HttpResponse *response = [self sendRawPostRequestWithPath:@"/xrpc/com.atproto.repo.importRepo"
                                                     bodyData:carData
                                                      headers:@{
                                                          @"content-type": @"application/vnd.ipld.car",
                                                          @"content-length": [NSString stringWithFormat:@"%lu", (unsigned long)carData.length]
                                                      }];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRepoImportRepoRequiresContentLengthHeader {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    NSData *carData = [@"fakecar" dataUsingEncoding:NSUTF8StringEncoding];
    HttpResponse *response = [self sendRawPostRequestWithPath:@"/xrpc/com.atproto.repo.importRepo"
                                                     bodyData:carData
                                                      headers:@{
                                                          @"authorization": authHeader,
                                                          @"content-type": @"application/vnd.ipld.car"
                                                      }];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testRepoImportRepoAcceptsCARPayload {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    NSData *carData = [@"fakecar" dataUsingEncoding:NSUTF8StringEncoding];
    HttpResponse *response = [self sendRawPostRequestWithPath:@"/xrpc/com.atproto.repo.importRepo"
                                                     bodyData:carData
                                                      headers:@{
                                                          @"authorization": authHeader,
                                                          @"content-type": @"application/vnd.ipld.car",
                                                          @"content-length": [NSString stringWithFormat:@"%lu", (unsigned long)carData.length]
                                                      }];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody isKindOfClass:[NSDictionary class]]);
    XCTAssertEqual(((NSDictionary *)response.jsonBody).count, 0U);
}

- (void)testSyncGetRepoStatusReturnsActiveForExistingRepo {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepoStatus"
                                               queryParams:@{@"did": self.did1}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"did"], self.did1);
    XCTAssertEqualObjects(response.jsonBody[@"active"], @YES);
}

- (void)testSyncGetRepoStatusReturnsNotFoundForMissingRepo {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepoStatus"
                                               queryParams:@{@"did": @"did:plc:aaaaaaaaaaaaaaaaaaaaaaaa"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 404);
}

- (void)testSyncGetCheckoutRequiresDid {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getCheckout"
                                               queryParams:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testSyncGetCheckoutReturnsCAR {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"checkout test",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.controller createRecordForDid:self.did1
                                                     collection:@"app.bsky.feed.post"
                                                         record:record
                                                 validationMode:PDSValidationModeRequired
                                                          error:nil];
    XCTAssertNotNil(created);

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getCheckout"
                                               queryParams:@{@"did": self.did1}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.contentType, @"application/vnd.ipld.car");
    XCTAssertNotNil(response.body);
    XCTAssertTrue(response.body.length > 0);
}

- (void)testSyncListHostsReturnsHosts {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listHosts"
                                               queryParams:@{@"limit": @"10"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    NSArray *hosts = response.jsonBody[@"hosts"];
    XCTAssertTrue([hosts isKindOfClass:[NSArray class]]);
    XCTAssertTrue(hosts.count >= 1U);
    NSDictionary *first = hosts.firstObject;
    XCTAssertTrue([first[@"hostname"] isKindOfClass:[NSString class]]);
    XCTAssertNotNil(first[@"status"]);
    XCTAssertNotNil(first[@"accountCount"]);
}

- (void)testSyncGetHostStatusReturnsNotFoundForUnknownHost {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getHostStatus"
                                               queryParams:@{@"hostname": @"unknown.example.test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 404);
}

- (void)testSyncGetHostStatusReturnsExistingHost {
    HttpResponse *hostsResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listHosts"
                                                    queryParams:@{}
                                                        headers:@{}];
    XCTAssertEqual(hostsResponse.statusCode, 200);
    NSArray *hosts = hostsResponse.jsonBody[@"hosts"];
    XCTAssertTrue([hosts isKindOfClass:[NSArray class]]);
    XCTAssertTrue(hosts.count >= 1U);
    NSString *hostname = hosts.firstObject[@"hostname"];
    XCTAssertTrue([hostname isKindOfClass:[NSString class]]);

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getHostStatus"
                                               queryParams:@{@"hostname": hostname}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"hostname"], hostname);
    XCTAssertNotNil(response.jsonBody[@"status"]);
}

- (void)testSyncListReposReturnsRepoEntries {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"list repos test",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.controller createRecordForDid:self.did1
                                                     collection:@"app.bsky.feed.post"
                                                         record:record
                                                 validationMode:PDSValidationModeRequired
                                                          error:nil];
    XCTAssertNotNil(created);

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listRepos"
                                               queryParams:@{@"limit": @"100"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    NSArray *repos = response.jsonBody[@"repos"];
    XCTAssertTrue([repos isKindOfClass:[NSArray class]]);
    XCTAssertTrue(repos.count >= 1U);

    BOOL foundDid1 = NO;
    for (NSDictionary *entry in repos) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        if ([entry[@"did"] isEqualToString:self.did1]) {
            foundDid1 = YES;
            XCTAssertTrue([entry[@"head"] isKindOfClass:[NSString class]]);
            XCTAssertTrue([entry[@"rev"] isKindOfClass:[NSString class]]);
        }
    }
    XCTAssertTrue(foundDid1);
}

- (void)testSyncListReposByCollectionReturnsMatchingRepos {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"collection listing test",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.controller createRecordForDid:self.did1
                                                     collection:@"app.bsky.feed.post"
                                                         record:record
                                                 validationMode:PDSValidationModeRequired
                                                          error:nil];
    XCTAssertNotNil(created);

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.listReposByCollection"
                                               queryParams:@{@"collection": @"app.bsky.feed.post", @"limit": @"100"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    NSArray *repos = response.jsonBody[@"repos"];
    XCTAssertTrue([repos isKindOfClass:[NSArray class]]);

    NSMutableSet<NSString *> *repoDids = [NSMutableSet set];
    for (NSDictionary *entry in repos) {
        if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"did"] isKindOfClass:[NSString class]]) {
            [repoDids addObject:entry[@"did"]];
        }
    }
    XCTAssertTrue([repoDids containsObject:self.did1]);
    XCTAssertFalse([repoDids containsObject:self.did2]);
}

- (void)testSyncRequestCrawlRequiresHostname {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.sync.requestCrawl"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testSyncRequestCrawlAcceptsHostname {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.sync.requestCrawl"
                                                      body:@{@"hostname": @"example.test"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
}

- (void)testSyncGetRecordReturnsCARWithoutAuth {
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"sync getRecord test",
        @"createdAt": [self iso8601String]
    };
    NSDictionary *created = [self.controller createRecordForDid:self.did1
                                                     collection:@"app.bsky.feed.post"
                                                        record:record
                                                validationMode:PDSValidationModeRequired
                                                         error:nil];
    XCTAssertNotNil(created);
    NSString *uri = created[@"uri"];
    NSString *rkey = [[uri componentsSeparatedByString:@"/"] lastObject];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRecord"
                                              queryParams:@{@"did": self.did1,
                                                           @"collection": @"app.bsky.feed.post",
                                                           @"rkey": rkey ?: @""}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.contentType, @"application/vnd.ipld.car");
    XCTAssertNotNil(response.body);
    XCTAssertTrue(response.body.length > 0);
}

@end
