// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/Crypto/JWT.h"
#import "Auth/Crypto/Secp256k1.h"
#import <CommonCrypto/CommonDigest.h>

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
    self.minter.signingAlgorithm = @"ES256K";
    self.minter.defaultExpiration = 3600;

    // Use a valid generated key pair
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    self.minter.privateKey = keyPair.privateKey;

    // Create verifier
    self.verifier = [[JWTVerifier alloc] init];
    self.verifier.expectedIssuer = @"test.issuer";
    self.verifier.expectedAudience = @"test.audience";
    self.verifier.allowedAlgorithms = @[@"ES256K"];
    
    // Set public key for verification
    self.verifier.publicKey = keyPair.publicKey;
}

- (void)tearDown {
    self.minter = nil;
    self.verifier = nil;
    [super tearDown];
}

- (void)testKeyPairWithPrivateKeyDerivesMatchingPublicKey {
    NSError *error = nil;
    Secp256k1KeyPair *generated = [Secp256k1KeyPair generateKeyPair:&error];
    XCTAssertNotNil(generated);
    XCTAssertNil(error);

    Secp256k1KeyPair *derived = [Secp256k1KeyPair keyPairWithPrivateKey:generated.privateKey error:&error];
    XCTAssertNotNil(derived);
    XCTAssertNil(error);
    XCTAssertEqualObjects(derived.publicKey, generated.publicKey);
    XCTAssertEqualObjects(derived.compressedPublicKey, generated.compressedPublicKey);

    NSData *message = [@"jwt-key-derivation" dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hashBytes[32];
    CC_SHA256(message.bytes, (CC_LONG)message.length, hashBytes);
    NSData *hash = [NSData dataWithBytes:hashBytes length:sizeof(hashBytes)];

    NSData *signature = [derived signHash:hash error:&error];
    XCTAssertNotNil(signature);
    XCTAssertNil(error);

    BOOL verified = [derived verifySignature:signature forHash:hash error:&error];
    XCTAssertTrue(verified);
    XCTAssertNil(error);
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

- (void)testBase64URLDecodeHandlesModThreeLength {
    NSError *error = nil;
    NSData *decoded = [JWT base64URLDecode:@"YWI" error:&error];

    XCTAssertNotNil(decoded, @"Base64URL decode should handle length %% 4 == 3");
    XCTAssertNil(error, @"No error expected while decoding valid mod-3 input");
    NSString *decodedString = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(decodedString, @"ab");
}

#pragma mark - Fail-Closed Claim Typing (workstream 01 S8 slice 1)

// Builds an unsigned compact JWT string from raw header/payload dictionaries
// so tests can inject claim values of the wrong JSON type. Signature
// verification is never reached by these tests, so the signature segment is
// a fixed placeholder.
- (NSString *)tokenWithHeaderDict:(NSDictionary *)headerDict payloadDict:(NSDictionary *)payloadDict {
    NSError *error = nil;
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:headerDict options:0 error:&error];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:&error];
    NSString *headerEncoded = [JWT base64URLEncodeData:headerData error:&error];
    NSString *payloadEncoded = [JWT base64URLEncodeData:payloadData error:&error];
    return [NSString stringWithFormat:@"%@.%@.%@", headerEncoded, payloadEncoded, @"sig"];
}

- (void)assertTokenRejectedWithHeader:(NSDictionary *)headerDict claim:(NSString *)claim {
    NSString *token = [self tokenWithHeaderDict:headerDict
                                     payloadDict:@{@"sub": @"test-user"}];
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    XCTAssertNil(jwt, @"Header claim '%@' with wrong type should be rejected, not crash", claim);
    XCTAssertNotNil(error, @"Rejection should set an error for claim '%@'", claim);
    XCTAssertEqual(error.domain, JWTErrorDomain);
}

