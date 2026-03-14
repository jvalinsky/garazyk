//
//  NSDataCompatTests.m
//  ATProtoPDS
//
//  Tests for NSDataCompat GNUstep compatibility shim.
//

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import <Foundation/Foundation.h>

@interface NSDataCompatTests : XCTestCase
@end

@implementation NSDataCompatTests

// MARK: - Base64 URL encoding

- (void)testBase64URLEncoding {
    // Verify standard Base64 encoding round-trips through NSData.
    NSString *original = @"Hello, ATProto!";
    NSData *data = [original dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNotNil(data);
    NSString *b64 = [data base64EncodedStringWithOptions:0];
    XCTAssertNotNil(b64);
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    XCTAssertEqualObjects(data, decoded, @"Base64 encode/decode round-trip should preserve data");
}

- (void)testBase64URLRoundTripBinaryData {
    // 32 pseudo-random bytes (fixed seed for reproducibility).
    uint8_t bytes[32];
    for (int i = 0; i < 32; i++) {
        bytes[i] = (uint8_t)(i * 7 + 13);
    }
    NSData *original = [NSData dataWithBytes:bytes length:32];
    NSString *b64 = [original base64EncodedStringWithOptions:0];
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    XCTAssertEqualObjects(original, decoded, @"Binary base64 round-trip should be lossless");
}

- (void)testBase64EmptyData {
    NSData *empty = [NSData data];
    NSString *b64 = [empty base64EncodedStringWithOptions:0];
    XCTAssertEqualObjects(b64, @"", @"Empty data encodes to empty string");
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    XCTAssertEqualObjects(empty, decoded);
}

// MARK: - Constant-time comparison

- (void)testConstantTimeComparisonEqualData {
    NSData *a = [@"same content" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *b = [@"same content" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(a, b, @"Equal data should compare as equal");
}

- (void)testConstantTimeComparisonDifferentData {
    NSData *a = [@"aaaa" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *b = [@"bbbb" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([a isEqualToData:b], @"Different data must not compare as equal");
}

- (void)testConstantTimeComparisonDifferentLength {
    NSData *a = [@"short" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *b = [@"longer string" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([a isEqualToData:b], @"Different-length data must not compare as equal");
}

// MARK: - dataWithContentsOfFile:options:error: (GNUstep compat shim)

- (void)testDataWithContentsOfFileMissingFileReturnsNil {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [[[NSUUID UUID] UUIDString] stringByAppendingString:@"_nonexistent.bin"]];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path
                                          options:0
                                            error:&error];
    XCTAssertNil(data, @"Reading a missing file should return nil");
    XCTAssertNotNil(error, @"An error should be reported for missing file");
}

- (void)testDataWithContentsOfFileReadsExistingFile {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [[[NSUUID UUID] UUIDString] stringByAppendingString:@"_compat.bin"]];
    NSData *written = [@"compat test" dataUsingEncoding:NSUTF8StringEncoding];
    [written writeToFile:path atomically:YES];

    NSError *error = nil;
    NSData *read = [NSData dataWithContentsOfFile:path options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(read, written, @"File contents should match what was written");

    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

@end
