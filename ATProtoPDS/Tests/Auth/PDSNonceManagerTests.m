// Tests for PDSNonceManager: nonce generation, one-time use, expiry.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Auth/PDSNonceManager.h"

@interface PDSNonceManagerTests : XCTestCase
@end

@implementation PDSNonceManagerTests

#pragma mark - Singleton

- (void)testSharedManagerIsSingleton {
    PDSNonceManager *a = [PDSNonceManager sharedManager];
    PDSNonceManager *b = [PDSNonceManager sharedManager];
    XCTAssertEqual(a, b, @"sharedManager must return the same instance");
}

#pragma mark - Generation

- (void)testGenerateNonceReturnsNonEmptyString {
    NSString *nonce = [[PDSNonceManager sharedManager] generateNonce];
    XCTAssertNotNil(nonce);
    XCTAssertGreaterThan(nonce.length, (NSUInteger)0,
                         @"Generated nonce must be non-empty");
}

- (void)testGenerateNonceProducesUniqueValues {
    PDSNonceManager *mgr = [PDSNonceManager sharedManager];
    NSString *n1 = [mgr generateNonce];
    NSString *n2 = [mgr generateNonce];
    XCTAssertNotEqualObjects(n1, n2, @"Consecutive nonces must differ");
}

#pragma mark - Validation (one-time use)

- (void)testNonceIsValidOnFirstUse {
    PDSNonceManager *mgr = [PDSNonceManager sharedManager];
    NSString *nonce = [mgr generateNonce];
    BOOL valid = [mgr validateNonce:nonce];
    XCTAssertTrue(valid, @"A freshly generated nonce must be valid on first use");
}

- (void)testNonceIsRejectedOnReuse {
    PDSNonceManager *mgr = [PDSNonceManager sharedManager];
    NSString *nonce = [mgr generateNonce];
    [mgr validateNonce:nonce];                    // consume it
    BOOL reuse = [mgr validateNonce:nonce];
    XCTAssertFalse(reuse, @"A consumed nonce must be rejected on reuse");
}

- (void)testUngeneratedNonceIsRejected {
    BOOL valid = [[PDSNonceManager sharedManager] validateNonce:@"not-a-real-nonce-xyz"];
    XCTAssertFalse(valid, @"An arbitrary string must not pass nonce validation");
}

- (void)testEmptyNonceIsRejected {
    BOOL valid = [[PDSNonceManager sharedManager] validateNonce:@""];
    XCTAssertFalse(valid, @"Empty string must not pass nonce validation");
}

@end
