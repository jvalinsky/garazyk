// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/DPoPUtil.h"
#import "Auth/Crypto/AuthCryptoDPoP.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"
#import "Auth/PDSReplayCache.h"
#import "Auth/TestKeyFixtures.h"


@interface OAuthDPoPTests : XCTestCase {
    SecKeyRef _privateKey;
    SecKeyRef _publicKey;
}
@end

@implementation OAuthDPoPTests

- (void)setUp {
    [super setUp];
    NSError *error = nil;
    _privateKey = PDSTestCreateFixedP256PrivateKey(&error);
    if (_privateKey == NULL) {
        XCTSkip(@"Skipping DPoP tests: fixed key import unavailable (%@)", error);
    }
    _publicKey = SecKeyCopyPublicKey(_privateKey);
}

- (void)tearDown {
    if (_privateKey) CFRelease(_privateKey);
    if (_publicKey) CFRelease(_publicKey);
    [super tearDown];
}

- (void)testDPoPProofStructure {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"POST" uri:@"https://server.example.com/tokens" nonce:nil key:_privateKey error:&error];
    
    XCTAssertNotNil(token, @"Should create token");
    XCTAssertNil(error, @"Should be no error");
    XCTAssertNotNil(token.jwt, @"JWT string should be present");
    
    NSArray *parts = [token.jwt componentsSeparatedByString:@"."];
    XCTAssertEqual(parts.count, 3, @"JWT should have 3 parts");
    
    NSString *headerB64 = parts[0];
    NSMutableString *padded = [headerB64 mutableCopy];
    if (padded.length % 4 > 0) [padded appendString:[@"====" substringToIndex:(4 - (padded.length % 4))]];
    NSString *safeB64 = [[padded stringByReplacingOccurrencesOfString:@"-" withString:@"+"] stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    NSData *headerData = [[NSData alloc] initWithBase64EncodedString:safeB64 options:0];
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:nil];
    
    XCTAssertEqualObjects(header[@"typ"], @"dpop+jwt", @"Header typ must be dpop+jwt");
    XCTAssertEqualObjects(header[@"alg"], @"ES256", @"Header alg must be ES256");
    XCTAssertNotNil(header[@"jwk"], @"Header should contain jwk");
}

- (void)testDPoPHtmBinding {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"GET" uri:@"https://resource.example.org/protected" nonce:nil key:_privateKey error:&error];
    XCTAssertNotNil(token);
    
    BOOL valid = [DPoPUtil verifyDPoP:token.jwt
                        withPublicKey:_publicKey
                               method:@"GET"
                                  uri:@"https://resource.example.org/protected"
                                nonce:nil
                                error:&error];
    XCTAssertTrue(valid, @"Matching method should pass");
    
    error = nil;
    valid = [DPoPUtil verifyDPoP:token.jwt
                   withPublicKey:NULL
                          method:@"POST"
                             uri:@"https://resource.example.org/protected"
                           nonce:nil
                           error:&error];
    XCTAssertFalse(valid, @"Mismatching method should fail");
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, AuthCryptoDPoPErrorDomain);
}

- (void)testVerifyDPoPFalseMismatchingUriForHtuBinding {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"POST" uri:@"https://server.example.com/a" nonce:nil key:_privateKey error:&error];
    
    BOOL valid = [DPoPUtil verifyDPoP:token.jwt
                        withPublicKey:_publicKey
                               method:@"POST"
                                  uri:@"https://server.example.com/b"
                                nonce:nil
                                error:&error];
    XCTAssertFalse(valid, @"Mismatching URI should fail");
}

- (void)testDPoPHtuCanonicalizationExcludesQueryAndFragment {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"GET"
                                                  uri:@"https://server.example.com/resource?id=123#frag"
                                               nonce:nil
                                                 key:_privateKey
                                               error:&error];
    XCTAssertNotNil(token);
    XCTAssertNil(error);
    XCTAssertEqualObjects(token.htu, @"https://server.example.com/resource");

    BOOL valid = [DPoPUtil verifyDPoP:token.jwt
                        withPublicKey:_publicKey
                               method:@"GET"
                                  uri:@"https://server.example.com/resource?other=1"
                                nonce:nil
                                error:&error];
    XCTAssertTrue(valid, @"DPoP htu verification should ignore query/fragment");
}

