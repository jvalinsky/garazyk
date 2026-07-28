// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "RepoAuthXrpcTestBase.h"
#import "Database/Service/ServiceDatabases.h"
#import <sqlite3.h>

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

- (void)testRequestAndResetPasswordFlowWithOpaqueToken {
    // 1. Missing email → 400.
    HttpResponse *requestMissingEmail = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestPasswordReset"
                                                                 body:@{}
                                                              headers:@{}];
    XCTAssertEqual(requestMissingEmail.statusCode, 400);

    // 2. Valid email → 200 (no-leak).
    HttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestPasswordReset"
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
    HttpResponse *resetResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.resetPassword"
                                                           body:@{@"token": token,
                                                                  @"password": @"new-password-123"}
                                                        headers:@{}];
    XCTAssertEqual(resetResponse.statusCode, 200);

    // 5. Can create session with new password.
    HttpResponse *sessionResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createSession"
                                                            body:@{@"identifier": @"repoauth1.test",
                                                                   @"password": @"new-password-123"}
                                                         headers:@{}];
    XCTAssertEqual(sessionResponse.statusCode, 200);
}

- (void)testRequestPasswordResetNoLeakNonexistentEmail {
    // No-leak: nonexistent email still returns 200.
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestPasswordReset"
                                                      body:@{@"email": @"nonexistent@example.com"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
}

- (void)testResetPasswordRejectsDidAsToken {
    // The old DID-as-token path is removed — a DID no longer works.
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.resetPassword"
                                                      body:@{@"token": self.did1,
                                                             @"password": @"new-password-123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidToken");
}

- (void)testResetPasswordRejectsInvalidToken {
    // A random 64-char hex string that was never minted.
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.resetPassword"
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

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.resetPassword"
                                                      body:@{@"token": expiredToken,
                                                             @"password": @"new-password-123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"ExpiredToken");
}

- (void)testResetPasswordRejectsReplayToken {
    // 1. Request password reset (stores a token).
    HttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestPasswordReset"
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
    HttpResponse *firstReset = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.resetPassword"
                                                        body:@{@"token": token,
                                                               @"password": @"first-new-password"}
                                                     headers:@{}];
    XCTAssertEqual(firstReset.statusCode, 200);

    // 4. Replay with same token → 400.
    HttpResponse *replayReset = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.resetPassword"
                                                         body:@{@"token": token,
                                                                @"password": @"second-new-password"}
                                                      headers:@{}];
    XCTAssertEqual(replayReset.statusCode, 400);
    XCTAssertEqualObjects(replayReset.jsonBody[@"error"], @"InvalidToken");
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

- (void)testRequestAccountDeleteMintsTokenAndCanDelete {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    // 1. Request account delete (no token) → 200 (mints token).
    HttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
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

    // 3. Exchange token via requestAccountDelete → 200 (deletes account).
    HttpResponse *deleteResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
                                                            body:@{@"token": token}
                                                         headers:@{@"authorization": authHeader}];
    XCTAssertEqual(deleteResponse.statusCode, 200);

    // 4. Account no longer exists.
    NSError *accountError = nil;
    PDSDatabaseAccount *account = [self.controller.serviceDatabases getAccountByDid:self.did1 error:&accountError];
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

    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
                                                      body:@{@"token": expiredToken}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"ExpiredToken");
}

- (void)testDeleteAccountRejectsReplayToken {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    // 1. Request account delete (no token) → 200 (stores token).
    HttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
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

    // 3. First exchange via requestAccountDelete → 200 (deletes account).
    HttpResponse *firstDelete = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
                                                         body:@{@"token": token}
                                                      headers:@{@"authorization": authHeader}];
    XCTAssertEqual(firstDelete.statusCode, 200);

    // 4. Replay with same token → 400.
    HttpResponse *replayDelete = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
                                                          body:@{@"token": token}
                                                       headers:@{@"authorization": authHeader}];
    XCTAssertEqual(replayDelete.statusCode, 400);
    XCTAssertEqualObjects(replayDelete.jsonBody[@"error"], @"InvalidToken");
}

- (void)testRequestAccountDeleteRejectsCrossAccountToken {
    NSString *authHeader1 = [NSString stringWithFormat:@"Bearer %@", self.accessJwt1];

    // 1. Auth as did1, request account delete (no token) → 200 (mints token for did1).
    HttpResponse *requestResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
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

    // 3. Auth as did2, try to exchange did1's token → 400 (DID mismatch).
    NSError *loginError = nil;
    NSDictionary *session2 = [self.controller loginWithHandle:@"repoauth2.test" password:@"password" error:&loginError];
    XCTAssertNil(loginError);
    NSString *accessJwt2 = session2[@"accessJwt"];
    XCTAssertNotNil(accessJwt2);

    NSString *authHeader2 = [NSString stringWithFormat:@"Bearer %@", accessJwt2];
    HttpResponse *crossResponse = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.requestAccountDelete"
                                                           body:@{@"token": did1Token}
                                                        headers:@{@"authorization": authHeader2}];
    XCTAssertEqual(crossResponse.statusCode, 400);
    XCTAssertEqualObjects(crossResponse.jsonBody[@"error"], @"InvalidToken");
}

- (void)testDeleteAccountRejectsCrossAccountToken {
    // Insert a token for did1 directly into the database.
    sqlite3 *db = (sqlite3 *)[self.controller.serviceDatabases serviceDatabase];
    XCTAssertTrue(db != NULL);

    NSString *crossToken = [NSString stringWithFormat:@"xacct-%lld",
                            (long long)([[NSDate date] timeIntervalSince1970] * 1000.0)];
    NSTimeInterval futureTime = [[NSDate date] timeIntervalSince1970] + 3600.0;

    sqlite3_stmt *stmt = NULL;
    XCTAssertEqual(sqlite3_prepare_v2(db,
        "INSERT INTO password_reset_tokens (token, did, expires_at) VALUES (?, ?, ?)",
        -1, &stmt, NULL), SQLITE_OK);
    sqlite3_bind_text(stmt, 1, crossToken.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, self.did1.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 3, (sqlite3_int64)futureTime);
    XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
    sqlite3_finalize(stmt);

    // Call deleteAccount with did2 + did1's token → 400.
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.deleteAccount"
                                                      body:@{@"token": crossToken,
                                                             @"did": self.did2,
                                                             @"password": @"password"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidToken");
}

@end
