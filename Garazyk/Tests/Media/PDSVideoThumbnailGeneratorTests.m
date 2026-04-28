#import <XCTest/XCTest.h>
#import "Media/PDSVideoThumbnailGenerator.h"
#import "Blob/PDSBlobProvider.h"
#import "Core/CID.h"

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

@end

@interface PDSVideoThumbnailGeneratorTests : XCTestCase
@property (nonatomic, strong) PDSVideoThumbnailGenerator *generator;
@property (nonatomic, strong) MockBlobProvider *blobProvider;
@end

@implementation PDSVideoThumbnailGeneratorTests

- (void)setUp {
    [super setUp];
    self.generator = [[PDSVideoThumbnailGenerator alloc] init];
    self.blobProvider = [[MockBlobProvider alloc] init];
}

- (void)tearDown {
    self.generator = nil;
    self.blobProvider = nil;
    [super tearDown];
}

#pragma mark - Error Domain

- (void)testErrorDomain {
    XCTAssertEqualObjects(PDSVideoThumbnailErrorDomain, @"com.atproto.pds.video.thumbnail");
}

#pragma mark - Singleton

- (void)testSharedGeneratorIsSingleton {
    PDSVideoThumbnailGenerator *a = [PDSVideoThumbnailGenerator sharedGenerator];
    PDSVideoThumbnailGenerator *b = [PDSVideoThumbnailGenerator sharedGenerator];
    XCTAssertEqual(a, b);
}

#pragma mark - Blob Storage

- (void)testStoreThumbnailWithoutBlobProvider {
    NSError *error = nil;
    CID *result = [self.generator storeThumbnailData:[NSData data] forJob:@"job-1" error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSVideoThumbnailErrorWriteFailed);
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
    CGSize size = CGSizeMake(1, 1);
    UIGraphicsBeginImageContext(size);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor blackColor].CGColor);
    CGContextFillRect(ctx, CGRectMake(0, 0, 1, 1));
    CGImageRef imageRef = CGBitmapContextCreateImage(ctx);
    UIGraphicsEndImageContext();

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