- (void)testDPoPNonceChallenge {
    NSError *error = nil;
    NSString *nonce = @"random-nonce-value";
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"POST" uri:@"https://server.com" nonce:nonce key:_privateKey error:&error];
    
    XCTAssertNotNil(token);
    
    BOOL valid = [DPoPUtil verifyDPoP:token.jwt
                        withPublicKey:_publicKey
                               method:@"POST"
                                  uri:@"https://server.com"
                                nonce:nonce
                                error:&error];
    XCTAssertTrue(valid, @"Correct nonce should pass");
    
    error = nil;
    valid = [DPoPUtil verifyDPoP:token.jwt
                   withPublicKey:NULL
                          method:@"POST"
                             uri:@"https://server.com"
                           nonce:@"other-nonce"
                           error:&error];
    XCTAssertFalse(valid, @"Incorrect nonce should fail");
}

- (void)testDPoPInvalidFormat {
    NSError *error = nil;
    BOOL valid = [DPoPUtil verifyDPoP:@"not-a-jwt" withPublicKey:NULL method:@"GET" uri:@"https://example.com" nonce:nil error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, -1);
    
    valid = [DPoPUtil verifyDPoP:@"a.b" withPublicKey:NULL method:@"GET" uri:@"https://example.com" nonce:nil error:&error];
    XCTAssertFalse(valid);
}

- (void)testDPoPTokenProperties {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"PUT" uri:@"https://api.example.com/resource/123" nonce:@"test-nonce" key:_privateKey error:&error];
    
    XCTAssertNotNil(token);
    XCTAssertEqualObjects(token.htm, @"PUT");
    XCTAssertEqualObjects(token.htu, @"https://api.example.com/resource/123");
    XCTAssertEqualObjects(token.nonce, @"test-nonce");
    XCTAssertNotNil(token.jti);
    XCTAssertNotNil(token.iat);
    XCTAssertNotNil(token.exp);
}

- (void)testDPoPPayloadClaims {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"DELETE" uri:@"https://server.com/item/1" nonce:nil key:_privateKey error:&error];
    
    NSDictionary *payload = [token payload];
    XCTAssertEqualObjects(payload[@"htm"], @"DELETE");
    XCTAssertEqualObjects(payload[@"htu"], @"https://server.com/item/1");
    XCTAssertNotNil(payload[@"iat"]);
    XCTAssertNotNil(payload[@"jti"]);
    XCTAssertNotNil(payload[@"exp"]);
}

- (void)testDPoPHeaderClaims {
    DPoPToken *token = [[DPoPToken alloc] init];
    NSDictionary *header = [token header];
    
    XCTAssertEqualObjects(header[@"typ"], @"dpop+jwt");
    XCTAssertEqualObjects(header[@"alg"], @"ES256");
    XCTAssertNotNil(header[@"jwk"]);
    XCTAssertEqualObjects(header[@"jwk"][@"kty"], @"EC");
    XCTAssertEqualObjects(header[@"jwk"][@"crv"], @"P-256");
}

- (void)testDPoPWithAthClaim {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"GET" uri:@"https://example.com" nonce:nil key:_privateKey error:&error];
    token.ath = @"access-token-hash";
    
    NSDictionary *payload = [token payload];
    XCTAssertEqualObjects(payload[@"ath"], @"access-token-hash");
}

- (void)testDPoPNoNonce {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"GET" uri:@"https://example.com" nonce:nil key:_privateKey error:&error];
    
    XCTAssertNotNil(token);
    XCTAssertNil(token.nonce);
    
    NSDictionary *payload = [token payload];
    XCTAssertNil(payload[@"nonce"]);
}

- (void)testVerifyDPoPFalseForEmptyJWTParts {
    NSError *error = nil;
    BOOL valid = [DPoPUtil verifyDPoP:@"a..c" withPublicKey:NULL method:@"GET" uri:@"https://example.com" nonce:nil error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
}

#pragma mark - Fail-Closed Claim Typing (workstream 01 S8 slice 1)

// Builds an unsigned compact DPoP-shaped JWT from raw header/payload
// dictionaries so tests can inject claim values of the wrong JSON type.
// The signature segment is a fixed placeholder; these tests only need to
// reach ATProtoAuthCryptoDPoP's type-checking of the header/payload claims, which
// runs before signature verification.
- (NSString *)dpopProofWithHeaderDict:(NSDictionary *)headerDict payloadDict:(NSDictionary *)payloadDict {
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:headerDict options:0 error:nil];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:nil];
    NSString *headerEncoded = [ATProtoAuthCryptoBase64URL encode:headerData];
    NSString *payloadEncoded = [ATProtoAuthCryptoBase64URL encode:payloadData];
    NSData *sigData = [@"0123456789012345678901234567890123456789012345678901234567890a" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *sigEncoded = [ATProtoAuthCryptoBase64URL encode:sigData];
    return [NSString stringWithFormat:@"%@.%@.%@", headerEncoded, payloadEncoded, sigEncoded];
}

