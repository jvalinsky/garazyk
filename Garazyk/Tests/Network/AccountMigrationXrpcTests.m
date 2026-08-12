// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "RepoAuthXrpcTestBase.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Network/XrpcServiceAuthHelper.h"
#import "Core/DID.h"
#import "Auth/Crypto/Secp256k1.h"
#import "Auth/Crypto/JWT.h"

// Bring-your-own-DID account creation (ADR 0035): createAccount accepts an
// existing DID only when the caller proves control of it with a service-auth
// JWT (lxm=com.atproto.server.createAccount) signed by the DID's current
// signing key, resolved from the DID document. The account is created
// deactivated and cannot create sessions until the operator completes the
// cutover. These tests exercise that path end-to-end through the XRPC layer.
@interface AccountMigrationXrpcTests : RepoAuthXrpcTestBase
@end

@implementation AccountMigrationXrpcTests

// 24 base32 characters from the did:plc alphabet (no 0/1/8/9, no uppercase).
static NSString * const kMigratedDID = @"did:plc:abcdefghijklmnopqrstuvwx";

#pragma mark - Helpers

- (void)seedDIDDocumentForDID:(NSString *)did
                      keyPair:(ATProtoSecp256k1KeyPair *)keyPair
                       handle:(NSString *)handle {
    NSString *didKey = keyPair.didKeyString ?: @"";
    NSString *multibase = [didKey hasPrefix:@"did:key:"] ? [didKey substringFromIndex:8] : didKey;
    NSDictionary *document = @{
        @"id": did,
        @"alsoKnownAs": @[[NSString stringWithFormat:@"at://%@", handle]],
        @"verificationMethod": @[@{
            @"id": [did stringByAppendingString:@"#atproto"],
            @"type": @"Multikey",
            @"controller": did,
            @"publicKeyMultibase": multibase,
        }],
        @"service": @[@{
            @"id": [did stringByAppendingString:@"#atproto_pds"],
            @"type": @"AtprotoPersonalDataServer",
            @"serviceEndpoint": @"https://old-pds.example.com",
        }],
    };
    [[ATProtoDIDResolver sharedResolver] seedCacheWithDID:did documentJSON:document];
}

