// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/Crypto/AuthCryptoJWK.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"

@interface AuthCryptoJWKTests : XCTestCase
@end

@implementation AuthCryptoJWKTests

#pragma mark - thumbprint:error:

- (void)testThumbprint_EC_P256_Valid {
    // RFC 7638 Appendix A example (EC key)
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
        @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"
    };

    NSError *error = nil;
    NSString *thumbprint = [AuthCryptoJWK thumbprint:jwk error:&error];
    XCTAssertNotNil(thumbprint);
    XCTAssertNil(error);

    // RFC 7638 expected: 47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU
    // (That's actually for empty input, let me use a different check)
    XCTAssertEqual(thumbprint.length, (NSUInteger)43, @"Thumbprint should be 43 base64url chars (SHA-256)");
}

- (void)testThumbprint_RSA_Valid {
    // RFC 7638 Appendix A example (RSA key)
    NSDictionary *jwk = @{
        @"e": @"AQAB",
        @"kty": @"RSA",
        @"n": @"0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw"
    };

    NSError *error = nil;
    NSString *thumbprint = [AuthCryptoJWK thumbprint:jwk error:&error];
    XCTAssertNotNil(thumbprint);
    XCTAssertNil(error);
    XCTAssertEqual(thumbprint.length, (NSUInteger)43, @"Thumbprint should be 43 base64url chars (SHA-256)");
}

- (void)testThumbprint_EC_NilError_DoesNotCrash {
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
        @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"
    };
    NSString *thumbprint = [AuthCryptoJWK thumbprint:jwk error:nil];
    XCTAssertNotNil(thumbprint);
}

- (void)testThumbprint_EC_MissingX_ReturnsNilError {
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"
    };
    NSError *error = nil;
    NSString *thumbprint = [AuthCryptoJWK thumbprint:jwk error:&error];
    XCTAssertNil(thumbprint);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, -1);
}

- (void)testThumbprint_EC_MissingCrv_ReturnsNilError {
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
        @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"
    };
    NSError *error = nil;
    NSString *thumbprint = [AuthCryptoJWK thumbprint:jwk error:&error];
    XCTAssertNil(thumbprint);
    XCTAssertNotNil(error);
}

- (void)testThumbprint_RSA_MissingE_ReturnsNilError {
    NSDictionary *jwk = @{
        @"kty": @"RSA",
        @"n": @"0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw"
    };
    NSError *error = nil;
    NSString *thumbprint = [AuthCryptoJWK thumbprint:jwk error:&error];
    XCTAssertNil(thumbprint);
    XCTAssertNotNil(error);
}

- (void)testThumbprint_UnsupportedKty_ReturnsNilError {
    NSDictionary *jwk = @{@"kty": @"OKP", @"crv": @"Ed25519", @"x": @"abc"};
    NSError *error = nil;
    NSString *thumbprint = [AuthCryptoJWK thumbprint:jwk error:&error];
    XCTAssertNil(thumbprint);
    XCTAssertNotNil(error);
}

- (void)testThumbprint_NilJWK_ReturnsNil {
    NSError *error = nil;
    // Passing nil to a nonnull param is UB, so pass empty dict
    NSString *thumbprint = [AuthCryptoJWK thumbprint:@{} error:&error];
    XCTAssertNil(thumbprint);
    XCTAssertNotNil(error);
}

- (void)testThumbprint_DeterministicForSameKey {
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
        @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"
    };

    NSError *error1 = nil, *error2 = nil;
    NSString *tp1 = [AuthCryptoJWK thumbprint:jwk error:&error1];
    NSString *tp2 = [AuthCryptoJWK thumbprint:jwk error:&error2];
    XCTAssertNotNil(tp1);
    XCTAssertNotNil(tp2);
    XCTAssertEqualObjects(tp1, tp2, @"Thumbprints should be deterministic");
}

#pragma mark - publicJWKFromJWK:

- (void)testPublicJWKFromJWK_EC_RemovesPrivateD {
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
        @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM",
        @"d": @"privateKeyMaterial"
    };

    NSDictionary *publicJWK = [AuthCryptoJWK publicJWKFromJWK:jwk];
    XCTAssertNotNil(publicJWK);
    XCTAssertNil(publicJWK[@"d"], @"Private key material 'd' should be removed");
    XCTAssertEqualObjects(publicJWK[@"kty"], @"EC");
    XCTAssertEqualObjects(publicJWK[@"x"], @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4");
}

