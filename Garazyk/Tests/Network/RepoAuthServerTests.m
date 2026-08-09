// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "RepoAuthXrpcTestBase.h"
#import "Database/Service/ServiceDatabases.h"
#import <sqlite3.h>

@interface RepoAuthServerTests : RepoAuthXrpcTestBase
@end

@implementation RepoAuthServerTests

- (void)testDeleteSessionReturns401WithoutAuth {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deleteSession"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testDeleteSessionRevokesRefreshTokens {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deleteSession"
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
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createInviteCode"
                                                      body:@{@"useCount": @1}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testCreateInviteCodeCreatesInviteInDatabase {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createInviteCode"
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
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createInviteCodes"
                                                      body:@{@"codeCount": @1,
                                                             @"useCount": @1,
                                                             @"forAccounts": @[self.did2]}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 403);
}

- (void)testCreateInviteCodesCreatesMultipleForSelf {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createInviteCodes"
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
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createAppPassword"
                                                      body:@{@"name": @"test-app"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testAppPasswordAllowsCreateSessionAndCanBeRevoked {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    ATProtoHttpResponse *createdResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createAppPassword"
                                                             body:@{@"name": @"test-app"}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(createdResponse.statusCode, 200);
    NSString *appPassword = createdResponse.jsonBody[@"password"];
    XCTAssertNotNil(appPassword);
    XCTAssertTrue([appPassword isKindOfClass:[NSString class]]);
    XCTAssertTrue(appPassword.length > 0);

    ATProtoHttpResponse *listResponse = [self sendGetRequestWithPath:@"/xrpc/com.atproto.server.listAppPasswords"
                                                     headers:@{@"authorization": authHeader}];
    XCTAssertEqual(listResponse.statusCode, 200);
    NSArray *passwords = listResponse.jsonBody[@"passwords"];
    XCTAssertNotNil(passwords);
    XCTAssertTrue([passwords isKindOfClass:[NSArray class]]);
    XCTAssertTrue(passwords.count >= 1U);
    NSDictionary *first = passwords.firstObject;
    XCTAssertNil(first[@"password"]);

    ATProtoHttpResponse *sessionResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createSession"
                                                            body:@{@"identifier": @"repoauth1.test",
                                                                   @"password": appPassword}
                                                         headers:@{}];
    XCTAssertEqual(sessionResponse.statusCode, 200);
    XCTAssertNotNil(sessionResponse.jsonBody[@"accessJwt"]);

    ATProtoHttpResponse *revokeResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.revokeAppPassword"
                                                           body:@{@"name": @"test-app"}
                                                        headers:@{@"authorization": authHeader}];
    XCTAssertEqual(revokeResponse.statusCode, 200);

    ATProtoHttpResponse *sessionAfterRevoke = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createSession"
                                                                body:@{@"identifier": @"repoauth1.test",
                                                                       @"password": appPassword}
                                                             headers:@{}];
    XCTAssertEqual(sessionAfterRevoke.statusCode, 401);
}

- (void)testGetAccountInviteCodesReturns401WithoutAuth {
    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.server.getAccountInviteCodes"
                                               queryParams:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetAccountInviteCodesReturnsInviteCodeObjects {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    ATProtoHttpResponse *createCodeResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createInviteCode"
                                                                body:@{@"useCount": @2}
                                                             headers:@{@"authorization": authHeader}];
    XCTAssertEqual(createCodeResponse.statusCode, 200);
    NSString *createdCode = createCodeResponse.jsonBody[@"code"];
    XCTAssertNotNil(createdCode);

    ATProtoHttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/com.atproto.server.getAccountInviteCodes"
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
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestEmailConfirmation"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRequestEmailConfirmationSucceedsWithAuth {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestEmailConfirmation"
                                                      body:@{}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertTrue([response.jsonBody isKindOfClass:[NSDictionary class]]);
    XCTAssertEqual(((NSDictionary *)response.jsonBody).count, 0U);
}

- (void)testRequestEmailUpdateRequiresAuth {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestEmailUpdate"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testRequestEmailUpdateReturnsTokenRequired {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestEmailUpdate"
                                                      body:@{}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqualObjects(response.jsonBody[@"tokenRequired"], @NO);
}

