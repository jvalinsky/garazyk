#import <XCTest/XCTest.h>
#import "Media/PDSVideoThumbnailGenerator.h"
#import "Media/PDSVideoTranscoderIntegrationTests.h" // for VideoIntegrationTestBase

@interface PDSVideoThumbnailGeneratorIntegrationTests : VideoIntegrationTestBase
@end

@implementation PDSVideoThumbnailGeneratorIntegrationTests

- (void)testGenerateThumbnailSync {
    if (!self.testVideoURL) { XCTSkip(@"No test video available"); }

    PDSVideoThumbnailGenerator *generator = [[PDSVideoThumbnailGenerator alloc] init];
    NSError *error = nil;
    NSData *thumbnail = [generator generateThumbnailAtTime:0.5
                                            fromVideoURL:self.testVideoURL
                                               maxWidth:640
                                              maxHeight:360
                                                  error:&error];
    XCTAssertNotNil(thumbnail);
    XCTAssertNil(error);
    XCTAssertTrue(thumbnail.length > 0);

    // Verify it's valid JPEG (starts with FF D8)
    const uint8_t *bytes = (const uint8_t *)thumbnail.bytes;
    if (thumbnail.length >= 2) {
        XCTAssertEqual(bytes[0], 0xFF);
        XCTAssertEqual(bytes[1], 0xD8);
    }
}

- (void)testGenerateThumbnailAsync {
    if (!self.testVideoURL) { XCTSkip(@"No test video available"); }

    PDSVideoThumbnailGenerator *generator = [[PDSVideoThumbnailGenerator alloc] init];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Thumbnail generated"];

    [generator generateThumbnailAtTime:0.5
                          fromVideoURL:self.testVideoURL
                            maxWidth:640
                           maxHeight:360
                          completion:^(NSData *thumbnailData, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(thumbnailData);
        XCTAssertTrue(thumbnailData.length > 0);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:30 handler:nil];
}

- (void)testGenerateThumbnailInvalidTime {
    if (!self.testVideoURL) { XCTSkip(@"No test video available"); }

    PDSVideoThumbnailGenerator *generator = [[PDSVideoThumbnailGenerator alloc] init];
    NSError *error = nil;
    // Request a time far beyond the video duration (1 second)
    NSData *thumbnail = [generator generateThumbnailAtTime:999.0
                                            fromVideoURL:self.testVideoURL
                                               maxWidth:640
                                              maxHeight:360
                                                  error:&error];
    // May return nil or may return the last frame — behavior is undefined
    // Just verify it doesn't crash
    (void)thumbnail;
}

- (void)testGenerateThumbnailInvalidURL {
    PDSVideoThumbnailGenerator *generator = [[PDSVideoThumbnailGenerator alloc] init];
    NSURL *invalidURL = [NSURL fileURLWithPath:@"/nonexistent/path/video.mp4"];
    NSError *error = nil;
    NSData *thumbnail = [generator generateThumbnailAtTime:0.5
                                            fromVideoURL:invalidURL
                                               maxWidth:640
                                              maxHeight:360
                                                  error:&error];
    XCTAssertNil(thumbnail);
    XCTAssertNotNil(error);
}

@end
