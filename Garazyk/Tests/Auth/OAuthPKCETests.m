// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/PKCEUtil.h"

@interface OAuthPKCETests : XCTestCase
@end

@implementation OAuthPKCETests

- (void)testPKCES256Challenge {
    // RFC 7636 Appendix B Example
    NSString *verifier = @"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
    NSString *expectedChallenge = @"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";
    
    NSString *challenge = [ATProtoPKCEUtil generateCodeChallengeWithVerifier:verifier];
    
    XCTAssertEqualObjects(challenge, expectedChallenge, @"S256 challenge generation should match RFC example");
}

- (void)testPKCEVerifierMinLength {
    // 43 chars is min
    NSString *verifier = [ATProtoPKCEUtil generateCodeVerifier];
    XCTAssertGreaterThanOrEqual(verifier.length, 43, @"Verifier must be at least 43 chars");
}

- (void)testPKCEVerifierMaxLength {
    // 128 chars is max per spec, though generateCodeVerifier produces fixed length usually.
    // Our generator produces 32 bytes encoded -> 43 chars.
    NSString *verifier = [ATProtoPKCEUtil generateCodeVerifier];
    XCTAssertLessThanOrEqual(verifier.length, 128, @"Verifier must be at most 128 chars");
}

- (void)testPKCEVerifierMismatch {
    NSString *verifier = [ATProtoPKCEUtil generateCodeVerifier];
    NSString *challenge = [ATProtoPKCEUtil generateCodeChallengeWithVerifier:verifier];
    
    NSString *wrongVerifier = [ATProtoPKCEUtil generateCodeVerifier];
    
    XCTAssertFalse([ATProtoPKCEUtil verifyCodeChallenge:challenge withVerifier:wrongVerifier], @"Mismatching verifier should fail");
    XCTAssertTrue([ATProtoPKCEUtil verifyCodeChallenge:challenge withVerifier:verifier], @"Matching verifier should pass");
}

- (void)testRandomness {
    NSString *v1 = [ATProtoPKCEUtil generateCodeVerifier];
    NSString *v2 = [ATProtoPKCEUtil generateCodeVerifier];
    XCTAssertNotEqualObjects(v1, v2, @"Verifiers should be random");
}

@end
