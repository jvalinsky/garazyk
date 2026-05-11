// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/VideoThumbnailGenerator.h"
#import "Blob/PDSBlobProvider.h"
#import "Core/CID.h"
#import <CoreGraphics/CoreGraphics.h>

@interface ATProtoVideoThumbnailGenerator (ATProtoVideoThumbnailGeneratorTests)
- (nullable NSData *)jpegDataFromCGImage:(CGImageRef)image compression:(float)quality;
@end

/// In-memory blob provider for unit testing.
@interface MockBlobProvider : NSObject <PDSBlobProvider>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *blobs;
@end

@implementation MockBlobProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        _blobs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)storeBlobData:(NSData *)data forCID:(CID *)cid error:(NSError **)error {
    self.blobs[cid.stringValue] = data;
    return YES;
}

- (nullable NSData *)retrieveBlobDataForCID:(CID *)cid error:(NSError **)error {
    NSData *data = self.blobs[cid.stringValue];
    if (!data && error) {
        *error = [NSError errorWithDomain:@"MockBlobProvider"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Blob not found"}];
    }
    return data;
}

- (BOOL)deleteBlobDataForCID:(CID *)cid error:(NSError **)error {
    [self.blobs removeObjectForKey:cid.stringValue];
    return YES;
}

- (BOOL)hasBlobDataForCID:(CID *)cid {
    return self.blobs[cid.stringValue] != nil;
}

@end

@interface ATProtoVideoThumbnailGeneratorTests : XCTestCase
@property (nonatomic, strong) ATProtoVideoThumbnailGenerator *generator;
@property (nonatomic, strong) MockBlobProvider *blobProvider;
@end

@implementation ATProtoVideoThumbnailGeneratorTests

- (void)setUp {
    [super setUp];
    self.generator = [[ATProtoVideoThumbnailGenerator alloc] init];
    self.blobProvider = [[MockBlobProvider alloc] init];
}

- (void)tearDown {
    self.generator = nil;
    self.blobProvider = nil;
    [super tearDown];
}

#pragma mark - Error Domain

- (void)testErrorDomain {
    XCTAssertEqualObjects(ATProtoVideoThumbnailErrorDomain, @"com.atproto.video.thumbnail");
}

#pragma mark - Singleton

- (void)testSharedGeneratorIsSingleton {
    ATProtoVideoThumbnailGenerator *a = [ATProtoVideoThumbnailGenerator sharedGenerator];
    ATProtoVideoThumbnailGenerator *b = [ATProtoVideoThumbnailGenerator sharedGenerator];
    XCTAssertEqual(a, b);
}

#pragma mark - Blob Storage

- (void)testStoreThumbnailWithoutBlobProvider {
    NSError *error = nil;
    CID *result = [self.generator storeThumbnailData:[NSData data] forJob:@"job-1" error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoVideoThumbnailErrorWriteFailed);
}

- (void)testStoreThumbnailWithBlobProvider {
    self.generator.blobProvider = self.blobProvider;

    NSData *thumbnailData = [@"fake-jpeg-data" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    CID *result = [self.generator storeThumbnailData:thumbnailData forJob:@"job-2" error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);

    // Verify the blob was stored
    NSData *stored = self.blobProvider.blobs[result.stringValue];
    XCTAssertNotNil(stored);
    XCTAssertEqualObjects(stored, thumbnailData);
}

#pragma mark - JPEG Encoding

- (void)testJpegDataFromCGImage {
    // Create a 1x1 pixel CGImage
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL,
                                             1,
                                             1,
                                             8,
                                             4,
                                             colorSpace,
                                             (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    XCTAssertNotEqual(ctx, NULL);
    CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, 1, 1));
    CGImageRef imageRef = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    CGColorSpaceRelease(colorSpace);
    XCTAssertNotEqual(imageRef, NULL);

    NSData *jpegData = [self.generator jpegDataFromCGImage:imageRef compression:0.8];
    CGImageRelease(imageRef);

    XCTAssertNotNil(jpegData);
    XCTAssertTrue(jpegData.length > 0);

    // Verify it's valid JPEG (starts with FF D8)
    const uint8_t *bytes = (const uint8_t *)jpegData.bytes;
    XCTAssertEqual(bytes[0], 0xFF);
    XCTAssertEqual(bytes[1], 0xD8);
}

@end