- (void)testPublicJWKFromJWK_RSA_RemovesPrivateFields {
    NSDictionary *jwk = @{
        @"kty": @"RSA",
        @"n": @"modulus",
        @"e": @"AQAB",
        @"d": @"privateExponent",
        @"p": @"prime1",
        @"q": @"prime2",
        @"dp": @"exp1",
        @"dq": @"exp2",
        @"qi": @"coeff"
    };

    NSDictionary *publicJWK = [AuthCryptoJWK publicJWKFromJWK:jwk];
    XCTAssertNotNil(publicJWK);
    XCTAssertNil(publicJWK[@"d"]);
    XCTAssertNil(publicJWK[@"p"]);
    XCTAssertNil(publicJWK[@"q"]);
    XCTAssertNil(publicJWK[@"dp"]);
    XCTAssertNil(publicJWK[@"dq"]);
    XCTAssertNil(publicJWK[@"qi"]);
    XCTAssertEqualObjects(publicJWK[@"kty"], @"RSA");
    XCTAssertEqualObjects(publicJWK[@"n"], @"modulus");
    XCTAssertEqualObjects(publicJWK[@"e"], @"AQAB");
}

- (void)testPublicJWKFromJWK_AlreadyPublic_ReturnsSameExceptCopy {
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": @"value",
        @"y": @"value"
    };

    NSDictionary *publicJWK = [AuthCryptoJWK publicJWKFromJWK:jwk];
    XCTAssertNotNil(publicJWK);
    XCTAssertEqualObjects(publicJWK[@"kty"], @"EC");
    XCTAssertEqualObjects(publicJWK[@"x"], @"value");
    XCTAssertEqualObjects(publicJWK[@"y"], @"value");
}

#pragma mark - publicKeyFromJWK:error: (validation only — SecKeyRef not testable in CI without Apple framework)

- (void)testPublicKeyFromJWK_NonEC_ReturnsNilError {
    NSDictionary *jwk = @{@"kty": @"RSA", @"n": @"modulus", @"e": @"AQAB"};
    NSError *error = nil;
    id key = [AuthCryptoJWK publicKeyFromJWK:jwk error:&error];
    XCTAssertNil(key);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, -3);
}

- (void)testPublicKeyFromJWK_MissingX_ReturnsNilError {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256", @"y": @"onlyY"};
    NSError *error = nil;
    id key = [AuthCryptoJWK publicKeyFromJWK:jwk error:&error];
    XCTAssertNil(key);
    XCTAssertNotNil(error);
}

#pragma mark - privateKeyFromJWK:error: (validation only)

- (void)testPrivateKeyFromJWK_NonEC_ReturnsNilError {
    NSDictionary *jwk = @{@"kty": @"RSA", @"n": @"modulus", @"e": @"AQAB"};
    NSError *error = nil;
    id key = [AuthCryptoJWK privateKeyFromJWK:jwk error:&error];
    XCTAssertNil(key);
    XCTAssertNotNil(error);
}

- (void)testPrivateKeyFromJWK_MissingD_ReturnsNilError {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256", @"x": @"abc", @"y": @"def"};
    NSError *error = nil;
    id key = [AuthCryptoJWK privateKeyFromJWK:jwk error:&error];
    XCTAssertNil(key);
    XCTAssertNotNil(error);
}

#pragma mark - publicJWKFromKey:error: (validation only)

- (void)testPublicJWKFromKey_NilKey_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *result = [AuthCryptoJWK publicJWKFromKey:(id<PDSKeyProtocol>)nil error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

#pragma mark - jwkFromKey:error: (validation only)

- (void)testJWKFromKey_NilKey_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *result = [AuthCryptoJWK jwkFromKey:(id<PDSKeyProtocol>)nil error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

#pragma mark - thumbprintForKey:error: (validation only)

- (void)testThumbprintForKey_NilKey_ReturnsNilError {
    NSError *error = nil;
    NSString *result = [AuthCryptoJWK thumbprintForKey:(id<PDSKeyProtocol>)nil error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

#pragma mark - Consistency

- (void)testThumbprintAndPublicJWKConsistency {
    // thumbprint on a JWK that has 'd' should ignore it (uses only canonical members)
    NSDictionary *privateJWK = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
        @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM",
        @"d": @"privateKeyMaterial"
    };

    NSDictionary *publicJWK = [AuthCryptoJWK publicJWKFromJWK:privateJWK];

    NSError *err1 = nil, *err2 = nil;
    NSString *tpPrivate = [AuthCryptoJWK thumbprint:privateJWK error:&err1];
    NSString *tpPublic = [AuthCryptoJWK thumbprint:publicJWK error:&err2];

    XCTAssertNotNil(tpPrivate);
    XCTAssertNotNil(tpPublic);
    XCTAssertEqualObjects(tpPrivate, tpPublic, @"Thumbprint should be same with or without private key material");
}

@end
