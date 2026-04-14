#import <XCTest/XCTest.h>
#import "Auth/PKCEUtil.h"

@interface OAuthPKCETests : XCTestCase
@end

@implementation OAuthPKCETests

- (void)testPKCES256Challenge {
    // RFC 7636 Appendix B Example
    NSString *verifier = @"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
    NSString *expectedChallenge = @"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";
    
    NSString *challenge = [PKCEUtil generateCodeChallengeWithVerifier:verifier];
    
    XCTAssertEqualObjects(challenge, expectedChallenge, @"S256 challenge generation should match RFC example");
}

- (void)testPKCEVerifierMinLength {
    // 43 chars is min
    NSString *verifier = [PKCEUtil generateCodeVerifier];
    XCTAssertGreaterThanOrEqual(verifier.length, 43, @"Verifier must be at least 43 chars");
}

- (void)testPKCEVerifierMaxLength {
    // 128 chars is max per spec, though generateCodeVerifier produces fixed length usually.
    // Our generator produces 32 bytes encoded -> 43 chars.
    NSString *verifier = [PKCEUtil generateCodeVerifier];
    XCTAssertLessThanOrEqual(verifier.length, 128, @"Verifier must be at most 128 chars");
}

- (void)testPKCEVerifierMismatch {
    NSString *verifier = [PKCEUtil generateCodeVerifier];
    NSString *challenge = [PKCEUtil generateCodeChallengeWithVerifier:verifier];
    
    NSString *wrongVerifier = [PKCEUtil generateCodeVerifier];
    
    XCTAssertFalse([PKCEUtil verifyCodeChallenge:challenge withVerifier:wrongVerifier], @"Mismatching verifier should fail");
    XCTAssertTrue([PKCEUtil verifyCodeChallenge:challenge withVerifier:verifier], @"Matching verifier should pass");
}

- (void)testRandomness {
    NSString *v1 = [PKCEUtil generateCodeVerifier];
    NSString *v2 = [PKCEUtil generateCodeVerifier];
    XCTAssertNotEqualObjects(v1, v2, @"Verifiers should be random");
}

@end
