// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/Crypto/AuthCryptoBase64URL.h"
#import "Auth/Crypto/AuthCryptoDPoP.h"
#import "Auth/PDSReplayCache.h"
#import "Auth/Base32Utils.h"

#pragma mark - AuthCryptoDPoP Tests

@interface AuthCryptoDPoPReplaySpy : NSObject <AuthCryptoDPoPReplayChecker>
@property (nonatomic, assign) NSUInteger callCount;
@end

@implementation AuthCryptoDPoPReplaySpy

- (BOOL)checkAndAddJTI:(NSString *)jti expiration:(NSDate *)expiration {
    (void)jti;
    (void)expiration;
    self.callCount += 1;
    return YES;
}

@end

@interface AuthCryptoDPoPTests : XCTestCase
@end

@implementation AuthCryptoDPoPTests

- (void)testCanonicalHTUFromURLBasic {
    NSURL *url = [NSURL URLWithString:@"https://example.com/path"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com/path");
}

- (void)testCanonicalHTUFromStringBasic {
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromString:@"https://example.com/path"];
    XCTAssertEqualObjects(htu, @"https://example.com/path");
}

- (void)testCanonicalHTUStripsQuery {
    NSURL *url = [NSURL URLWithString:@"https://example.com/path?query=1"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com/path");
}

- (void)testCanonicalHTUStripsFragment {
    NSURL *url = [NSURL URLWithString:@"https://example.com/path#fragment"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com/path");
}

- (void)testCanonicalHTUDefaultPortHTTPS {
    NSURL *url = [NSURL URLWithString:@"https://example.com:443/path"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com/path");
}

- (void)testCanonicalHTUDefaultPortHTTP {
    NSURL *url = [NSURL URLWithString:@"http://example.com:80/path"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"http://example.com/path");
}

- (void)testCanonicalHTUNonDefaultPort {
    NSURL *url = [NSURL URLWithString:@"https://example.com:8443/path"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com:8443/path");
}

- (void)testCanonicalHTULowercasesSchemeAndHost {
    NSURL *url = [NSURL URLWithString:@"HTTPS://EXAMPLE.COM/path"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com/path");
}

- (void)testCanonicalHTUDefaultPath {
    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    XCTAssertEqualObjects(htu, @"https://example.com");
}

- (void)testCanonicalHTUNilURL {
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:nil];
    XCTAssertEqualObjects(htu, @"");
}

- (void)testCanonicalHTUFromStringNil {
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromString:nil];
    XCTAssertNil(htu);
}

- (void)testCanonicalHTUFromStringInvalid {
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromString:@"not a url"];
    XCTAssertNotNil(htu);
}

- (void)testVerifyProofNilJWT {
    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:nil
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:[PDSReplayCache sharedCache]
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofInvalidFormat {
    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:@"not-a-jwt"
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:[PDSReplayCache sharedCache]
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofInvalidHeaderEncoding {
    NSString *badJwt = @"!!!invalid!!!.eyJodG0iOiJHRVQifQ.signature";
    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:[PDSReplayCache sharedCache]
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofWrongTyp {
    NSDictionary *header = @{@"typ": @"JWT", @"alg": @"ES256", @"jwk": @{@"kty": @"EC"}};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:[PDSReplayCache sharedCache]
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofWrongAlg {
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"RS256", @"jwk": @{@"kty": @"EC"}};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:[PDSReplayCache sharedCache]
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofMissingJWK {
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256"};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:[PDSReplayCache sharedCache]
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofJWKWithPrivateKeyMaterial {
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": @{@"kty": @"EC", @"d": @"private-key"}};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:[PDSReplayCache sharedCache]
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofHtmMismatch {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256", @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4", @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"};
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": jwk};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"POST", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:[PDSReplayCache sharedCache]
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofMissingIat {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256", @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4", @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"};
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": jwk};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:[PDSReplayCache sharedCache]
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofExpiredIat {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256", @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4", @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"};
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": jwk};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSTimeInterval oldIat = [[NSDate date] timeIntervalSince1970] - 600;
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @(oldIat), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:nil
                                  requireNonce:NO
                                nonceValidator:nil
                                 replayChecker:[PDSReplayCache sharedCache]
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofRequireNonceMissing {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256", @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4", @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"};
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": jwk};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString]};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:@"expected-nonce"
                                  requireNonce:YES
                                nonceValidator:nil
                                 replayChecker:[PDSReplayCache sharedCache]
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyProofNonceMismatch {
    NSDictionary *jwk = @{@"kty": @"EC", @"crv": @"P-256", @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4", @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"};
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": jwk};
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSDictionary *payload = @{@"htm": @"GET", @"htu": @"https://example.com", @"iat": @([[NSDate date] timeIntervalSince1970]), @"jti": [[NSUUID UUID] UUIDString], @"nonce": @"wrong-nonce"};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *badJwt = [NSString stringWithFormat:@"%@.%@.fakesignature", headerEnc, payloadEnc];

    NSURL *url = [NSURL URLWithString:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [AuthCryptoDPoP verifyProof:badJwt
                                        method:@"GET"
                                           url:url
                                         nonce:@"expected-nonce"
                                  requireNonce:YES
                                nonceValidator:nil
                                 replayChecker:[PDSReplayCache sharedCache]
                                 outThumbprint:nil
                                         error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testInvalidSignatureDoesNotConsumeReplayIdentifier {
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": @"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
        @"y": @"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM"
    };
    NSDictionary *header = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": jwk};
    NSDictionary *payload = @{
        @"htm": @"GET",
        @"htu": @"https://example.com",
        @"iat": @([[NSDate date] timeIntervalSince1970]),
        @"jti": @"untrusted-jti"
    };
    NSString *headerEnc = [AuthCryptoBase64URL
        encode:[NSJSONSerialization dataWithJSONObject:header options:0 error:nil]];
    NSString *payloadEnc = [AuthCryptoBase64URL
        encode:[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil]];
    NSString *proof = [NSString stringWithFormat:@"%@.%@.invalid-signature",
                                                  headerEnc, payloadEnc];
    AuthCryptoDPoPReplaySpy *replaySpy = [[AuthCryptoDPoPReplaySpy alloc] init];
    NSError *error = nil;

    BOOL valid = [AuthCryptoDPoP verifyProof:proof
                                      method:@"GET"
                                         url:[NSURL URLWithString:@"https://example.com"]
                                       nonce:nil
                                requireNonce:NO
                              nonceValidator:nil
                               replayChecker:replaySpy
                               outThumbprint:nil
                                       error:&error];

    XCTAssertFalse(valid);
    XCTAssertNotNil(error);
    XCTAssertEqual(replaySpy.callCount, 0u,
                   @"A proof must authenticate before its JTI is recorded");
}

- (void)testCreateProofMissingParameters {
    NSError *error = nil;
    NSString *result = [AuthCryptoDPoP createProofForURL:nil method:@"GET" key:@{} error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

@end

#pragma mark - Base32Utils Tests

@interface Base32UtilsTests : XCTestCase
@end

@implementation Base32UtilsTests

- (void)testEncodeEmptyData {
    NSString *result = [Base32Utils base32StringFromData:[NSData data]];
    XCTAssertEqualObjects(result, @"");
}

- (void)testEncodeNilData {
    NSString *result = [Base32Utils base32StringFromData:nil];
    XCTAssertEqualObjects(result, @"");
}

- (void)testEncodeSingleByte {
    NSData *data = [NSData dataWithBytes:(uint8_t[]){0x48} length:1];
    NSString *result = [Base32Utils base32StringFromData:data];
    XCTAssertEqualObjects(result, @"JA======");
}

- (void)testEncodeHelloWorld {
    NSData *data = [@"Hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *result = [Base32Utils base32StringFromData:data];
    XCTAssertTrue([result hasPrefix:@"JBSWY3DP"]);
}

- (void)testDecodeNil {
    NSData *result = [Base32Utils dataFromBase32String:nil];
    XCTAssertNil(result);
}

- (void)testDecodeEmptyString {
    NSData *result = [Base32Utils dataFromBase32String:@""];
    XCTAssertNotNil(result);
    XCTAssertEqual(result.length, (NSUInteger)0);
}

- (void)testDecodeInvalidCharacter {
    NSData *result = [Base32Utils dataFromBase32String:@"019!@#"];
    XCTAssertNil(result);
}

- (void)testRoundTrip {
    for (NSUInteger len = 1; len < 32; len++) {
        NSMutableData *data = [NSMutableData dataWithLength:len];
        arc4random_buf(data.mutableBytes, len);
        NSString *encoded = [Base32Utils base32StringFromData:data];
        NSData *decoded = [Base32Utils dataFromBase32String:encoded];
        XCTAssertEqualObjects(decoded, data, @"Round-trip failed for %lu bytes", (unsigned long)len);
    }
}

- (void)testDecodeLowercase {
    NSData *result = [Base32Utils dataFromBase32String:@"jbswy3dp"];
    XCTAssertNotNil(result);
    NSData *upperResult = [Base32Utils dataFromBase32String:@"JBSWY3DP"];
    XCTAssertNotNil(upperResult);
    XCTAssertEqualObjects(result, upperResult);
}

- (void)testDecodeWithPadding {
    NSData *result = [Base32Utils dataFromBase32String:@"JA======"];
    XCTAssertNotNil(result);
    XCTAssertEqual(result.length, (NSUInteger)1);
    const uint8_t *bytes = result.bytes;
    XCTAssertEqual(bytes[0], 0x48);
}

- (void)testDecodeWithoutPadding {
    NSData *result = [Base32Utils dataFromBase32String:@"JA"];
    XCTAssertNotNil(result);
    XCTAssertEqual(result.length, (NSUInteger)1);
    const uint8_t *bytes = result.bytes;
    XCTAssertEqual(bytes[0], 0x48);
}

- (void)testEncodeKnownValue {
    NSData *f = [NSData dataWithBytes:(uint8_t[]){0x66} length:1];
    NSString *fEncoded = [Base32Utils base32StringFromData:f];
    XCTAssertEqualObjects(fEncoded, @"MY======");

    NSData *fo = [NSData dataWithBytes:(uint8_t[]){0x66, 0x6f} length:2];
    NSString *foEncoded = [Base32Utils base32StringFromData:fo];
    XCTAssertEqualObjects(foEncoded, @"MZXQ====");

    NSData *foo = [NSData dataWithBytes:(uint8_t[]){0x66, 0x6f, 0x6f} length:3];
    NSString *fooEncoded = [Base32Utils base32StringFromData:foo];
    XCTAssertEqualObjects(fooEncoded, @"MZXW6===");

    NSData *foob = [NSData dataWithBytes:(uint8_t[]){0x66, 0x6f, 0x6f, 0x62} length:4];
    NSString *foobEncoded = [Base32Utils base32StringFromData:foob];
    XCTAssertEqualObjects(foobEncoded, @"MZXW6YQ=");

    NSData *fooba = [NSData dataWithBytes:(uint8_t[]){0x66, 0x6f, 0x6f, 0x62, 0x61} length:5];
    NSString *foobaEncoded = [Base32Utils base32StringFromData:fooba];
    XCTAssertEqualObjects(foobaEncoded, @"MZXW6YTB");
}

@end
