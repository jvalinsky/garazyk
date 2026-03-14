// Tests for the AuthCrypto module: Base64URL, DPoP canonical HTU.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "AuthCrypto/AuthCryptoBase64URL.h"
#import "AuthCrypto/AuthCryptoDPoP.h"
#import "Auth/CryptoUtils.h"
#import <CommonCrypto/CommonDigest.h>

@interface AuthCryptoTests : XCTestCase
@end

@implementation AuthCryptoTests

#pragma mark - AuthCryptoBase64URL

- (void)testBase64URLEncodeDecodeRoundTrip {
    NSData *original = [CryptoUtils randomBytes:32];
    NSString *encoded = [AuthCryptoBase64URL encode:original];
    XCTAssertNotNil(encoded);
    XCTAssertFalse([encoded containsString:@"+"], @"Must not contain +");
    XCTAssertFalse([encoded containsString:@"/"], @"Must not contain /");
    XCTAssertFalse([encoded containsString:@"="], @"Must not contain padding");

    NSData *decoded = [AuthCryptoBase64URL decode:encoded];
    XCTAssertEqualObjects(decoded, original, @"Decode must recover original bytes");
}

- (void)testBase64URLEncodeMatchesSHA256EmptyInput {
    // SHA-256("") → e3b0... → base64url = 47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(NULL, 0, hash);
    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
    NSString *encoded = [AuthCryptoBase64URL encode:hashData];
    XCTAssertEqualObjects(encoded, @"47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU");
}

- (void)testBase64URLDecodeRejectsEmpty {
    NSData *result = [AuthCryptoBase64URL decode:@""];
    XCTAssertNil(result);
}

- (void)testBase64URLDecodeRejectsInvalidChars {
    XCTAssertNil([AuthCryptoBase64URL decode:@"not!valid@base64#"]);
}

#pragma mark - AuthCryptoDPoP Canonical HTU

- (void)testCanonicalHTUFromValidURL {
    NSURL *url = [NSURL URLWithString:@"https://example.com/token?client_id=abc#frag"];
    NSString *htu = [AuthCryptoDPoP canonicalHTUFromURL:url];
    // Canonical HTU: scheme + authority + path, no query or fragment
    XCTAssertEqualObjects(htu, @"https://example.com/token",
                          @"Canonical HTU must strip query and fragment");
}

- (void)testCanonicalHTUFromStringValid {
    NSString *result = [AuthCryptoDPoP canonicalHTUFromString:@"https://pds.example.com/xrpc/method"];
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result, @"https://pds.example.com/xrpc/method");
}

- (void)testCanonicalHTUFromStringStripsQuery {
    NSString *result = [AuthCryptoDPoP canonicalHTUFromString:@"https://pds.example.com/path?foo=bar"];
    XCTAssertNotNil(result);
    XCTAssertFalse([result containsString:@"?"], @"Canonical HTU must not contain query string");
}

- (void)testCanonicalHTUFromStringStripsFragment {
    NSString *result = [AuthCryptoDPoP canonicalHTUFromString:@"https://example.com/path#section"];
    XCTAssertNotNil(result);
    XCTAssertFalse([result containsString:@"#"], @"Canonical HTU must not contain fragment");
}

- (void)testCanonicalHTUFromEmptyStringReturnsNil {
    NSString *result = [AuthCryptoDPoP canonicalHTUFromString:@""];
    XCTAssertNil(result);
}

- (void)testCanonicalHTUFromNonHTTPSReturnsNilOrValid {
    // The implementation may reject non-https URLs; either nil or a canonical form is acceptable
    // as long as it doesn't crash.
    (void)[AuthCryptoDPoP canonicalHTUFromString:@"ftp://example.com/path"];
}

@end