- (void)testUpdateEmailReturns401WithoutAuth {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.updateEmail"
                                                      body:@{@"email": @"updated@example.com"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testUpdateEmailUpdatesAccountEmail {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.updateEmail"
                                                      body:@{@"email": @"updated@example.com"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSError *error = nil;
    NSDictionary *account = [self.controller getAccountForDid:self.did1 error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(account[@"email"], @"updated@example.com");
}

- (void)testReserveSigningKeyReturnsDidKey {
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.reserveSigningKey"
                                                      body:@{}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    NSString *signingKey = response.jsonBody[@"signingKey"];
    XCTAssertNotNil(signingKey);
    XCTAssertTrue([signingKey hasPrefix:@"did:key:"]);
}

- (void)testRequestAndResetPasswordFlowWithOpaqueToken {
    // 1. Missing email → 400.
    ATProtoHttpResponse *requestMissingEmail = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestPasswordReset"
                                                                 body:@{}
                                                              headers:@{}];
    XCTAssertEqual(requestMissingEmail.statusCode, 400);

    // 2. Valid email → 200 (no-leak).
    ATProtoHttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestPasswordReset"
                                                             body:@{@"email": @"repoauth1@example.com"}
                                                          headers:@{}];
    XCTAssertEqual(requestResponse.statusCode, 200);

    // 3. Extract the opaque token from password_reset_tokens.
    sqlite3 *db = (sqlite3 *)[self.controller.serviceDatabases serviceDatabase];
    XCTAssertTrue(db != NULL);

    sqlite3_stmt *stmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db,
        "SELECT token FROM password_reset_tokens WHERE did = ? ORDER BY rowid DESC LIMIT 1",
        -1, &stmt, NULL), SQLITE_OK);
    sqlite3_bind_text(stmt, 1, self.did1.UTF8String, -1, SQLITE_TRANSIENT);

    NSString *token = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *tokenText = sqlite3_column_text(stmt, 0);
        if (tokenText) token = [NSString stringWithUTF8String:(const char *)tokenText];
    }
    sqlite3_finalize(stmt);
    XCTAssertNotNil(token, @"Expected a password reset token to be stored in the database");

    // 4. Reset password with opaque token → 200.
    ATProtoHttpResponse *resetResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.resetPassword"
                                                           body:@{@"token": token,
                                                                  @"password": @"new-password-123"}
                                                        headers:@{}];
    XCTAssertEqual(resetResponse.statusCode, 200);

    // 5. Can create session with new password.
    ATProtoHttpResponse *sessionResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createSession"
                                                            body:@{@"identifier": @"repoauth1.test",
                                                                   @"password": @"new-password-123"}
                                                         headers:@{}];
    XCTAssertEqual(sessionResponse.statusCode, 200);
}

- (void)testRequestPasswordResetNoLeakNonexistentEmail {
    // No-leak: nonexistent email still returns 200.
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestPasswordReset"
                                                      body:@{@"email": @"nonexistent@example.com"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
}

- (void)testResetPasswordRejectsDidAsToken {
    // The old DID-as-token path is removed — a DID no longer works.
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.resetPassword"
                                                      body:@{@"token": self.did1,
                                                             @"password": @"new-password-123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidToken");
}

- (void)testResetPasswordRejectsInvalidToken {
    // A random 64-char hex string that was never minted.
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.resetPassword"
                                                      body:@{@"token": @"0000000000000000000000000000000000000000000000000000000000000000",
                                                             @"password": @"new-password-123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidToken");
}

- (void)testResetPasswordRejectsExpiredToken {
    // Insert an expired token directly into the database.
    sqlite3 *db = (sqlite3 *)[self.controller.serviceDatabases serviceDatabase];
    XCTAssertTrue(db != NULL);

    NSString *expiredToken = [NSString stringWithFormat:@"expired-%lld",
                              (long long)([[NSDate date] timeIntervalSince1970] * 1000.0)];
    NSTimeInterval expiredTime = [[NSDate date] timeIntervalSince1970] - 3600.0; // 1 hour ago

    sqlite3_stmt *stmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db,
        "INSERT INTO password_reset_tokens (token, did, expires_at) VALUES (?, ?, ?)",
        -1, &stmt, NULL), SQLITE_OK);
    sqlite3_bind_text(stmt, 1, expiredToken.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, self.did1.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 3, (sqlite3_int64)expiredTime);
    XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
    sqlite3_finalize(stmt);

    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.resetPassword"
                                                      body:@{@"token": expiredToken,
                                                             @"password": @"new-password-123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"ExpiredToken");
}