- (NSString *)mintServiceAuthTokenForDID:(NSString *)did
                                 keyPair:(ATProtoSecp256k1KeyPair *)keyPair
                                     lxm:(NSString *)lxm {
    ATProtoJWTMinter *minter = [[ATProtoJWTMinter alloc] init];
    minter.signingAlgorithm = @"ES256K";
    minter.privateKey = keyPair.privateKey;
    minter.publicKey = keyPair.compressedPublicKey;

    NSArray<NSString *> *audiences =
        XrpcServiceAuthExpectedAudiences([ATProtoServiceConfiguration sharedConfiguration]);
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDictionary *payload = @{
        @"iss": did,
        @"aud": audiences.firstObject ?: @"did:web:localhost",
        @"lxm": lxm,
        @"iat": @((NSInteger)now),
        @"exp": @((NSInteger)(now + 60)),
        @"jti": [[NSUUID UUID] UUIDString],
    };

    NSError *error = nil;
    NSString *token = [minter signPayload:payload error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(token);
    return token;
}

- (ATProtoHttpResponse *)createAccountWithDID:(NSString *)did
                                       handle:(NSString *)handle
                                        email:(NSString *)email
                                  authToken:(nullable NSString *)authToken {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (authToken.length > 0) {
        headers[@"authorization"] = [@"Bearer " stringByAppendingString:authToken];
    }
    return [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createAccount"
                                    body:@{
                                        @"handle": handle,
                                        @"email": email,
                                        @"password": @"password123",
                                        @"did": did,
                                    }
                                 headers:headers];
}

#pragma mark - Bring-your-own-DID success path

- (void)testCreateAccountWithDIDAndValidServiceAuthCreatesDeactivatedAccount {
    NSError *keyError = nil;
    ATProtoSecp256k1KeyPair *keyPair = [[ATProtoSecp256k1 shared] generateKeyPairWithError:&keyError];
    XCTAssertNotNil(keyPair, @"%@", keyError);

    NSString *handle = @"migrate1.test";
    [self seedDIDDocumentForDID:kMigratedDID keyPair:keyPair handle:handle];
    NSString *token = [self mintServiceAuthTokenForDID:kMigratedDID
                                               keyPair:keyPair
                                                   lxm:@"com.atproto.server.createAccount"];

    ATProtoHttpResponse *response = [self createAccountWithDID:kMigratedDID
                                                        handle:handle
                                                         email:@"migrate1@example.com"
                                                    authToken:token];
    XCTAssertEqual(response.statusCode, HttpStatusOK, @"%@", response.jsonBody);
    XCTAssertEqualObjects(response.jsonBody[@"did"], kMigratedDID);
    XCTAssertEqualObjects(response.jsonBody[@"active"], @NO,
                          @"A bring-your-own-DID account must be created deactivated (ADR 0035)");

    // The account must exist under the caller's DID, not a freshly minted one.
    ATProtoHttpResponse *describe = [self sendGetRequestWithPath:@"/xrpc/com.atproto.repo.describeRepo"
                                                     queryParams:@{@"repo": kMigratedDID}
                                                         headers:@{}];
    XCTAssertEqual(describe.statusCode, HttpStatusOK, @"%@", describe.jsonBody);
    XCTAssertEqualObjects(describe.jsonBody[@"did"], kMigratedDID);
}

- (void)testCreateAccountWithoutDIDStillMintsActiveFreshDID {
    ATProtoHttpResponse *response = [self createAccountWithDID:@""
                                                        handle:@"migrate-fresh.test"
                                                         email:@"migrate-fresh@example.com"
                                                    authToken:nil];
    XCTAssertEqual(response.statusCode, HttpStatusOK, @"%@", response.jsonBody);
    XCTAssertTrue([response.jsonBody[@"did"] hasPrefix:@"did:"]);
    XCTAssertEqualObjects(response.jsonBody[@"active"], @YES,
                          @"Ordinary account creation must remain active");
}

#pragma mark - Service-auth rejection paths

- (void)testCreateAccountWithDIDWithoutServiceAuthReturns401 {
    NSError *keyError = nil;
    ATProtoSecp256k1KeyPair *keyPair = [[ATProtoSecp256k1 shared] generateKeyPairWithError:&keyError];
    XCTAssertNotNil(keyPair);
    [self seedDIDDocumentForDID:kMigratedDID keyPair:keyPair handle:@"migrate2.test"];

    ATProtoHttpResponse *response = [self createAccountWithDID:kMigratedDID
                                                        handle:@"migrate2.test"
                                                         email:@"migrate2@example.com"
                                                    authToken:nil];
    XCTAssertEqual(response.statusCode, HttpStatusUnauthorized);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidToken");
}

- (void)testCreateAccountWithDIDAndTokenSignedByWrongKeyReturns401 {
    NSError *keyError = nil;
    ATProtoSecp256k1KeyPair *documentKey = [[ATProtoSecp256k1 shared] generateKeyPairWithError:&keyError];
    ATProtoSecp256k1KeyPair *attackerKey = [[ATProtoSecp256k1 shared] generateKeyPairWithError:&keyError];
    XCTAssertNotNil(documentKey);
    XCTAssertNotNil(attackerKey);

    [self seedDIDDocumentForDID:kMigratedDID keyPair:documentKey handle:@"migrate3.test"];
    NSString *token = [self mintServiceAuthTokenForDID:kMigratedDID
                                               keyPair:attackerKey
                                                   lxm:@"com.atproto.server.createAccount"];

    ATProtoHttpResponse *response = [self createAccountWithDID:kMigratedDID
                                                        handle:@"migrate3.test"
                                                         email:@"migrate3@example.com"
                                                    authToken:token];
    XCTAssertEqual(response.statusCode, HttpStatusUnauthorized);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidToken");
}

- (void)testCreateAccountWithDIDAndWrongLxmReturns401 {
    NSError *keyError = nil;
    ATProtoSecp256k1KeyPair *keyPair = [[ATProtoSecp256k1 shared] generateKeyPairWithError:&keyError];
    XCTAssertNotNil(keyPair);

    [self seedDIDDocumentForDID:kMigratedDID keyPair:keyPair handle:@"migrate4.test"];
    NSString *token = [self mintServiceAuthTokenForDID:kMigratedDID
                                               keyPair:keyPair
                                                   lxm:@"com.atproto.server.createSession"];

    ATProtoHttpResponse *response = [self createAccountWithDID:kMigratedDID
                                                        handle:@"migrate4.test"
                                                         email:@"migrate4@example.com"
                                                    authToken:token];
    XCTAssertEqual(response.statusCode, HttpStatusUnauthorized);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidToken");
}

- (void)testCreateAccountWithDIDAndTokenForAnotherDIDIssuerReturns401 {
    NSError *keyError = nil;
    ATProtoSecp256k1KeyPair *keyPair = [[ATProtoSecp256k1 shared] generateKeyPairWithError:&keyError];
    XCTAssertNotNil(keyPair);

    [self seedDIDDocumentForDID:kMigratedDID keyPair:keyPair handle:@"migrate5.test"];
    // Token claims to be issued by a different DID than the one in the body.
    NSString *token = [self mintServiceAuthTokenForDID:@"did:plc:zzzzzzzzzzzzzzzzzzzzzzzz"
                                               keyPair:keyPair
                                                   lxm:@"com.atproto.server.createAccount"];

    ATProtoHttpResponse *response = [self createAccountWithDID:kMigratedDID
                                                        handle:@"migrate5.test"
                                                         email:@"migrate5@example.com"
                                                    authToken:token];
    XCTAssertEqual(response.statusCode, HttpStatusUnauthorized);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidToken");
}

#pragma mark - Deactivated-account session behavior

- (void)testDeactivatedMigratedAccountCannotCreateSession {
    NSError *keyError = nil;
    ATProtoSecp256k1KeyPair *keyPair = [[ATProtoSecp256k1 shared] generateKeyPairWithError:&keyError];
    XCTAssertNotNil(keyPair);

    NSString *email = @"migrate6@example.com";
    NSString *handle = @"migrate6.test";
    [self seedDIDDocumentForDID:kMigratedDID keyPair:keyPair handle:handle];
    NSString *token = [self mintServiceAuthTokenForDID:kMigratedDID
                                               keyPair:keyPair
                                                   lxm:@"com.atproto.server.createAccount"];
    ATProtoHttpResponse *created = [self createAccountWithDID:kMigratedDID
                                                       handle:handle
                                                        email:email
                                                   authToken:token];
    XCTAssertEqual(created.statusCode, HttpStatusOK, @"%@", created.jsonBody);

    // Until the operator activates the account, the password must not open a
    // session — even though the BYO-DID createAccount returned tokens.
    ATProtoHttpResponse *session = [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.createSession"
                                                          body:@{
                                                              @"identifier": email,
                                                              @"password": @"password123",
                                                          }
                                                       headers:@{}];
    XCTAssertEqual(session.statusCode, HttpStatusUnauthorized);
    XCTAssertEqualObjects(session.jsonBody[@"error"], @"AccountDeactivated");
}

- (void)testDeactivatedMigratedAccountCanRefreshTokens {
    // ADR 0035: refresh-token rotation is deliberately not blocked for
    // deactivated accounts, so the migration tool's long-lived session
    // survives the import window (createSession stays blocked; this pins the
    // intended refresh semantics).
    NSError *keyError = nil;
    ATProtoSecp256k1KeyPair *keyPair = [[ATProtoSecp256k1 shared] generateKeyPairWithError:&keyError];
    XCTAssertNotNil(keyPair);

    NSString *email = @"migrate9@example.com";
    NSString *handle = @"migrate9.test";
    [self seedDIDDocumentForDID:kMigratedDID keyPair:keyPair handle:handle];
    NSString *token = [self mintServiceAuthTokenForDID:kMigratedDID
                                               keyPair:keyPair
                                                   lxm:@"com.atproto.server.createAccount"];
    ATProtoHttpResponse *created = [self createAccountWithDID:kMigratedDID
                                                       handle:handle
                                                        email:email
                                                   authToken:token];
    XCTAssertEqual(created.statusCode, HttpStatusOK, @"%@", created.jsonBody);
    NSString *refreshJwt = created.jsonBody[@"refreshJwt"];
    XCTAssertTrue(refreshJwt.length > 0);

    ATProtoHttpResponse *refreshed =
        [self sendJsonRequestWithPath:@"/xrpc/com.atproto.server.refreshSession"
                                 body:@{}
                              headers:@{@"authorization": [@"Bearer " stringByAppendingString:refreshJwt]}];
    XCTAssertEqual(refreshed.statusCode, HttpStatusOK, @"%@", refreshed.jsonBody);
    XCTAssertNotNil(refreshed.jsonBody[@"accessJwt"]);
    XCTAssertNotNil(refreshed.jsonBody[@"refreshJwt"]);
}

- (void)testCreateAccountWithDIDIsRejectedForExistingDID {
    NSError *keyError = nil;
    ATProtoSecp256k1KeyPair *keyPair = [[ATProtoSecp256k1 shared] generateKeyPairWithError:&keyError];
    XCTAssertNotNil(keyPair);

    [self seedDIDDocumentForDID:kMigratedDID keyPair:keyPair handle:@"migrate7.test"];
    NSString *token = [self mintServiceAuthTokenForDID:kMigratedDID
                                               keyPair:keyPair
                                                   lxm:@"com.atproto.server.createAccount"];
    ATProtoHttpResponse *first = [self createAccountWithDID:kMigratedDID
                                                     handle:@"migrate7.test"
                                                      email:@"migrate7@example.com"
                                                 authToken:token];
    XCTAssertEqual(first.statusCode, HttpStatusOK, @"%@", first.jsonBody);

    // A second attempt for the same DID must fail: the DID is already hosted.
    ATProtoHttpResponse *second = [self createAccountWithDID:kMigratedDID
                                                      handle:@"migrate7b.test"
                                                       email:@"migrate7b@example.com"
                                                  authToken:token];
    XCTAssertEqual(second.statusCode, HttpStatusBadRequest);
}

@end
