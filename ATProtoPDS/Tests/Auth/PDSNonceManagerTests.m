#import <XCTest/XCTest.h>
#import "Auth/PDSNonceManager.h"

@interface PDSNonceManagerTests : XCTestCase
@end

@implementation PDSNonceManagerTests

- (void)testSharedManagerReturnsSingleton {
    PDSNonceManager *mgr1 = [PDSNonceManager sharedManager];
    PDSNonceManager *mgr2 = [PDSNonceManager sharedManager];
    
    XCTAssertNotNil(mgr1);
    XCTAssertEqual(mgr1, mgr2, @"Shared manager should return singleton");
}

- (void)testGenerateNonceReturnsValidNonce {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    NSString *nonce = [mgr generateNonce];
    
    XCTAssertNotNil(nonce, @"Generated nonce should not be nil");
    XCTAssertTrue(nonce.length > 0, @"Nonce should have content");
}

- (void)testGenerateNonceLengthIs24BytesBase64 {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    NSString *nonce = [mgr generateNonce];
    
    XCTAssertGreaterThanOrEqual(nonce.length, (NSUInteger)30,
                                @"24 bytes of random data should encode to ~32 characters");
    XCTAssertLessThanOrEqual(nonce.length, (NSUInteger)36,
                            @"24 bytes should fit within URL-safe base64 range");
}

- (void)testGenerateNonceIsURLSafe {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    
    for (int i = 0; i < 10; i++) {
        NSString *nonce = [mgr generateNonce];
        
        XCTAssertFalse([nonce containsString:@"+"],
                       @"Nonce should not contain + (not URL safe)");
        XCTAssertFalse([nonce containsString:@"/"],
                       @"Nonce should not contain / (not URL safe)");
        XCTAssertFalse([nonce containsString:@"="],
                       @"Nonce should not contain padding (not URL safe)");
    }
}

- (void)testGenerateNonceReturnsUniqueValues {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    NSMutableSet *nonces = [NSMutableSet set];
    
    for (int i = 0; i < 100; i++) {
        NSString *nonce = [mgr generateNonce];
        [nonces addObject:nonce];
    }
    
    XCTAssertEqual(nonces.count, 100, @"Each generated nonce should be unique");
}

#pragma mark - Validation

- (void)testValidateNonceValidNonceReturnsTrue {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    NSString *nonce = [mgr generateNonce];
    
    BOOL valid = [mgr validateNonce:nonce];
    
    XCTAssertTrue(valid, @"Just-generated nonce should be valid");
}

- (void)testValidateNonceNonExistentReturnsFalse {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    
    BOOL valid = [mgr validateNonce:@"non_existent_nonce_12345"];
    
    XCTAssertFalse(valid, @"Non-existent nonce should return false");
}

- (void)testValidateNonceNilInputReturnsFalse {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    
    BOOL valid = [mgr validateNonce:nil];
    
    XCTAssertFalse(valid, @"Nil input should return false");
}

- (void)testValidateNonceEmptyStringReturnsFalse {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    
    BOOL valid = [mgr validateNonce:@""];
    
    XCTAssertFalse(valid, @"Empty string should return false");
}

- (void)testValidateNonceReusableUntilExpiry {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    NSString *nonce = [mgr generateNonce];
    
    BOOL valid1 = [mgr validateNonce:nonce];
    XCTAssertTrue(valid1, @"First validation should succeed");
    
    BOOL valid2 = [mgr validateNonce:nonce];
    XCTAssertTrue(valid2, @"Second validation (same nonce) should also succeed");
    
    BOOL valid3 = [mgr validateNonce:nonce];
    XCTAssertTrue(valid3, @"Third validation (same nonce) should also succeed");
}

#pragma mark - Expiration

- (void)testNonceExpiresAfterTTL {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    NSString *nonce = [mgr generateNonce];
    
    XCTAssertTrue([mgr validateNonce:nonce], @"Nonce should be valid immediately");
    
    [NSThread sleepForTimeInterval:0.1];
    
    XCTAssertTrue([mgr validateNonce:nonce], @"Nonce should still be valid after short delay");
}

#pragma mark - Cleanup

- (void)testCleanupRemovesExpiredNonces {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    
    NSString *nonce1 = [mgr generateNonce];
    NSString *nonce2 = [mgr generateNonce];
    
    XCTAssertTrue([mgr validateNonce:nonce1]);
    XCTAssertTrue([mgr validateNonce:nonce2]);
    
    [mgr performSelector:@selector(cleanupNonces)];
    
    XCTAssertTrue([mgr validateNonce:nonce1], @"Valid nonces should remain after cleanup");
    XCTAssertTrue([mgr validateNonce:nonce2], @"Valid nonces should remain after cleanup");
}

#pragma mark - Concurrency

- (void)testConcurrentGenerateAndValidate {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    dispatch_queue_t queue = dispatch_queue_create("test.queue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();
    
    for (int i = 0; i < 50; i++) {
        dispatch_group_async(group, queue, ^{
            NSString *nonce = [mgr generateNonce];
            (void)nonce;
        });
        
        dispatch_group_async(group, queue, ^{
            [mgr validateNonce:@"test_nonexistent"];
        });
    }
    
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}

- (void)testThreadSafetyOfNonceStorage {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    
    dispatch_queue_t queue = dispatch_queue_create("test.queue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();
    __block NSMutableArray *generatedNonces = [NSMutableArray array];
    NSLock *lock = [[NSLock alloc] init];
    
    for (int i = 0; i < 20; i++) {
        dispatch_group_async(group, queue, ^{
            NSString *nonce = [mgr generateNonce];
            [lock lock];
            [generatedNonces addObject:nonce];
            [lock unlock];
        });
    }
    
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    
    [lock lock];
    NSUInteger count = generatedNonces.count;
    [lock unlock];
    
    XCTAssertEqual(count, 20, @"All nonces should be generated successfully");
}

#pragma mark - Stress Test

- (void)testManyNoncesDoNotCauseOverflow {
    PDSNonceManager *mgr = [[PDSNonceManager alloc] init];
    
    for (int i = 0; i < 1000; i++) {
        NSString *nonce = [mgr generateNonce];
        XCTAssertNotNil(nonce, @"Nonce %d should be generated", i);
    }
}

@end