- (void)testResetPasswordRejectsReplayToken {
    // 1. Request password reset (stores a token).
    ATProtoHttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestPasswordReset"
                                                             body:@{@"email": @"repoauth1@example.com"}
                                                          headers:@{}];
    XCTAssertEqual(requestResponse.statusCode, 200);

    // 2. Extract token from database.
    sqlite3 *db = (sqlite3 *)[self.controller.serviceDatabases serviceDatabase];
    XCTAssertTrue(db != NULL);

    sqlite3_stmt *stmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db,
        "SELECT token FROM password_reset_tokens WHERE did = ? ORDER BY rowid DESC LIMIT 1",
        -1, &stmt, NULL), SQLITE_OK);
    sqlite3_bind_text(stmt, 1, self.did1.UTF8String, -1, SQLITE_TRANSIENT);

    NSString *token = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *tokenText = sqlite3_column_text(stmt, 0);
        if (tokenText) token = [NSString stringWithUTF8String:(const char *)tokenText];
    }
    sqlite3_finalize(stmt);
    XCTAssertNotNil(token);

    // 3. First reset → 200.
    ATProtoHttpResponse *firstReset = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.resetPassword"
                                                        body:@{@"token": token,
                                                               @"password": @"first-new-password"}
                                                     headers:@{}];
    XCTAssertEqual(firstReset.statusCode, 200);

    // 4. Replay with same token → 400.
    ATProtoHttpResponse *replayReset = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.resetPassword"
                                                         body:@{@"token": token,
                                                                @"password": @"second-new-password"}
                                                      headers:@{}];
    XCTAssertEqual(replayReset.statusCode, 400);
    XCTAssertEqualObjects(replayReset.jsonBody[@"error"], @"InvalidToken");
}

- (void)testConfirmEmailAndRequestAccountDeleteRequireAuth {
    ATProtoHttpResponse *confirmWithoutAuth = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.confirmEmail"
                                                                body:@{@"email": @"repoauth1@example.com", @"token": @"123456"}
                                                             headers:@{}];
    XCTAssertEqual(confirmWithoutAuth.statusCode, 401);

    ATProtoHttpResponse *deleteWithoutAuth = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
                                                               body:@{}
                                                            headers:@{}];
    XCTAssertEqual(deleteWithoutAuth.statusCode, 401);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    ATProtoHttpResponse *confirmWithAuth = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.confirmEmail"
                                                             body:@{@"email": @"repoauth1@example.com", @"token": @"123456"}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(confirmWithAuth.statusCode, 400);
    XCTAssertEqualObjects(confirmWithAuth.jsonBody[@"error"], @"InvalidToken");

    ATProtoHttpResponse *deleteWithAuth = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
                                                            body:@{}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(deleteWithAuth.statusCode, 200);
}

- (void)testDeleteAccountRequiresAuthAndRequiredFields {
    NSDictionary *body = @{@"did": self.did1, @"password": @"password", @"token": @"test-token"};
    ATProtoHttpResponse *unauthorized = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deleteAccount"
                                                           body:body
                                                        headers:@{}];
    XCTAssertEqual(unauthorized.statusCode, HttpStatusUnauthorized);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    NSArray<NSDictionary *> *invalidBodies = @[
        @{@"password": @"password", @"token": @"test-token"},
        @{@"did": self.did1, @"token": @"test-token"},
        @{@"did": self.did1, @"password": @"password"},
        @{@"did": @"", @"password": @"password", @"token": @"test-token"},
        @{@"did": self.did1, @"password": @"", @"token": @"test-token"},
        @{@"did": self.did1, @"password": @"password", @"token": @""},
        @{@"did": @"not-a-did", @"password": @"password", @"token": @"test-token"}
    ];
    for (NSDictionary *invalidBody in invalidBodies) {
        ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deleteAccount"
                                                           body:invalidBody
                                                        headers:@{@"authorization": authHeader}];
        XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
        XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
    }
}