- (void)assertTokenRejectedWithPayload:(NSDictionary *)payloadDict claim:(NSString *)claim {
    NSString *token = [self tokenWithHeaderDict:@{@"alg": @"ES256", @"typ": @"JWT"}
                                     payloadDict:payloadDict];
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    XCTAssertNil(jwt, @"Payload claim '%@' with wrong type should be rejected, not crash", claim);
    XCTAssertNotNil(error, @"Rejection should set an error for claim '%@'", claim);
    XCTAssertEqual(error.domain, JWTErrorDomain);
}

- (void)testHeaderClaimTypeMismatchesAreRejected {
    NSDictionary<NSString *, id> *malformedValues = @{
        @"number": @42,
        @"array": @[@"x"],
        @"object": @{@"x": @1},
        @"null": [NSNull null],
    };
    for (NSString *claim in @[@"alg", @"typ", @"kid", @"cty"]) {
        for (NSString *shape in malformedValues) {
            NSMutableDictionary *header = [@{@"alg": @"ES256", @"typ": @"JWT"} mutableCopy];
            header[claim] = malformedValues[shape];
            [self assertTokenRejectedWithHeader:header claim:[NSString stringWithFormat:@"%@ (%@)", claim, shape]];
        }
    }
}

- (void)testPayloadStringClaimTypeMismatchesAreRejected {
    NSDictionary<NSString *, id> *malformedValues = @{
        @"number": @42,
        @"array": @[@"x"],
        @"object": @{@"x": @1},
        @"null": [NSNull null],
    };
    NSArray<NSString *> *stringClaims = @[@"iss", @"sub", @"jti", @"sid", @"did", @"handle", @"scope", @"lxm", @"token_use"];
    for (NSString *claim in stringClaims) {
        for (NSString *shape in malformedValues) {
            NSMutableDictionary *payload = [@{@"sub": @"test-user"} mutableCopy];
            payload[claim] = malformedValues[shape];
            [self assertTokenRejectedWithPayload:payload claim:[NSString stringWithFormat:@"%@ (%@)", claim, shape]];
        }
    }
}

- (void)testAudObjectShapeIsRejected {
    [self assertTokenRejectedWithPayload:@{@"sub": @"test-user", @"aud": @{@"x": @1}} claim:@"aud (object)"];
}

- (void)testAudNumberShapeIsRejected {
    [self assertTokenRejectedWithPayload:@{@"sub": @"test-user", @"aud": @42} claim:@"aud (number)"];
}

- (void)testAudArrayWithNonStringElementIsRejected {
    [self assertTokenRejectedWithPayload:@{@"sub": @"test-user", @"aud": @[@"valid.aud", @7]} claim:@"aud (mixed array)"];
}

- (void)testAudArrayFormIsAcceptedAndNormalized {
    NSString *token = [self tokenWithHeaderDict:@{@"alg": @"ES256", @"typ": @"JWT"}
                                     payloadDict:@{@"sub": @"test-user", @"aud": @[@"aud-one", @"aud-two"]}];
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    XCTAssertNotNil(jwt, @"Array-valued aud is RFC 7519-legal and must parse");
    XCTAssertNil(error);
    XCTAssertEqualObjects(jwt.payload.aud, @"aud-one", @"aud should hold the first element for single-value consumers");
    XCTAssertEqualObjects(jwt.payload.audiences, (@[@"aud-one", @"aud-two"]), @"audiences should hold the full normalized list");
}

- (void)testAudStringFormIsNormalizedToSingleElementArray {
    NSString *token = [self tokenWithHeaderDict:@{@"alg": @"ES256", @"typ": @"JWT"}
                                     payloadDict:@{@"sub": @"test-user", @"aud": @"solo-aud"}];
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    XCTAssertNotNil(jwt);
    XCTAssertNil(error);
    XCTAssertEqualObjects(jwt.payload.aud, @"solo-aud");
    XCTAssertEqualObjects(jwt.payload.audiences, @[@"solo-aud"]);
}

