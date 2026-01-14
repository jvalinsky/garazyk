#import <XCTest/XCTest.h>
#import "Repository/CBOR.h"

@interface CBORSecurityTests : XCTestCase
@end

@implementation CBORSecurityTests

- (void)testDeeplyNestedArrays {
    // Generate a deeply nested array: [[[[...]]]]
    // This tests for stack overflow in recursive decoders
    NSMutableData *data = [NSMutableData data];
    int depth = 10000; // Deep enough to blow stack if unchecked
    
    // Write 10000 array headers [0x81, 0x81, ...]
    for (int i = 0; i < depth; i++) {
        uint8_t header = 0x81; // Array of length 1
        [data appendBytes:&header length:1];
    }
    
    // Write the innermost value (integer 1)
    uint8_t value = 0x01;
    [data appendBytes:&value length:1];
    
    // We expect this to fail gracefully or return nil, but NOT crash
    // Ideally the decoder should have a depth limit
    @try {
        CBORValue *decoded = [CBORDecoder decode:data];
        // If it returns a value, it handled it (or the depth wasn't enough to crash)
        // If it returns nil, it rejected it.
        // The success condition here is "did not crash"
        XCTAssertTrue(YES, @"Survived deep nesting");
    } @catch (NSException *exception) {
        // If it throws an exception (e.g. stack overflow caught if possible, though unlikely), that's a failure of robustness but handled
         XCTFail(@"Caught exception: %@", exception);
    }
}

- (void)testDeeplyNestedMaps {
    // Generate deeply nested maps: {"a": {"a": ...}}
    NSMutableData *data = [NSMutableData data];
    int depth = 10000;
    
    for (int i = 0; i < depth; i++) {
        uint8_t header = 0xA1; // Map of length 1
        [data appendBytes:&header length:1];
        
        // Key "a"
        uint8_t keyHeader = 0x61; // String length 1
        char key = 'a';
        [data appendBytes:&keyHeader length:1];
        [data appendBytes:&key length:1];
    }
    
    uint8_t value = 0x01;
    [data appendBytes:&value length:1];
    
    @try {
        [CBORDecoder decode:data];
        XCTAssertTrue(YES, @"Survived deep map nesting");
    } @catch (NSException *exception) {
         XCTFail(@"Caught exception: %@", exception);
    }
}

- (void)testLargeArrayAllocation {
    // Test for "zip bomb" / OOM attack
    // Array with 0xFFFFFFFF elements (approx 4 billion)
    // 0x9B is Array(8-byte length)
    NSMutableData *data = [NSMutableData data];
    uint8_t header = 0x9B;
    [data appendBytes:&header length:1];
    uint64_t count = OSSwapHostToBigInt64(UINT32_MAX); // Just under 4GB elements
    [data appendBytes:&count length:8];
    
    // Payload is empty, so it should fail to read immediately,
    // BUT if it tries to allocate memory for UINT32_MAX * pointer_size first, it will crash/OOM.
    
    NSDate *start = [NSDate date];
    CBORValue *decoded = [CBORDecoder decode:data];
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];
    
    XCTAssertNil(decoded, @"Should fail to decode incomplete data");
    XCTAssertLessThan(duration, 1.0, @"Should fail fast and not hang allocating memory");
}

- (void)testLargeMapAllocation {
    // Similar to array, but for maps
    NSMutableData *data = [NSMutableData data];
    uint8_t header = 0xBB; // Map(8-byte length)
    [data appendBytes:&header length:1];
    uint64_t count = OSSwapHostToBigInt64(UINT32_MAX);
    [data appendBytes:&count length:8];
    
    NSDate *start = [NSDate date];
    CBORValue *decoded = [CBORDecoder decode:data];
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];
    
    XCTAssertNil(decoded, @"Should fail to decode incomplete data");
    XCTAssertLessThan(duration, 1.0, @"Should fail fast");
}

- (void)testBufferOverread {
    // Declare a string of length 100, provide only 1 byte
    NSMutableData *data = [NSMutableData data];
    uint8_t header = 0x78; // String(1-byte length follows)
    [data appendBytes:&header length:1];
    uint8_t length = 100;
    [data appendBytes:&length length:1];
    
    uint8_t junk = 0x41;
    [data appendBytes:&junk length:1]; // Only 1 byte provided
    
    CBORValue *decoded = [CBORDecoder decode:data];
    XCTAssertNil(decoded, @"Should return nil when data is truncated");
}

@end