- (void)testRequestAccountDeleteOnlyInitiatesFlowAndDeleteAccountConsumesToken {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    // 1. Request account delete (no token) → 200 (mints token).
    ATProtoHttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
                                                             body:@{}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(requestResponse.statusCode, 200);

    // 2. Extract the opaque token from password_reset_tokens.
    sqlite3 *db = (sqlite3 *)[self.controller.serviceDatabases serviceDatabase];
    XCTAssertTrue(db != NULL);

    sqlite3_stmt *stmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db,
        "SELECT token FROM password_reset_tokens WHERE did = ? ORDER BY rowid DESC LIMIT 1",
        -1, &stmt, NULL), SQLITE_OK);
    sqlite3_bind_text(stmt, 1, self.did1.UTF8String, -1, SQLITE_TRANSIENT);

    NSString *token = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *tokenText = sqlite3_column_text(stmt, 0);
        if (tokenText) token = [NSString stringWithUTF8String:(const char *)tokenText];
    }
    sqlite3_finalize(stmt);
    XCTAssertNotNil(token, @"Expected a delete token to be stored in the database");

    // 3. A token in requestAccountDelete's body cannot delete the account.
    ATProtoHttpResponse *repeatRequest = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
                                                            body:@{@"token": token}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(repeatRequest.statusCode, 200);
    NSError *accountError = nil;
    PDSDatabaseAccount *account = [self.controller.serviceDatabases getAccountByDid:self.did1 error:&accountError];
    XCTAssertNotNil(account);

    // 4. deleteAccount is the only endpoint that consumes the token.
    ATProtoHttpResponse *deleteResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deleteAccount"
                                                            body:@{@"did": self.did1, @"password": @"password", @"token": token}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(deleteResponse.statusCode, 200);
    XCTAssertTrue([deleteResponse.jsonBody isKindOfClass:[NSDictionary class]]);
    XCTAssertEqual(((NSDictionary *)deleteResponse.jsonBody).count, 0U);

    // 5. Account no longer exists.
    account = [self.controller.serviceDatabases getAccountByDid:self.did1 error:&accountError];
    XCTAssertNil(account, @"Account should be deleted");
}

- (void)testDeleteAccountRejectsExpiredToken {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    // Insert an expired token directly into the database.
    sqlite3 *db = (sqlite3 *)[self.controller.serviceDatabases serviceDatabase];
    XCTAssertTrue(db != NULL);

    NSString *expiredToken = [NSString stringWithFormat:@"adexp-%lld",
                              (long long)([[NSDate date] timeIntervalSince1970] * 1000.0)];
    NSTimeInterval expiredTime = [[NSDate date] timeIntervalSince1970] - 3600.0;

    sqlite3_stmt *stmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db,
        "INSERT INTO password_reset_tokens (token, did, expires_at) VALUES (?, ?, ?)",
        -1, &stmt, NULL), SQLITE_OK);
    sqlite3_bind_text(stmt, 1, expiredToken.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, self.did1.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 3, (sqlite3_int64)expiredTime);
    XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
    sqlite3_finalize(stmt);

    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deleteAccount"
                                                      body:@{@"did": self.did1, @"password": @"password", @"token": expiredToken}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"ExpiredToken");
}

- (void)testDeleteAccountClaimsTokenBeforeDeletion {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    // 1. Request account delete (no token) → 200 (stores token).
    ATProtoHttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
                                                             body:@{}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(requestResponse.statusCode, 200);

    // 2. Extract token from database.
    sqlite3 *db = (sqlite3 *)[self.controller.serviceDatabases serviceDatabase];
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(db,
        "SELECT token FROM password_reset_tokens WHERE did = ? ORDER BY rowid DESC LIMIT 1",
        -1, &stmt, NULL);
    sqlite3_bind_text(stmt, 1, self.did1.UTF8String, -1, SQLITE_TRANSIENT);

    NSString *token = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *tokenText = sqlite3_column_text(stmt, 0);
        if (tokenText) token = [NSString stringWithUTF8String:(const char *)tokenText];
    }
    sqlite3_finalize(stmt);
    XCTAssertNotNil(token);

    // 3. A failed deletion still claims the token before service deletion.
    ATProtoHttpResponse *firstDelete = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deleteAccount"
                                                         body:@{@"did": self.did1, @"password": @"wrong-password", @"token": token}
                                                      headers:@{@"authorization": authHeader}];
    XCTAssertEqual(firstDelete.statusCode, 400);
    XCTAssertEqualObjects(firstDelete.jsonBody[@"error"], @"AccountDeletionFailed");

    // 4. The claimed token cannot be replayed, and the account was retained.
    ATProtoHttpResponse *replayDelete = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deleteAccount"
                                                          body:@{@"did": self.did1, @"password": @"password", @"token": token}
                                                       headers:@{@"authorization": authHeader}];
    XCTAssertEqual(replayDelete.statusCode, 400);
    XCTAssertEqualObjects(replayDelete.jsonBody[@"error"], @"InvalidToken");
    XCTAssertNotNil([self.controller.serviceDatabases getAccountByDid:self.did1 error:nil]);
}

