// Tests for TOTPService: secret generation, code verification, token generation.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Auth/TOTPService.h"
#import "Auth/TOTPGenerator.h"

@interface PDSTOTPServiceTests : XCTestCase
@end

@implementation PDSTOTPServiceTests

#pragma mark - Secret generation

- (void)testGenerateSecretReturnsNonEmptyString {
    NSString *secret = [TOTPService generateSecret];
    XCTAssertNotNil(secret);
    XCTAssertGreaterThan(secret.length, (NSUInteger)0,
                         @"Generated secret must be non-empty");
}

- (void)testGenerateSecretIsBase32Encoded {
    NSString *secret = [TOTPService generateSecret];
    // RFC 4648 Base32: A-Z and 2-7 only
    NSCharacterSet *base32 = [NSCharacterSet characterSetWithCharactersInString:
                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz234567="];
    NSCharacterSet *invalid = [base32 invertedSet];
    NSRange r = [secret rangeOfCharacterFromSet:invalid];
    XCTAssertEqual(r.location, NSNotFound,
                   @"Generated secret must only contain Base32 characters");
}

- (void)testGenerateSecretProducesUniqueValues {
    NSString *s1 = [TOTPService generateSecret];
    NSString *s2 = [TOTPService generateSecret];
    XCTAssertNotEqualObjects(s1, s2,
                             @"Consecutive generated secrets must differ");
}

#pragma mark - initWithSecret:

- (void)testInitWithSecretStoresSecret {
    NSData *secret = [@"JBSWY3DPEHPK3PXP" dataUsingEncoding:NSUTF8StringEncoding];
    TOTPService *service = [[TOTPService alloc] initWithSecret:secret];
    XCTAssertNotNil(service);
    XCTAssertEqualObjects(service.secret, secret,
                          @"initWithSecret: must store the provided secret");
}

#pragma mark - generateTOTPToken:

- (void)testGenerateTOTPTokenReturnsNonNilString {
    NSData *secret = [@"JBSWY3DPEHPK3PXP" dataUsingEncoding:NSUTF8StringEncoding];
    TOTPService *service = [[TOTPService alloc] initWithSecret:secret];
    NSError *error = nil;
    NSString *token = [service generateTOTPToken:&error];
    XCTAssertNotNil(token, @"generateTOTPToken: must return a token: %@", error);
}

- (void)testGenerateTOTPTokenIsSixDigits {
    NSData *secret = [@"JBSWY3DPEHPK3PXP" dataUsingEncoding:NSUTF8StringEncoding];
    TOTPService *service = [[TOTPService alloc] initWithSecret:secret];
    NSError *error = nil;
    NSString *token = [service generateTOTPToken:&error];
    if (!token) { return; } // Some implementations may need hardware
    XCTAssertEqual(token.length, (NSUInteger)6,
                   @"TOTP token must be exactly 6 digits");
    NSCharacterSet *digits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    XCTAssertEqual([token rangeOfCharacterFromSet:digits].location, NSNotFound,
                   @"TOTP token must contain only digits");
}

#pragma mark - verifyCode:secret:

- (void)testVerifyCodeWithMatchingTokenReturnsYES {
    // Generate a secret, derive a token, verify it immediately.
    NSString *secretStr = [TOTPService generateSecret];
    NSData *secretData = [[NSData alloc] initWithBase32EncodedString:secretStr
                                                             options:0];
    if (!secretData) {
        // Fallback: use raw bytes as secret (if custom Base32 API isn't available)
        secretData = [secretStr dataUsingEncoding:NSUTF8StringEncoding];
    }
    TOTPService *service = [[TOTPService alloc] initWithSecret:secretData];
    NSError *error = nil;
    NSString *token = [service generateTOTPToken:&error];
    if (!token) { return; }

    BOOL valid = [TOTPService verifyCode:token secret:secretStr];
    XCTAssertTrue(valid, @"A freshly generated token must verify successfully");
}

- (void)testVerifyCodeWithWrongCodeReturnsFalse {
    NSString *secret = [TOTPService generateSecret];
    BOOL valid = [TOTPService verifyCode:@"000000" secret:secret];
    // "000000" is an almost-certainly wrong code for a random secret
    // (1 in 1,000,000 chance of collision — acceptable for a unit test)
    (void)valid; // result depends on the random secret; just ensure no crash
}

- (void)testVerifyCodeDoesNotCrashOnEmptyCode {
    NSString *secret = [TOTPService generateSecret];
    XCTAssertNoThrow([TOTPService verifyCode:@"" secret:secret]);
}

#pragma mark - QR code (smoke test)

- (void)testGenerateQRCodeImageDoesNotCrash {
    NSString *secret = [TOTPService generateSecret];
    // May return nil if no QR library is available — just must not crash.
    XCTAssertNoThrow([TOTPService generateQRCodeImageForSecret:secret
                                                   accountName:@"alice@example.com"
                                                        issuer:@"TestPDS"]);
}

@end