- (void)testExpStringShapeIsRejectedRatherThanSilentlyIgnored {
    // Before this fix, a string 'exp' silently left payload.exp nil, which
    // JWTVerifier's absent-claim skip then treated as "never expires."
    [self assertTokenRejectedWithPayload:@{@"sub": @"test-user", @"exp": @"1700000000"} claim:@"exp (string)"];
}

- (void)testIatStringShapeIsRejected {
    [self assertTokenRejectedWithPayload:@{@"sub": @"test-user", @"iat": @"1700000000"} claim:@"iat (string)"];
}

- (void)testNbfStringShapeIsRejected {
    [self assertTokenRejectedWithPayload:@{@"sub": @"test-user", @"nbf": @"1700000000"} claim:@"nbf (string)"];
}

- (void)testCnfNonObjectShapeIsRejected {
    [self assertTokenRejectedWithPayload:@{@"sub": @"test-user", @"cnf": @"not-an-object"} claim:@"cnf (string)"];
}

#pragma mark - Required Claims and Algorithm Binding (workstream 01 S8 slice 2)

- (void)testAbsentExpIsRejected {
    // exp is mandatory: a token without exp must never be accepted.
    NSError *error = nil;
    NSDictionary *payload = @{
        @"sub": @"test-user",
        @"iss": @"test.issuer",
        @"aud": @"test.audience",
        @"iat": @([[NSDate date] timeIntervalSince1970])
    };
    NSString *token = [self.minter signPayload:payload error:&error];
    XCTAssertNotNil(token);
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    XCTAssertNotNil(jwt);

    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertFalse(verified, @"Token without exp must be rejected");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, JWTErrorMissingRequiredClaim);
}

- (void)testAbsentIssIsRejectedWhenExpectedIssuerIsSet {
    // iss mandatory when expectedIssuer is set: nil iss must not
    // silently bypass the issuer check.
    NSError *error = nil;
    NSDictionary *payload = @{
        @"sub": @"test-user",
        @"aud": @"test.audience",
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:3600] timeIntervalSince1970]),
        @"iat": @([[NSDate date] timeIntervalSince1970])
    };
    NSString *token = [self.minter signPayload:payload error:&error];
    XCTAssertNotNil(token);
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    XCTAssertNotNil(jwt);

    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertFalse(verified, @"Token without iss must be rejected when expectedIssuer is set");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, JWTErrorMissingRequiredClaim);
}

- (void)testAbsentAudIsRejectedWhenExpectedAudienceIsSet {
    // aud mandatory when expectedAudience is set: nil aud must not
    // silently bypass the audience check.
    NSError *error = nil;
    NSDictionary *payload = @{
        @"sub": @"test-user",
        @"iss": @"test.issuer",
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:3600] timeIntervalSince1970]),
        @"iat": @([[NSDate date] timeIntervalSince1970])
    };
    NSString *token = [self.minter signPayload:payload error:&error];
    XCTAssertNotNil(token);
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    XCTAssertNotNil(jwt);

    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertFalse(verified, @"Token without aud must be rejected when expectedAudience is set");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, JWTErrorMissingRequiredClaim);
}

- (void)testAllowedAlgorithmsUnsetFailsClosed {
    // If allowedAlgorithms is nil, verification must fail closed rather
    // than silently accepting any algorithm.
    NSError *error = nil;
    NSDictionary *payload = @{
        @"sub": @"test-user",
        @"iss": @"test.issuer",
        @"aud": @"test.audience",
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:3600] timeIntervalSince1970]),
        @"iat": @([[NSDate date] timeIntervalSince1970])
    };
    NSString *token = [self.minter signPayload:payload error:&error];
    JWT *jwt = [JWT jwtWithToken:token error:&error];

    JWTVerifier *unrestrictedVerifier = [[JWTVerifier alloc] init];
    unrestrictedVerifier.expectedIssuer = @"test.issuer";
    unrestrictedVerifier.expectedAudience = @"test.audience";
    unrestrictedVerifier.publicKey = self.verifier.publicKey;
    // allowedAlgorithms deliberately left nil

    BOOL verified = [unrestrictedVerifier verifyJWT:jwt error:&error];
    XCTAssertFalse(verified, @"Verifier with no allowedAlgorithms must fail closed");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, JWTErrorInvalidAlgorithm);
}

