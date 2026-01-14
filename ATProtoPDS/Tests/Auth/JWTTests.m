#import <XCTest/XCTest.h>
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"

@interface JWTTests : XCTestCase
@property (nonatomic, strong) JWTMinter *minter;
@property (nonatomic, strong) JWTVerifier *verifier;
@end

@implementation JWTTests

- (void)setUp {
    [super setUp];

    // Create a test minter with a known private key
    self.minter = [[JWTMinter alloc] init];
    self.minter.issuer = @"test.issuer";
    self.minter.signingAlgorithm = @"ES256";
    self.minter.defaultExpiration = 3600;

    // Use a valid generated key pair
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    self.minter.privateKey = keyPair.privateKey;

    // Create verifier
    self.verifier = [[JWTVerifier alloc] init];
    self.verifier.expectedIssuer = @"test.issuer";
    self.verifier.expectedAudience = @"test.audience";
    
    // Set public key for verification
    self.verifier.publicKey = keyPair.publicKey;
}

- (void)tearDown {
    self.minter = nil;
    self.verifier = nil;
    [super tearDown];
}

#pragma mark - JWT Parsing Tests

- (void)testValidJWTTokenParsing {
    // Test successful JWT parsing and claims extraction
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:@"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" error:&error];

    XCTAssertNotNil(jwt, @"JWT should parse successfully");
    XCTAssertNil(error, @"No error should occur during parsing");
    XCTAssertNotNil(jwt.header, @"Header should be parsed");
    XCTAssertNotNil(jwt.payload, @"Payload should be parsed");
    XCTAssertEqualObjects(jwt.header.alg, @"HS256", @"Algorithm should be HS256");
    XCTAssertEqualObjects(jwt.payload.sub, @"1234567890", @"Subject should be parsed correctly");
}

- (void)testMalformedJWTTokenRejection {
    // Test malformed JWT rejection
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:@"invalid.jwt.token" error:&error];

    XCTAssertNil(jwt, @"Malformed JWT should not parse");
    XCTAssertNotNil(error, @"Error should be returned for malformed JWT");
    XCTAssertEqual(error.domain, JWTErrorDomain, @"Error should be in JWT domain");
}

- (void)testJWTWithMissingParts {
    // Test JWT with missing signature
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:@"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0" error:&error];

    XCTAssertNil(jwt, @"JWT with missing signature should not parse");
    XCTAssertNotNil(error, @"Error should be returned for incomplete JWT");
}

#pragma mark - JWT Creation Tests

- (void)testJWTTokenCreationAndEncoding {
    // Test creating a JWT and encoding it back
    NSError *error = nil;

    // Create header
    JWTHeader *header = [[JWTHeader alloc] init];
    header.alg = @"HS256";
    header.typ = @"JWT";

    // Create payload
    JWTPayload *payload = [[JWTPayload alloc] init];
    payload.sub = @"test-subject";
    payload.iss = @"test-issuer";
    payload.aud = @"test-audience";

    // Create JWT
    JWT *jwt = [JWT jwtWithHeader:header payload:payload signature:@"test-signature" error:&error];

    XCTAssertNotNil(jwt, @"JWT should be created successfully");
    XCTAssertNil(error, @"No error should occur during creation");
    XCTAssertEqualObjects(jwt.header.alg, @"HS256", @"Header should be preserved");
    XCTAssertEqualObjects(jwt.payload.sub, @"test-subject", @"Payload should be preserved");

    // Test encoding
    NSString *encoded = [jwt encodedToken];
    XCTAssertNotNil(encoded, @"JWT should encode to string");
    XCTAssertTrue([encoded containsString:@"."], @"Encoded JWT should contain dots");
}

#pragma mark - JWT Verification Tests

- (void)testJWTVerificationWithValidToken {
    // Test successful JWT verification
    NSError *error = nil;

    // Create a valid token
    NSDictionary *payload = @{
        @"sub": @"test-user",
        @"iss": @"test.issuer",
        @"aud": @"test.audience",
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:3600] timeIntervalSince1970]),
        @"iat": @([[NSDate date] timeIntervalSince1970])
    };

    NSString *token = [self.minter signPayload:payload error:&error];
    XCTAssertNotNil(token, @"Token should be created");
    XCTAssertNil(error, @"No error during token creation");

    // Parse and verify
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    XCTAssertNotNil(jwt, @"JWT should parse");
    XCTAssertNil(error, @"No error during parsing");

    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertTrue(verified, @"JWT should verify successfully");
    XCTAssertNil(error, @"No error during verification");
}

- (void)testJWTVerificationWithExpiredToken {
    // Test expired JWT rejection
    NSError *error = nil;

    // Create an expired token
    NSDictionary *payload = @{
        @"sub": @"test-user",
        @"iss": @"test.issuer",
        @"aud": @"test.audience",
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:-3600] timeIntervalSince1970]), // Expired 1 hour ago
        @"iat": @([[NSDate date] timeIntervalSince1970])
    };

    NSString *token = [self.minter signPayload:payload error:&error];
    XCTAssertNotNil(token, @"Expired token should still be created");

    // Parse and verify
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    XCTAssertNotNil(jwt, @"Expired JWT should still parse");

    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertFalse(verified, @"Expired JWT should not verify");
    XCTAssertNotNil(error, @"Error should be returned for expired token");
    XCTAssertEqual(error.code, JWTErrorTokenExpired, @"Error should indicate token expired");
}

