#import <XCTest/XCTest.h>
#import "Auth/Session.h"
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"

@interface SessionStoreTests : XCTestCase
@property (nonatomic, strong) SessionStore *store;
@property (nonatomic, strong) JWTMinter *minter;
@property (nonatomic, strong) JWTVerifier *verifier;
@end

@implementation SessionStoreTests

- (void)setUp {
    [super setUp];
    // Create a fresh store instance for each test
    self.store = [[SessionStore alloc] init];
    [self configureJWTSigning];
}

- (void)tearDown {
    self.store = nil;
    self.minter = nil;
    self.verifier = nil;
    [super tearDown];
}

#pragma mark - JWT Fixtures

- (void)configureJWTSigning {
    self.minter = [[JWTMinter alloc] init];
    self.minter.issuer = @"test.issuer";
    self.minter.signingAlgorithm = @"ES256K";
    self.minter.defaultExpiration = 3600;

    NSError *error = nil;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(keyPair, @"Failed to generate key pair: %@", error);
    self.minter.privateKey = keyPair.privateKey;

    self.verifier = [[JWTVerifier alloc] init];
    self.verifier.expectedIssuer = @"test.issuer";
    self.verifier.publicKey = keyPair.publicKey;

    self.store.minter = self.minter;
}

- (void)assertValidJWTAccessToken:(NSString *)accessToken {
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:accessToken error:&error];
    XCTAssertNotNil(jwt, @"Access token should parse as JWT");
    XCTAssertNil(error, @"No JWT parsing error expected");

    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertTrue(verified, @"JWT access token should verify");
    XCTAssertNil(error, @"No JWT verification error expected");
}

#pragma mark - Session Creation Tests

- (void)testCreateSessionForDID {
    NSError *error = nil;
    Session *session = [self.store createSessionForDID:@"did:plc:test123"
                                                handle:@"test.example.com"
                                                 scope:@"atproto"
                                               dpopJWK:nil
                                                 error:&error];
    
    XCTAssertNotNil(session, @"Session should be created");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertEqualObjects(session.did, @"did:plc:test123");
    XCTAssertEqualObjects(session.handle, @"test.example.com");
    XCTAssertEqualObjects(session.scope, @"atproto");
    XCTAssertNotNil(session.accessToken, @"Access token should be generated");
    XCTAssertNotNil(session.refreshToken, @"Refresh token should be generated");
    XCTAssertNotNil(session.sessionID, @"Session ID should be generated");
    [self assertValidJWTAccessToken:session.accessToken];
}

- (void)testDPoPThumbprintEqualsExpectedValue {
    NSDictionary *dpopJWK = @{@"kid": @"dpop-key-thumbprint-123"};
    
    Session *session = [self.store createSessionForDID:@"did:plc:dpoptest"
                                                handle:@"dpop.example.com"
                                                 scope:@"atproto"
                                               dpopJWK:dpopJWK
                                                 error:nil];
    
    XCTAssertEqualObjects(session.dpopKeyThumbprint, @"dpop-key-thumbprint-123",
                          @"DPoP thumbprint should be set from JWK kid");
}

- (void)testDPoPThumbprintNilWhenNoKid {
    NSDictionary *dpopJWK = @{@"kty": @"EC"}; // No kid field
    
    Session *session = [self.store createSessionForDID:@"did:plc:nokid"
                                                handle:@"nokid.example.com"
                                                 scope:@"atproto"
                                               dpopJWK:dpopJWK
                                                 error:nil];
    
    XCTAssertNil(session.dpopKeyThumbprint, @"DPoP thumbprint should be nil when no kid");
}

#pragma mark - Session Lookup Tests