- (void)testDeleteAccountRejectsAuthenticatedDidMismatch {
    NSString *authHeader1 = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    // 1. Auth as did1, request account delete (no token) → 200 (mints token for did1).
    ATProtoHttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
                                                             body:@{}
                                                          headers:@{@"authorization": authHeader1}];
    XCTAssertEqual(requestResponse.statusCode, 200);

    // 2. Extract the token from password_reset_tokens.
    sqlite3 *db = (sqlite3 *)[self.controller.serviceDatabases serviceDatabase];
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(db,
        "SELECT token FROM password_reset_tokens WHERE did = ? ORDER BY rowid DESC LIMIT 1",
        -1, &stmt, NULL);
    sqlite3_bind_text(stmt, 1, self.did1.UTF8String, -1, SQLITE_TRANSIENT);

    NSString *did1Token = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *tokenText = sqlite3_column_text(stmt, 0);
        if (tokenText) did1Token = [NSString stringWithUTF8String:(const char *)tokenText];
    }
    sqlite3_finalize(stmt);
    XCTAssertNotNil(did1Token);

    // 3. Authenticated did1 cannot submit did2, even with did1's token.
    ATProtoHttpResponse *crossResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deleteAccount"
                                                           body:@{@"did": self.did2, @"password": @"password", @"token": did1Token}
                                                        headers:@{@"authorization": authHeader1}];
    XCTAssertEqual(crossResponse.statusCode, HttpStatusForbidden);
    XCTAssertEqualObjects(crossResponse.jsonBody[@"error"], @"Forbidden");
}

- (void)testDeleteAccountRejectsExpiredCrossAccountTokenAsInvalid {
    // Insert a token for did1 directly into the database.
    sqlite3 *db = (sqlite3 *)[self.controller.serviceDatabases serviceDatabase];
    XCTAssertTrue(db != NULL);

    NSString *crossToken = [NSString stringWithFormat:@"xacct-%lld",
                            (long long)([[NSDate date] timeIntervalSince1970] * 1000.0)];
    NSTimeInterval expiredTime = [[NSDate date] timeIntervalSince1970] - 3600.0;

    sqlite3_stmt *stmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db,
        "INSERT INTO password_reset_tokens (token, did, expires_at) VALUES (?, ?, ?)",
        -1, &stmt, NULL), SQLITE_OK);
    sqlite3_bind_text(stmt, 1, crossToken.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, self.did1.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 3, (sqlite3_int64)expiredTime);
    XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
    sqlite3_finalize(stmt);

    // An expired token minted for did1 must not reveal ExpiredToken to did2.
    NSError *loginError = nil;
    NSDictionary *session2 = [self.controller loginWithHandle:@"repoauth2.test" password:@"password" error:&loginError];
    XCTAssertNil(loginError);
    NSString *authHeader2 = [NSString stringWithFormat:@"Bearer %@", session2[@"accessJwt"]];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deleteAccount"
                                                      body:@{@"token": crossToken,
                                                             @"did": self.did2,
                                                             @"password": @"password"}
                                                   headers:@{@"authorization": authHeader2}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidToken");
}

#pragma mark - confirmEmail acceptance gate tests (phase-23 slice 4d)

