#import <XCTest/XCTest.h>
#import "Media/PDSVideoTranscoder.h"
#import <AVFoundation/AVFoundation.h>

@interface PDSVideoTranscoderTests : XCTestCase
@property (nonatomic, strong) PDSVideoTranscoder *transcoder;
@end

@implementation PDSVideoTranscoderTests

- (void)setUp {
    [super setUp];
    // Use fresh instance instead of shared singleton to avoid state leakage
    self.transcoder = [[PDSVideoTranscoder alloc] init];
}

- (void)tearDown {
    self.transcoder = nil;
    [super tearDown];
}

#pragma mark - Error Domain

- (void)testErrorDomain {
    XCTAssertEqualObjects(PDSVideoTranscoderErrorDomain, @"com.atproto.pds.video.transcoder");
}

#pragma mark - Preset Mapping

- (void)testPresetForQuality480p {
    XCTAssertEqualObjects([self.transcoder presetForQuality:PDSVideoTranscoderQuality480p],
                          AVAssetExportPreset640x480);
}

- (void)testPresetForQuality720p {
    XCTAssertEqualObjects([self.transcoder presetForQuality:PDSVideoTranscoderQuality720p],
                          AVAssetExportPreset1280x720);
}

- (void)testPresetForQuality1080p {
    XCTAssertEqualObjects([self.transcoder presetForQuality:PDSVideoTranscoderQuality1080p],
                          AVAssetExportPreset1920x1080);
}

- (void)testPresetForQualityHEVC {
    XCTAssertEqualObjects([self.transcoder presetForQuality:PDSVideoTranscoderQualityHEVC],
                          AVAssetExportPresetHEVCHighestQuality);
}

- (void)testPresetForQualityDefault {
    // Invalid enum value should fall through to default
    XCTAssertEqualObjects([self.transcoder presetForQuality:(PDSVideoTranscoderQuality)99],
                          AVAssetExportPresetHighestQuality);
}

#pragma mark - Singleton

- (void)testSharedTranscoderIsSingleton {
    PDSVideoTranscoder *a = [PDSVideoTranscoder sharedTranscoder];
    PDSVideoTranscoder *b = [PDSVideoTranscoder sharedTranscoder];
    XCTAssertEqual(a, b);
}

#pragma mark - Configuration

- (void)testMaxConcurrentExportsDefault {
    XCTAssertEqual(self.transcoder.maxConcurrentExports, 2);
}

#pragma mark - Cancel

- (void)testCancelAllExports {
    // Should not crash when called with no active exports
    [self.transcoder cancelAllExports];

    // Should not crash when called again
    [self.transcoder cancelAllExports];
}

@end
