// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "RepoAuthXrpcTestBase.h"
#import "Database/Service/ServiceDatabases.h"

@interface RepoAuthServerTests : RepoAuthXrpcTestBase
@end

@implementation RepoAuthServerTests

- (void)testDeleteSessionReturns401WithoutAuth {
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

- (void)testCreateInviteCodesReturnsForbiddenForOtherAccounts {
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

- (void)testCreateAppPasswordReturns401WithoutAuth {
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

- (void)testGetAccountInviteCodesReturns401WithoutAuth {
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

- (void)testUpdateEmailReturns401WithoutAuth {
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

@end