- (void)testConfirmEmailNoLeakNonexistentToken {
    // No-leak: a fabricated token returns the same error as any invalid token.
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.confirmEmail"
                                                      body:@{@"email": @"repoauth1@example.com",
                                                             @"token": @"aa00000000000000000000000000000000000000000000000000000000000000"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidToken");
}

- (void)testConfirmEmailValidTokenSucceedsAndMarksUsed {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    // 1. Request email confirmation → 200 (mints token).
    ATProtoHttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestEmailConfirmation"
                                                             body:@{}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(requestResponse.statusCode, 200);

    // 2. Extract the opaque token from email_confirmation_tokens.
    sqlite3 *db = (sqlite3 *)[self.controller.serviceDatabases serviceDatabase];
    XCTAssertTrue(db != NULL);

    sqlite3_stmt *stmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db,
        "SELECT token FROM email_confirmation_tokens WHERE did = ? ORDER BY rowid DESC LIMIT 1",
        -1, &stmt, NULL), SQLITE_OK);
    sqlite3_bind_text(stmt, 1, self.did1.UTF8String, -1, SQLITE_TRANSIENT);

    NSString *token = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *tokenText = sqlite3_column_text(stmt, 0);
        if (tokenText) token = [NSString stringWithUTF8String:(const char *)tokenText];
    }
    sqlite3_finalize(stmt);
    XCTAssertNotNil(token, @"Expected an email confirmation token to be stored in the database");

    // 3. Confirm email with the valid token → 200.
    ATProtoHttpResponse *confirmResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.confirmEmail"
                                                             body:@{@"email": @"repoauth1@example.com",
                                                                    @"token": token}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(confirmResponse.statusCode, 200);

    // 4. Verify the token is marked as used.
    sqlite3_stmt *checkStmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db,
        "SELECT used_at FROM email_confirmation_tokens WHERE token = ?",
        -1, &checkStmt, NULL), SQLITE_OK);
    sqlite3_bind_text(checkStmt, 1, token.UTF8String, -1, SQLITE_TRANSIENT);
    XCTAssertEqual(sqlite3_step(checkStmt), SQLITE_ROW);
    XCTAssertTrue(sqlite3_column_type(checkStmt, 0) != SQLITE_NULL, @"Expected used_at to be set");
    sqlite3_finalize(checkStmt);

    // 5. Verify the account's email_confirmed_at is set.
    sqlite3_stmt *acctStmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db,
        "SELECT email_confirmed_at FROM accounts WHERE did = ?",
        -1, &acctStmt, NULL), SQLITE_OK);
    sqlite3_bind_text(acctStmt, 1, self.did1.UTF8String, -1, SQLITE_TRANSIENT);
    XCTAssertEqual(sqlite3_step(acctStmt), SQLITE_ROW);
    XCTAssertTrue(sqlite3_column_type(acctStmt, 0) != SQLITE_NULL, @"Expected email_confirmed_at to be set on the account");
    sqlite3_finalize(acctStmt);
}

- (void)testConfirmEmailRejectsReplayToken {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    // 1. Request email confirmation (stores a token).
    ATProtoHttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestEmailConfirmation"
                                                             body:@{}
                                                          headers:@{@"authorization": authHeader}];
    XCTAssertEqual(requestResponse.statusCode, 200);

    // 2. Extract token from database.
    sqlite3 *db = (sqlite3 *)[self.controller.serviceDatabases serviceDatabase];
    XCTAssertTrue(db != NULL);

    sqlite3_stmt *stmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db,
        "SELECT token FROM email_confirmation_tokens WHERE did = ? ORDER BY rowid DESC LIMIT 1",
        -1, &stmt, NULL), SQLITE_OK);
    sqlite3_bind_text(stmt, 1, self.did1.UTF8String, -1, SQLITE_TRANSIENT);

    NSString *token = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *tokenText = sqlite3_column_text(stmt, 0);
        if (tokenText) token = [NSString stringWithUTF8String:(const char *)tokenText];
    }
    sqlite3_finalize(stmt);
    XCTAssertNotNil(token);

    // 3. First confirm → 200.
    NSDictionary *confirmBody = @{@"email": @"repoauth1@example.com", @"token": token};
    ATProtoHttpResponse *firstConfirm = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.confirmEmail"
                                                          body:confirmBody
                                                       headers:@{@"authorization": authHeader}];
    XCTAssertEqual(firstConfirm.statusCode, 200);

    // 4. Replay with same token → 400.
    ATProtoHttpResponse *replayConfirm = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.confirmEmail"
                                                           body:confirmBody
                                                        headers:@{@"authorization": authHeader}];
    XCTAssertEqual(replayConfirm.statusCode, 400);
    XCTAssertEqualObjects(replayConfirm.jsonBody[@"error"], @"InvalidToken");
}