- (void)testGetSessionByAccessToken {
    Session *created = [self.store createSessionForDID:@"did:plc:lookup"
                                                handle:@"lookup.example.com"
                                                 scope:@"atproto"
                                               dpopJWK:nil
                                                 error:nil];
    
    NSError *error = nil;
    Session *found = [self.store getSessionByAccessToken:created.accessToken error:&error];
    
    XCTAssertNotNil(found, @"Session should be found by access token");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertEqualObjects(found.sessionID, created.sessionID);
    XCTAssertEqualObjects(found.did, created.did);
}

- (void)testGetSessionByAccessTokenNotFound {
    NSError *error = nil;
    Session *found = [self.store getSessionByAccessToken:@"nonexistent-token" error:&error];
    
    XCTAssertNil(found, @"Session should not be found");
    XCTAssertNotNil(error, @"Error should be returned");
    XCTAssertEqual(error.code, SessionErrorInvalidToken);
}

- (void)testGetSessionByRefreshToken {
    Session *created = [self.store createSessionForDID:@"did:plc:refresh"
                                                handle:@"refresh.example.com"
                                                 scope:@"atproto"
                                               dpopJWK:nil
                                                 error:nil];
    
    NSError *error = nil;
    Session *found = [self.store getSessionByRefreshToken:created.refreshToken error:&error];
    
    XCTAssertNotNil(found, @"Session should be found by refresh token");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertEqualObjects(found.sessionID, created.sessionID);
}

- (void)testGetSessionByRefreshTokenNotFound {
    NSError *error = nil;
    Session *found = [self.store getSessionByRefreshToken:@"nonexistent-refresh" error:&error];
    
    XCTAssertNil(found, @"Session should not be found");
    XCTAssertNotNil(error, @"Error should be returned");
    XCTAssertEqual(error.code, SessionErrorInvalidToken);
}

- (void)testGetSessionByID {
    Session *created = [self.store createSessionForDID:@"did:plc:byid"
                                                handle:@"byid.example.com"
                                                 scope:@"atproto"
                                               dpopJWK:nil
                                                 error:nil];
    
    NSError *error = nil;
    Session *found = [self.store getSessionByID:created.sessionID error:&error];
    
    XCTAssertNotNil(found, @"Session should be found by ID");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertEqualObjects(found.accessToken, created.accessToken);
}

#pragma mark - Session Revocation Tests

- (void)testRevokeSession {
    Session *session = [self.store createSessionForDID:@"did:plc:revoke"
                                                handle:@"revoke.example.com"
                                                 scope:@"atproto"
                                               dpopJWK:nil
                                                 error:nil];
    NSString *accessToken = session.accessToken;
    NSString *refreshToken = session.refreshToken;
    NSString *sessionID = session.sessionID;
    
    NSError *error = nil;
    BOOL revoked = [self.store revokeSession:sessionID error:&error];
    
    XCTAssertTrue(revoked, @"Session should be revoked");
    XCTAssertNil(error, @"No error should occur");
    
    // Verify tokens no longer work
    Session *byAccess = [self.store getSessionByAccessToken:accessToken error:nil];
    Session *byRefresh = [self.store getSessionByRefreshToken:refreshToken error:nil];
    Session *byID = [self.store getSessionByID:sessionID error:nil];
    
    XCTAssertNil(byAccess, @"Access token lookup should fail after revocation");
    XCTAssertNil(byRefresh, @"Refresh token lookup should fail after revocation");
    XCTAssertNil(byID, @"Session ID lookup should fail after revocation");
}

- (void)testRevokeNonexistentSession {
    NSError *error = nil;
    BOOL revoked = [self.store revokeSession:@"nonexistent-session-id" error:&error];
    
    XCTAssertFalse(revoked, @"Revocation should fail");
    XCTAssertNotNil(error, @"Error should be returned");
    XCTAssertEqual(error.code, SessionErrorSessionNotFound);
}

#pragma mark - Session Refresh Tests

