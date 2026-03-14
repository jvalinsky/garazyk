// Tests for PKCEUtil: RFC 7636 PKCE code verifier and S256 code challenge generation.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Auth/PKCEUtil.h"
#import "Auth/CryptoUtils.h"
#import <CommonCrypto/CommonDigest.h>

@interface PKCEUtilTests : XCTestCase
@end

@implementation PKCEUtilTests

#pragma mark - Code Verifier

- (void)testCodeVerifierLengthIsInRange {
    NSString *verifier = [PKCEUtil generateCodeVerifier];
    XCTAssertNotNil(verifier);
    XCTAssertGreaterThanOrEqual(verifier.length, (NSUInteger)43, @"Verifier must be at least 43 chars");
    XCTAssertLessThanOrEqual(verifier.length, (NSUInteger)128, @"Verifier must be at most 128 chars");
}

- (void)testCodeVerifierIsURLSafe {
    // RFC 7636 §4.1: unreserved characters [A-Z] [a-z] [0-9] '-' '.' '_' '~'
    NSString *verifier = [PKCEUtil generateCodeVerifier];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSCharacterSet *disallowed = [allowed invertedSet];
    NSRange bad = [verifier rangeOfCharacterFromSet:disallowed];
    XCTAssertEqual(bad.location, NSNotFound,
                   @"Verifier must only contain URL-safe unreserved characters, got: %@", verifier);
}

- (void)testCodeVerifierIsUnique {
    NSString *v1 = [PKCEUtil generateCodeVerifier];
    NSString *v2 = [PKCEUtil generateCodeVerifier];
    XCTAssertNotEqualObjects(v1, v2, @"Consecutive verifiers must differ");
}

#pragma mark - Code Challenge (S256)

- (void)testCodeChallengeMatchesSHA256OfVerifier {
    // RFC 7636 §4.2: code_challenge = BASE64URL(SHA256(ASCII(code_verifier)))
    NSString *verifier = @"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
    NSString *challenge = [PKCEUtil generateCodeChallengeWithVerifier:verifier];

    NSData *verifierData = [verifier dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hashBytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(verifierData.bytes, (CC_LONG)verifierData.length, hashBytes);
    NSData *hashData = [NSData dataWithBytes:hashBytes length:CC_SHA256_DIGEST_LENGTH];
    NSString *expectedChallenge = [CryptoUtils base64URLEncode:hashData];

    XCTAssertEqualObjects(challenge, expectedChallenge,
                          @"S256 challenge must equal base64url(SHA-256(verifier))");
}

- (void)testCodeChallengeDiffersFromVerifier {
    NSString *verifier = [PKCEUtil generateCodeVerifier];
    NSString *challenge = [PKCEUtil generateCodeChallengeWithVerifier:verifier];
    XCTAssertNotEqualObjects(challenge, verifier);
}

#pragma mark - Verification

- (void)testVerifyCodeChallengeSucceedsForMatchingPair {
    NSString *verifier = [PKCEUtil generateCodeVerifier];
    NSString *challenge = [PKCEUtil generateCodeChallengeWithVerifier:verifier];
    BOOL ok = [PKCEUtil verifyCodeChallenge:challenge withVerifier:verifier];
    XCTAssertTrue(ok, @"verifyCodeChallenge:withVerifier: must succeed for matching pair");
}

- (void)testVerifyCodeChallengeFailsForWrongVerifier {
    NSString *verifier1 = [PKCEUtil generateCodeVerifier];
    NSString *verifier2 = [PKCEUtil generateCodeVerifier];
    NSString *challenge = [PKCEUtil generateCodeChallengeWithVerifier:verifier1];
    BOOL ok = [PKCEUtil verifyCodeChallenge:challenge withVerifier:verifier2];
    XCTAssertFalse(ok, @"Verification must fail when verifier does not match challenge");
}

@end
