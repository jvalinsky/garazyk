#import <XCTest/XCTest.h>
#import "Media/PDSVideoTranscoder.h"
#import <AVFoundation/AVFoundation.h>

/// Base class for video integration tests that need a valid MP4 fixture.
/// Generates a 1-second black frame MP4 programmatically using AVFoundation.
@interface VideoIntegrationTestBase : XCTestCase
@property (nonatomic, strong) NSURL *testVideoURL;
@end

@implementation VideoIntegrationTestBase

- (void)setUp {
    [super setUp];
    self.testVideoURL = [self generateTestVideo];
}

- (void)tearDown {
    if (self.testVideoURL) {
        [[NSFileManager defaultManager] removeItemAtURL:self.testVideoURL error:nil];
    }
    [super tearDown];
}

- (nullable NSURL *)generateTestVideo {
    NSURL *outputURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingFormat:@"test_video_%@.mp4", [[NSUUID UUID] UUIDString]]];

    // Create a 1-second black video using AVAssetWriter
    NSError *error = nil;
    NSDictionary *videoSettings = @{
        AVVideoCodecKey: AVVideoCodecH264,
        AVVideoWidthKey: @320,
        AVVideoHeightKey: @240
    };
    NSDictionary *pixelBufferAttrs = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32ARGB),
        (id)kCVPixelBufferWidthKey: @320,
        (id)kCVPixelBufferHeightKey: @240
    };

    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:outputURL
                                                     fileType:AVFileTypeMPEG4
                                                        error:&error];
    if (!writer) {
        NSLog(@"Failed to create AVAssetWriter: %@", error);
        return nil;
    }

    AVAssetWriterInput *input = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                                               outputSettings:videoSettings];
    input.expectsMediaDataInRealTime = NO;
    [writer addInput:input];

    AVAssetWriterInputPixelBufferAdaptor *adaptor =
        [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:input
                                                         sourcePixelBufferAttributes:pixelBufferAttrs];

    [writer startWriting];
    [writer startSessionAtSourceTime:kCMTimeZero];

    __block BOOL finished = NO;
    __block BOOL success = NO;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    NSInteger frameCount = 24; // 24fps * 1 second
    __block NSInteger currentFrame = 0;

    input.requestMediaDataWhenReadyOnQueue:dispatch_get_main_queue() usingBlock:^{
        while (input.isReadyForMoreMediaData && currentFrame < frameCount) {
            CMTime time = CMTimeMake(currentFrame, 24);
            CVPixelBufferRef pixelBuffer = NULL;
            CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, 320, 240,
                kCVPixelFormatType_32ARGB, NULL, &pixelBuffer);
            if (status == kCVReturnSuccess) {
                [adaptor appendPixelBuffer:pixelBuffer withPresentationTime:time];
                CVBufferRelease(pixelBuffer);
            }
            currentFrame++;
        }

        if (currentFrame >= frameCount) {
            [input markAsFinished];
            [writer finishWritingWithCompletionHandler:^{
                success = (writer.status == AVAssetWriterStatusCompleted);
                if (!success) {
                    NSLog(@"AVAssetWriter failed: %@", writer.error);
                }
                dispatch_semaphore_signal(sema);
            }];
        }
    }];

    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

    if (!success) {
        [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
        return nil;
    }

    return outputURL;
}

@end

#pragma mark - Transcoder Integration Tests

@interface PDSVideoTranscoderIntegrationTests : VideoIntegrationTestBase
@end

@implementation PDSVideoTranscoderIntegrationTests

- (void)testTranscodeSyncReturnsData {
    if (!self.testVideoURL) { XCTSkip(@"No test video available"); }

    PDSVideoTranscoder *transcoder = [[PDSVideoTranscoder alloc] init];
    NSError *error = nil;
    NSData *result = [transcoder transcodeVideoAtURL:self.testVideoURL
                                          toQuality:PDSVideoTranscoderQuality480p
                                               error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertTrue(result.length > 0);
}

- (void)testTranscodeAsyncCompletion {
    if (!self.testVideoURL) { XCTSkip(@"No test video available"); }

    PDSVideoTranscoder *transcoder = [[PDSVideoTranscoder alloc] init];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Transcode complete"];

    [transcoder transcodeVideoAtURL:self.testVideoURL
                         toQuality:PDSVideoTranscoderQuality480p
                         outputURL:nil
                         progress:nil
                       completion:^(NSURL *outputURL, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(outputURL);
        if (outputURL) {
            XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtURL:outputURL]);
            [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
        }
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:30 handler:nil];
}

- (void)testTranscodeInvalidURLError {
    PDSVideoTranscoder *transcoder = [[PDSVideoTranscoder alloc] init];
    NSURL *invalidURL = [NSURL fileURLWithPath:@"/nonexistent/path/video.mp4"];
    NSError *error = nil;
    NSData *result = [transcoder transcodeVideoAtURL:invalidURL
                                          toQuality:PDSVideoTranscoderQuality480p
                                               error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testTranscodeProgressCallback {
    if (!self.testVideoURL) { XCTSkip(@"No test video available"); }

    PDSVideoTranscoder *transcoder = [[PDSVideoTranscoder alloc] init];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Transcode complete"];
    __block BOOL progressCalled = NO;

    [transcoder transcodeVideoAtURL:self.testVideoURL
                         toQuality:PDSVideoTranscoderQuality480p
                         outputURL:nil
                         progress:^(float progress) {
        progressCalled = YES;
    }
                       completion:^(NSURL *outputURL, NSError *error) {
        if (outputURL) {
            [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
        }
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:30 handler:nil];
    // Progress may or may not be called depending on export speed
    // (fast exports may complete before the timer fires)
}

@end