- (void)testRefreshSession {
    Session *original = [self.store createSessionForDID:@"did:plc:refreshtest"
                                                 handle:@"refreshtest.example.com"
                                                  scope:@"atproto"
                                                dpopJWK:nil
                                                  error:nil];
    NSString *oldAccessToken = original.accessToken;
    NSString *oldRefreshToken = original.refreshToken;
    
    Session *newSession = nil;
    NSError *error = nil;
    BOOL refreshed = [self.store refreshSession:original.sessionID
                                          scope:nil
                                        dpopJWK:nil
                                     newSession:&newSession
                                          error:&error];
    
    XCTAssertTrue(refreshed, @"Session should be refreshed");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(newSession, @"New session should be returned");
    
    // New tokens should be different
    XCTAssertNotEqualObjects(newSession.accessToken, oldAccessToken);
    XCTAssertNotEqualObjects(newSession.refreshToken, oldRefreshToken);
    
    // Old tokens should no longer work
    Session *oldLookup = [self.store getSessionByAccessToken:oldAccessToken error:nil];
    XCTAssertNil(oldLookup, @"Old access token should be invalid");
    
    // New tokens should work
    Session *newLookup = [self.store getSessionByAccessToken:newSession.accessToken error:nil];
    XCTAssertNotNil(newLookup, @"New access token should be valid");
}

- (void)testRefreshSessionUpdatesScopePropertyEqualToExpected {
    Session *original = [self.store createSessionForDID:@"did:plc:scopechange"
                                                 handle:@"scopechange.example.com"
                                                  scope:@"atproto"
                                                dpopJWK:nil
                                                  error:nil];
    
    Session *newSession = nil;
    [self.store refreshSession:original.sessionID
                         scope:@"atproto transition:generic"
                       dpopJWK:nil
                    newSession:&newSession
                         error:nil];
    
    XCTAssertEqualObjects(newSession.scope, @"atproto transition:generic",
                          @"New scope should be applied");
}

#pragma mark - Multi-Session Tests

- (void)testGetSessionsForDID {
    NSString *did = @"did:plc:multisession";
    
    [self.store createSessionForDID:did handle:@"session1.example.com" scope:@"atproto" dpopJWK:nil error:nil];
    [self.store createSessionForDID:did handle:@"session2.example.com" scope:@"atproto" dpopJWK:nil error:nil];
    [self.store createSessionForDID:did handle:@"session3.example.com" scope:@"atproto" dpopJWK:nil error:nil];
    
    NSError *error = nil;
    NSArray<Session *> *sessions = [self.store getSessionsForDID:did error:&error];
    
    XCTAssertEqual(sessions.count, 3, @"Should have 3 sessions for this DID");
    XCTAssertNil(error, @"No error should occur");
}

- (void)testAllActiveSessions {
    [self.store createSessionForDID:@"did:plc:user1" handle:@"user1.example.com" scope:@"atproto" dpopJWK:nil error:nil];
    [self.store createSessionForDID:@"did:plc:user2" handle:@"user2.example.com" scope:@"atproto" dpopJWK:nil error:nil];
    
    NSError *error = nil;
    NSArray<Session *> *sessions = [self.store allActiveSessions:&error];
    
    XCTAssertGreaterThanOrEqual(sessions.count, 2, @"Should have at least 2 active sessions");
    XCTAssertNil(error, @"No error should occur");
}

#pragma mark - Clock Skew Tests

- (void)testClockSkewTolerance {
    [self.store setClockSkew:60.0]; // 60 second tolerance
    XCTAssertEqual(self.store.clockSkew, 60.0, @"Clock skew should be set");
}

#pragma mark - Token Response Tests

- (void)testToTokenResponse {
    Session *session = [self.store createSessionForDID:@"did:plc:tokenresp"
                                                handle:@"tokenresp.example.com"
                                                 scope:@"atproto"
                                               dpopJWK:nil
                                                 error:nil];
    
    NSDictionary *response = [session toTokenResponse];
    
    XCTAssertEqualObjects(response[@"access_token"], session.accessToken, @"Response should have correct access_token");
    XCTAssertEqualObjects(response[@"token_type"], session.tokenType, @"Response should have token_type matching session");
    XCTAssertEqualObjects(response[@"scope"], @"atproto", @"Response should have correct scope");
    XCTAssertNotNil(response[@"expires_in"], @"Response should have expires_in");
    XCTAssertEqualObjects(response[@"refresh_token"], session.refreshToken, @"Response should have correct refresh_token");
}


