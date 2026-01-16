#import <XCTest/XCTest.h>
#import "Auth/DPoPUtil.h"

@interface OAuthDPoPTests : XCTestCase
@end

@implementation OAuthDPoPTests

- (void)testDPoPProofStructure {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"POST" uri:@"https://server.example.com/tokens" nonce:nil error:&error];
    
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
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"GET" uri:@"https://resource.example.org/protected" nonce:nil error:&error];
    XCTAssertNotNil(token);
    
    BOOL valid = [DPoPUtil verifyDPoP:token.jwt
                        withPublicKey:NULL
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
    XCTAssertEqualObjects(error.domain, @"com.atproto.pds.dpop");
}

- (void)testDPoPHtuBinding {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"POST" uri:@"https://server.example.com/a" nonce:nil error:&error];
    
    BOOL valid = [DPoPUtil verifyDPoP:token.jwt
                        withPublicKey:NULL
                               method:@"POST"
                                  uri:@"https://server.example.com/b"
                                nonce:nil
                                error:&error];
    XCTAssertFalse(valid, @"Mismatching URI should fail");
}

- (void)testDPoPNonceChallenge {
    NSError *error = nil;
    NSString *nonce = @"random-nonce-value";
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"POST" uri:@"https://server.com" nonce:nonce error:&error];
    
    XCTAssertNotNil(token);
    
    BOOL valid = [DPoPUtil verifyDPoP:token.jwt
                        withPublicKey:NULL
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
    XCTAssertEqual(error.code, -2);
    
    valid = [DPoPUtil verifyDPoP:@"a.b" withPublicKey:NULL method:@"GET" uri:@"https://example.com" nonce:nil error:&error];
    XCTAssertFalse(valid);
}

- (void)testDPoPTokenProperties {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"PUT" uri:@"https://api.example.com/resource/123" nonce:@"test-nonce" error:&error];
    
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
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"DELETE" uri:@"https://server.com/item/1" nonce:nil error:&error];
    
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
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"GET" uri:@"https://example.com" nonce:nil error:&error];
    token.ath = @"access-token-hash";
    
    NSDictionary *payload = [token payload];
    XCTAssertEqualObjects(payload[@"ath"], @"access-token-hash");
}

- (void)testDPoPNoNonce {
    NSError *error = nil;
    DPoPToken *token = [DPoPUtil createDPoPForMethod:@"GET" uri:@"https://example.com" nonce:nil error:&error];
    
    XCTAssertNotNil(token);
    XCTAssertNil(token.nonce);
    
    NSDictionary *payload = [token payload];
    XCTAssertNil(payload[@"nonce"]);
}

- (void)testDPoPEmptyJWTParts {
    NSError *error = nil;
    BOOL valid = [DPoPUtil verifyDPoP:@"a..c" withPublicKey:NULL method:@"GET" uri:@"https://example.com" nonce:nil error:&error];
    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
}

@end