- (void)testConfirmEmailRejectsExpiredToken {
    // Insert an expired token directly into the database.
    sqlite3 *db = (sqlite3 *)[self.controller.serviceDatabases serviceDatabase];
    XCTAssertTrue(db != NULL);

    NSString *expiredToken = [NSString stringWithFormat:@"cemexp-%lld",
                              (long long)([[NSDate date] timeIntervalSince1970] * 1000.0)];
    NSTimeInterval expiredTime = [[NSDate date] timeIntervalSince1970] - 3600.0;

    sqlite3_stmt *stmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db,
        "INSERT INTO email_confirmation_tokens (token, did, email, expires_at) VALUES (?, ?, ?, ?)",
        -1, &stmt, NULL), SQLITE_OK);
    sqlite3_bind_text(stmt, 1, expiredToken.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, self.did1.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, "repoauth1@example.com", -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 4, (sqlite3_int64)expiredTime);
    XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
    sqlite3_finalize(stmt);

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];
    ATProtoHttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.confirmEmail"
                                                      body:@{@"email": @"repoauth1@example.com",
                                                             @"token": expiredToken}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidToken");
}

- (void)testConfirmEmailRejectsCrossAccountToken {
    NSString *authHeader1 = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    // 1. Auth as did1, request email confirmation → 200 (mints token for did1).
    ATProtoHttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestEmailConfirmation"
                                                             body:@{}
                                                          headers:@{@"authorization": authHeader1}];
    XCTAssertEqual(requestResponse.statusCode, 200);

    // 2. Extract the token from email_confirmation_tokens.
    sqlite3 *db = (sqlite3 *)[self.controller.serviceDatabases serviceDatabase];
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(db,
        "SELECT token FROM email_confirmation_tokens WHERE did = ? ORDER BY rowid DESC LIMIT 1",
        -1, &stmt, NULL);
    sqlite3_bind_text(stmt, 1, self.did1.UTF8String, -1, SQLITE_TRANSIENT);

    NSString *did1Token = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *tokenText = sqlite3_column_text(stmt, 0);
        if (tokenText) did1Token = [NSString stringWithUTF8String:(const char *)tokenText];
    }
    sqlite3_finalize(stmt);
    XCTAssertNotNil(did1Token);

    // 3. Auth as did2, try to confirm with did1's token → 400 (DID mismatch).
    NSError *loginError = nil;
    NSDictionary *session2 = [self.controller loginWithHandle:@"repoauth2.test" password:@"password" error:&loginError];
    XCTAssertNil(loginError);
    NSString *accessJwt2 = session2[@"accessJwt"];
    XCTAssertNotNil(accessJwt2);
    NSString *authHeader2 = [NSString stringWithFormat:@"Bearer %@", accessJwt2];
    ATProtoHttpResponse *crossResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.confirmEmail"
                                                           body:@{@"email": @"repoauth2@example.com",
                                                                  @"token": did1Token}
                                                        headers:@{@"authorization": authHeader2}];
    XCTAssertEqual(crossResponse.statusCode, 400);
    XCTAssertEqualObjects(crossResponse.jsonBody[@"error"], @"InvalidToken");

    // 4. Verify did1's token is NOT consumed (used_at still NULL).
    sqlite3_stmt *checkStmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db,
        "SELECT used_at FROM email_confirmation_tokens WHERE token = ?",
        -1, &checkStmt, NULL), SQLITE_OK);
    sqlite3_bind_text(checkStmt, 1, did1Token.UTF8String, -1, SQLITE_TRANSIENT);
    XCTAssertEqual(sqlite3_step(checkStmt), SQLITE_ROW);
    XCTAssertTrue(sqlite3_column_type(checkStmt, 0) == SQLITE_NULL, @"Expected did1's token to NOT be consumed by did2's failed attempt");
    sqlite3_finalize(checkStmt);
}

@end