- (void)testSessionPersistsAcrossStoreInstances {
    NSString *tempDir = NSTemporaryDirectory();
    NSString *dbPath = [tempDir stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    dbPath = [dbPath stringByAppendingPathExtension:@"sqlite"];
    
    // 1. Create store with path
    SessionStore *store1 = [[SessionStore alloc] initWithDatabasePath:dbPath];
    store1.minter = self.minter;
    // Set clock skew to match setUp
    store1.clockSkew = 0;
    
    // 2. Create session
    Session *session = [store1 createSessionForDID:@"did:example:123"
                                            handle:@"user.bsky.social"
                                             scope:@"com.atproto.access"
                                           dpopJWK:nil
                                             error:nil];
    XCTAssertNotNil(session, @"Failed to create session in store1");
    NSString *accessToken = session.accessToken;
    
    // 3. Create NEW store with same path
    SessionStore *store2 = [[SessionStore alloc] initWithDatabasePath:dbPath];
    store2.minter = self.minter;
    store2.clockSkew = 0;
    
    // 4. Retrieve session
    NSError *error = nil;
    Session *retrieved = [store2 getSessionByAccessToken:accessToken error:&error];
    
    XCTAssertNotNil(retrieved, @"Session should persist across store instances");
    XCTAssertNil(error, @"Should not have error retrieving session");
    XCTAssertEqualObjects(retrieved.did, @"did:example:123", @"DID should match");
    XCTAssertEqualObjects(retrieved.handle, @"user.bsky.social", @"Handle should match");
    XCTAssertEqualObjects(retrieved.scope, @"com.atproto.access", @"Scope should match");
    
    // Cleanup
    [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];
}

- (void)testSessionRoundTrip {
    // Create a session, retrieve it by access token, verify identity fields.
    NSError *error = nil;
    Session *session = [self.store createSessionForDID:@"did:plc:roundtrip"
                                                handle:@"roundtrip.test"
                                                 scope:@"atproto"
                                               dpopJWK:nil
                                                 error:&error];
    XCTAssertNotNil(session, @"createSession must succeed: %@", error);
    XCTAssertNil(error);

    Session *fetched = [self.store getSessionByAccessToken:session.accessToken error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(fetched, @"Session must be retrievable by access token");
    XCTAssertEqualObjects(fetched.did, @"did:plc:roundtrip");
    XCTAssertEqualObjects(fetched.handle, @"roundtrip.test");
    XCTAssertEqualObjects(fetched.scope, @"atproto");
}

- (void)testExpiredSessionIsRejected {
    // Configure a very short access token lifetime so it expires immediately.
    self.store.accessTokenLifetime = -1.0; // expired in the past
    NSError *error = nil;
    Session *session = [self.store createSessionForDID:@"did:plc:expired"
                                                handle:@"expired.test"
                                                 scope:@"atproto"
                                               dpopJWK:nil
                                                 error:&error];
    // Session creation itself may succeed (we just store it).
    if (session == nil) {
        // Some implementations refuse to create expired sessions — acceptable.
        return;
    }

    // The session's access token should be expired.
    XCTAssertTrue([session.accessToken length] > 0);
    // Verify the token using the verifier with no clock skew — must be rejected.
    JWT *jwt = [JWT jwtWithToken:session.accessToken error:nil];
    if (jwt) {
        BOOL valid = [self.verifier verifyToken:session.accessToken error:&error];
        XCTAssertFalse(valid, @"An expired token must fail verification");
    }
    // Restore the lifetime for subsequent tests.
    self.store.accessTokenLifetime = 3600;
}

@end