- (void)testAudienceArrayAnyElementMatches {
    // Per RFC 7519 §4.1.3, a token is intended for a principal if any
    // element of the aud array matches. The expected audience is
    // "test.audience"; the token's aud array contains it as the second
    // element.
    NSError *error = nil;
    NSDictionary *payload = @{
        @"sub": @"test-user",
        @"iss": @"test.issuer",
        @"aud": @[@"other.audience", @"test.audience"],
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:3600] timeIntervalSince1970]),
        @"iat": @([[NSDate date] timeIntervalSince1970])
    };
    NSString *token = [self.minter signPayload:payload error:&error];
    XCTAssertNotNil(token);
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    XCTAssertNotNil(jwt);
    XCTAssertEqualObjects(jwt.payload.audiences, (@[@"other.audience", @"test.audience"]));

    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertTrue(verified, @"Token with matching audience in array should verify");
    XCTAssertNil(error);
}

- (void)testAudienceArrayNoMatchIsRejected {
    // None of the aud array elements match the expected audience.
    NSError *error = nil;
    NSDictionary *payload = @{
        @"sub": @"test-user",
        @"iss": @"test.issuer",
        @"aud": @[@"other.audience", @"another.audience"],
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:3600] timeIntervalSince1970]),
        @"iat": @([[NSDate date] timeIntervalSince1970])
    };
    NSString *token = [self.minter signPayload:payload error:&error];
    JWT *jwt = [JWT jwtWithToken:token error:&error];

    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertFalse(verified, @"Token with no matching audience in array should be rejected");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, JWTErrorInvalidAudience);
}

- (void)testClockOffsetUsedForTimeComparison {
    // clockOffset allows tests to set a fixed time for deterministic
    // expiry checks. Set clockOffset to the past so a token that is
    // valid now appears expired.
    NSError *error = nil;
    NSDictionary *payload = @{
        @"sub": @"test-user",
        @"iss": @"test.issuer",
        @"aud": @"test.audience",
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:3600] timeIntervalSince1970]),
        @"iat": @([[NSDate date] timeIntervalSince1970])
    };
    NSString *token = [self.minter signPayload:payload error:&error];
    JWT *jwt = [JWT jwtWithToken:token error:&error];

    // Set clockOffset 2 hours in the future: the token's exp (1 hour
    // from now) is in the past relative to clockOffset.
    self.verifier.clockOffset = [[NSDate date] dateByAddingTimeInterval:7200];

    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertFalse(verified, @"Token should be expired relative to clockOffset");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, JWTErrorTokenExpired);
}

- (void)testDefaultClockUsesLiveTimeRatherThanConstructionTime {
    // Give the token a short lifetime after the verifier already exists. A
    // verifier that freezes time during init would still accept it; the
    // default path must observe that it has expired by verification time.
    NSError *error = nil;
    NSDictionary *payload = @{
        @"sub": @"test-user",
        @"iss": @"test.issuer",
        @"aud": @"test.audience",
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:0.005] timeIntervalSince1970]),
        @"iat": @([[NSDate date] timeIntervalSince1970])
    };
    NSString *token = [self.minter signPayload:payload error:&error];
    XCTAssertNotNil(token, @"Token signing failed: %@", error);
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    XCTAssertNotNil(jwt, @"Token parsing failed: %@", error);

    [NSThread sleepForTimeInterval:0.02];
    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    XCTAssertFalse(verified, @"A default verifier must use live time and reject an expired token");
    XCTAssertEqual(error.code, JWTErrorTokenExpired);
}

@end