- (void)testDPoPHeaderClaimTypeMismatchesAreRejectedNotCrashed {
    NSDictionary<NSString *, id> *malformedShapes = @{
        @"number": @1,
        @"array": @[@"x"],
        @"null": [NSNull null],
    };
    NSDictionary *validPayload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": @"jti-1"};
    for (NSString *claim in @[@"typ", @"alg"]) {
        for (NSString *shape in malformedShapes) {
            NSMutableDictionary *header = [@{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": @{@"kty": @"EC"}} mutableCopy];
            header[claim] = malformedShapes[shape];
            NSString *proof = [self dpopProofWithHeaderDict:header payloadDict:validPayload];
            NSError *error = nil;
            BOOL valid = [ATProtoAuthCryptoDPoP verifyProof:proof method:@"GET" url:[NSURL URLWithString:@"https://example.com"]
                                                nonce:nil requireNonce:NO nonceValidator:nil replayChecker:[PDSReplayCache sharedCache]
                                        outThumbprint:nil expectedAccessToken:nil error:&error];
            XCTAssertFalse(valid, @"DPoP header claim '%@' (%@) with wrong type must be rejected, not crash", claim, shape);
            XCTAssertNotNil(error, @"Rejection should set an error for claim '%@' (%@)", claim, shape);
            XCTAssertEqualObjects(error.domain, AuthCryptoDPoPErrorDomain);
        }
    }
}

- (void)testDPoPStringValuedJwkIsRejectedNotCrashed {
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": @"not-an-object"};
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": @"jti-1"};
    NSString *proof = [self dpopProofWithHeaderDict:header payloadDict:payload];
    NSError *error = nil;
    BOOL valid = [ATProtoAuthCryptoDPoP verifyProof:proof method:@"GET" url:[NSURL URLWithString:@"https://example.com"]
                                        nonce:nil requireNonce:NO nonceValidator:nil replayChecker:[PDSReplayCache sharedCache]
                                outThumbprint:nil expectedAccessToken:nil error:&error];
    XCTAssertFalse(valid, @"String-valued jwk must be rejected, not crash on jwk[@\"d\"] subscript");
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, AuthCryptoDPoPErrorDomain);
}

- (void)testDPoPPayloadClaimTypeMismatchesAreRejectedNotCrashed {
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": @{@"kty": @"EC"}};
    NSDictionary<NSString *, id> *malformedShapes = @{
        @"number": @1,
        @"array": @[@"x"],
        @"object": @{@"x": @1},
    };
    for (NSString *claim in @[@"htm", @"htu"]) {
        for (NSString *shape in malformedShapes) {
            NSMutableDictionary *payload = [@{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": @"jti-1"} mutableCopy];
            payload[claim] = malformedShapes[shape];
            NSString *proof = [self dpopProofWithHeaderDict:header payloadDict:payload];
            NSError *error = nil;
            BOOL valid = [ATProtoAuthCryptoDPoP verifyProof:proof method:@"GET" url:[NSURL URLWithString:@"https://example.com"]
                                                nonce:nil requireNonce:NO nonceValidator:nil replayChecker:[PDSReplayCache sharedCache]
                                        outThumbprint:nil expectedAccessToken:nil error:&error];
            XCTAssertFalse(valid, @"DPoP payload claim '%@' (%@) with wrong type must be rejected, not crash", claim, shape);
            XCTAssertNotNil(error);
            XCTAssertEqualObjects(error.domain, AuthCryptoDPoPErrorDomain);
        }
    }
}

- (void)testDPoPReplayDetection {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"POST"
                                                  uri:@"https://server.example.com/tokens"
                                               nonce:nil
                                                 key:_privateKey
                                               error:&error];
    XCTAssertNotNil(token, @"Should create DPoP token for replay test");

    // First verification should succeed
    BOOL firstValid = [DPoPUtil verifyDPoP:token.jwt
                              withPublicKey:_publicKey
                                     method:@"POST"
                                        uri:@"https://server.example.com/tokens"
                                      nonce:nil
                                      error:&error];
    XCTAssertTrue(firstValid, @"First verification should succeed");

    // Second verification of the same JWT should fail (replay detected)
    error = nil;
    BOOL replayValid = [DPoPUtil verifyDPoP:token.jwt
                              withPublicKey:_publicKey
                                     method:@"POST"
                                        uri:@"https://server.example.com/tokens"
                                      nonce:nil
                                      error:&error];
    XCTAssertFalse(replayValid, @"Replayed DPoP proof should be rejected");
    XCTAssertNotNil(error, @"Replay should produce an error");
}

@end
