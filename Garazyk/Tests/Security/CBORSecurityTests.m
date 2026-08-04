// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Core/CBOR.h"

@interface CBORSecurityTests : XCTestCase
@end

@implementation CBORSecurityTests

- (void)testDeeplyNestedArraysDoesNotCrash {
    // Generate a deeply nested array: [[[[...]]]]
    // This tests for stack overflow in recursive decoders.
    // §1.2: kCBORMaxDecodeDepth = 64 caps nesting; decoder returns nil
    // rather than recursing until stack exhaustion.
    NSMutableData *data = [NSMutableData data];
    int depth = 10000; // Far above the 64-level cap.
    
    // Write 10000 array headers [0x81, 0x81, ...]
    for (int i = 0; i < depth; i++) {
        uint8_t header = 0x81; // Array of length 1
        [data appendBytes:&header length:1];
    }
    
    // Write the innermost value (integer 1)
    uint8_t value = 0x01;
    [data appendBytes:&value length:1];
    
    @try {
        ATProtoCBORValue *decoded = [ATProtoCBORDecoder decode:data];
        XCTAssertNil(decoded,
                     @"Deeply nested CBOR input (depth=%d) must be rejected by "
                     @"the depth cap (kCBORMaxDecodeDepth=64).", depth);
    } @catch (NSException *exception) {
        XCTFail(@"Caught exception: %@", exception);
    }
}

- (void)testDeeplyNestedMaps {
    // Generate deeply nested maps: {"a": {"a": ...}}
    // §1.2: same depth cap applies; must return nil, not crash.
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
        ATProtoCBORValue *decoded = [ATProtoCBORDecoder decode:data];
        XCTAssertNil(decoded,
                     @"Deeply nested CBOR map (depth=%d) must be rejected by "
                     @"the depth cap.", depth);
    } @catch (NSException *exception) {
         XCTFail(@"Caught exception: %@", exception);
    }
}

- (void)testDecodeReturnsNilForLargeArrayAllocation {
    // Test for "zip bomb" / OOM attack
    // Array with 0xFFFFFFFF elements (approx 4 billion)
    // 0x9B is Array(8-byte length)
    NSMutableData *data = [NSMutableData data];
    uint8_t header = 0x9B;
    [data appendBytes:&header length:1];
    uint64_t count = OSSwapHostToBigInt64(UINT32_MAX); // Just under 4GB elements
    [data appendBytes:&count length:8];
    
    // Payload is empty, so it should fail to read immediately,
    // BUT if it tries to allocate memory for UINT32_MAX * pointer_size initially, it will crash/OOM.
    
    NSDate *start = [NSDate date];
    ATProtoCBORValue *decoded = [ATProtoCBORDecoder decode:data];
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];
    
    XCTAssertNil(decoded, @"Should fail to decode incomplete data");
    XCTAssertLessThan(duration, 1.0, @"Should fail fast and not hang allocating memory");
}

- (void)testDecodeReturnsNilForLargeMapAllocation {
    // Similar to array, but for maps
    NSMutableData *data = [NSMutableData data];
    uint8_t header = 0xBB; // Map(8-byte length)
    [data appendBytes:&header length:1];
    uint64_t count = OSSwapHostToBigInt64(UINT32_MAX);
    [data appendBytes:&count length:8];
    
    NSDate *start = [NSDate date];
    ATProtoCBORValue *decoded = [ATProtoCBORDecoder decode:data];
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];
    
    XCTAssertNil(decoded, @"Should fail to decode incomplete data");
    XCTAssertLessThan(duration, 1.0, @"Should fail fast");
}

- (void)testDecodeReturnsNilOnBufferOverread {
    // Declare a string of length 100, provide only 1 byte
    NSMutableData *data = [NSMutableData data];
    uint8_t header = 0x78; // String(1-byte length follows)
    [data appendBytes:&header length:1];
    uint8_t length = 100;
    [data appendBytes:&length length:1];
    
    uint8_t junk = 0x41;
    [data appendBytes:&junk length:1]; // Only 1 byte provided
    
    ATProtoCBORValue *decoded = [ATProtoCBORDecoder decode:data];
    XCTAssertNil(decoded, @"Should return nil when data is truncated");
}

@end