- (void)testJWTVerificationWithWrongIssuer {
    // Test JWT with wrong issuer
    self.verifier.expectedIssuer = @"wrong.issuer";

    NSError *error = nil;

    NSDictionary *payload = @{
        @"sub": @"test-user",
        @"iss": @"test.issuer", // Wrong issuer
        @"aud": @"test.audience",
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:3600] timeIntervalSince1970]),
        @"iat": @([[NSDate date] timeIntervalSince1970])
    };

    NSString *token = [self.minter signPayload:payload error:&error];
    JWT *jwt = [JWT jwtWithToken:token error:&error];

    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertFalse(verified, @"JWT with wrong issuer should not verify");
    XCTAssertNotNil(error, @"Error should be returned for wrong issuer");
}

- (void)testJWTVerificationRejectsNoneAlgorithm {
    // Test JWT with "none" algorithm is rejected
    NSError *error = nil;

    // Create a JWT with "none" algorithm (unsigned)
    JWTHeader *header = [[JWTHeader alloc] init];
    header.alg = @"none";
    header.typ = @"JWT";

    JWTPayload *payload = [[JWTPayload alloc] init];
    payload.sub = @"test-user";
    payload.iss = @"test.issuer";
    payload.aud = @"test.audience";
    payload.exp = [[NSDate date] dateByAddingTimeInterval:3600];

    // Create JWT with empty signature (none algorithm)
    JWT *jwt = [JWT jwtWithHeader:header payload:payload signature:@"" error:&error];
    XCTAssertNotNil(jwt, @"JWT should be created");

    // Set allowed algorithms (excluding none)
    self.verifier.allowedAlgorithms = @[@"RS256", @"ES256"];

    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertFalse(verified, @"JWT with 'none' algorithm should not verify when algorithm restriction is set");

    // Assert error is returned
    XCTAssertNotNil(error, @"Error should be returned for disallowed algorithm");
}

- (void)testJWTVerificationWithWrongAudience {
    // Test JWT with wrong audience
    self.verifier.expectedAudience = @"wrong.audience";

    NSError *error = nil;

    NSDictionary *payload = @{
        @"sub": @"test-user",
        @"iss": @"test.issuer",
        @"aud": @"test.audience", // Wrong audience
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:3600] timeIntervalSince1970]),
        @"iat": @([[NSDate date] timeIntervalSince1970])
    };

    NSString *token = [self.minter signPayload:payload error:&error];
    JWT *jwt = [JWT jwtWithToken:token error:&error];

    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertFalse(verified, @"JWT with wrong audience should not verify");
    XCTAssertNotNil(error, @"Error should be returned for wrong audience");
}

- (void)testJWTNotBeforeClaim {
    // Test JWT with future nbf is rejected
    NSError *error = nil;

    // Create a token not valid yet (starts in 1 hour)
    NSDictionary *payload = @{
        @"sub": @"test-user",
        @"iss": @"test.issuer",
        @"aud": @"test.audience",
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:7200] timeIntervalSince1970]),
        @"iat": @([[NSDate date] timeIntervalSince1970]),
        @"nbf": @([[[NSDate date] dateByAddingTimeInterval:3600] timeIntervalSince1970])
    };

    NSString *token = [self.minter signPayload:payload error:&error];
    XCTAssertNotNil(token);

    JWT *jwt = [JWT jwtWithToken:token error:&error];
    XCTAssertNotNil(jwt);

    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertFalse(verified, @"JWT with future nbf should not verify");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, JWTErrorTokenNotYetValid, @"Error should indicate token not yet valid");
}

#pragma mark - JWTMinter Tests

- (void)testAccessTokenMinting {
    // Test minting an access token
    NSError *error = nil;

    JWT *token = [self.minter mintAccessTokenForDID:@"did:example:test"
                                             handle:@"test.handle"
                                             scopes:@[@"read", @"write"]
                                               error:&error];

    XCTAssertNotNil(token, @"Access token should be minted");
    XCTAssertNil(error, @"No error during minting");
    XCTAssertNotNil(token.payload.did, @"DID should be set in payload");
    XCTAssertNotNil(token.payload.handle, @"Handle should be set in payload");
    XCTAssertNotNil(token.payload.scope, @"Scope should be set in payload");
    XCTAssertEqualObjects(token.payload.iss, @"test.issuer", @"Issuer should be set correctly");
}

- (void)testRefreshTokenMinting {
    // Test minting a refresh token
    NSError *error = nil;

    JWT *token = [self.minter mintRefreshTokenForDID:@"did:example:test"
                                              handle:@"test.handle"
                                              scopes:@[@"read", @"write"]
                                                error:&error];

    XCTAssertNotNil(token, @"Refresh token should be minted");
    XCTAssertNil(error, @"No error during minting");
    XCTAssertNotNil(token.payload.did, @"DID should be set in payload");
    XCTAssertEqualObjects(token.payload.iss, @"test.issuer", @"Issuer should be set correctly");
}

#pragma mark - Base64URL Encoding Tests

- (void)testBase64URLEncoding {
    // Test base64URL encoding
    NSError *error = nil;
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];

    NSString *encoded = [JWT base64URLEncodeData:data error:&error];

    XCTAssertNotNil(encoded, @"Data should be encoded");
    XCTAssertNil(error, @"No error during encoding");
    XCTAssertFalse([encoded containsString:@"+"], @"Should not contain +");
    XCTAssertFalse([encoded containsString:@"/"], @"Should not contain /");
}

@end
