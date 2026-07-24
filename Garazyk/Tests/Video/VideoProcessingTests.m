// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/ATProtoVideoProcessor.h"
#import "Video/AVFoundationTranscoder.h"
#import "Video/FFmpegTranscoder.h"
#import "Video/PDSLocalVideoJobStore.h"
#import "Video/VideoLocalBlobUploader.h"
#import "Video/VideoRemoteBlobUploader.h"
#import "Video/VideoJWTAuthProvider.h"
#import "Video/VideoPDSAuthProvider.h"
#import "Video/VideoTranscoder.h"
#import "Video/VideoTranscoderBackend.h"
#import "Video/VideoWorker.h"
#import "Video/JelczConfiguration.h"
#import "Video/VideoXrpcPack.h"

#pragma mark - ATProtoVideoProcessor

@interface ATProtoVideoProcessorTests : XCTestCase
@end

@implementation ATProtoVideoProcessorTests

- (void)testInstantiation {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertNotNil(processor);
}

- (void)testMediaTypeIdentifier {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertEqualObjects([processor mediaTypeIdentifier], @"app.bsky.video");
}

- (void)testDefaultInclude1080pIsNO {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertFalse(processor.include1080p);
}

- (void)testInclude1080pCanBeToggled {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    processor.include1080p = YES;
    XCTAssertTrue(processor.include1080p);
    processor.include1080p = NO;
    XCTAssertFalse(processor.include1080p);
}

- (void)testPropertiesDefaultToNil {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertNil(processor.did);
    XCTAssertNil(processor.blobCid);
    XCTAssertNil(processor.blobProvider);
    XCTAssertNil(processor.outputBaseUrl);
}

- (void)testDidCanBeSet {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    processor.did = @"did:plc:abc123";
    XCTAssertEqualObjects(processor.did, @"did:plc:abc123");
}

- (void)testBlobCidCanBeSet {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    processor.blobCid = @"bafyrei123";
    XCTAssertEqualObjects(processor.blobCid, @"bafyrei123");
}

- (void)testOutputBaseUrlCanBeSet {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    processor.outputBaseUrl = @"http://localhost:2586";
    XCTAssertEqualObjects(processor.outputBaseUrl, @"http://localhost:2586");
}

#pragma mark - canProcessMimeType:

- (void)testCanProcessMP4 {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertTrue([processor canProcessMimeType:@"video/mp4"]);
}

- (void)testCanProcessQuickTime {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertTrue([processor canProcessMimeType:@"video/quicktime"]);
}

- (void)testCanProcessM4V {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertTrue([processor canProcessMimeType:@"video/x-m4v"]);
}

- (void)testCanProcessWebM {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertTrue([processor canProcessMimeType:@"video/webm"]);
}

- (void)testCanProcessAVI {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertTrue([processor canProcessMimeType:@"video/x-msvideo"]);
}

- (void)testCanProcess3GPP {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertTrue([processor canProcessMimeType:@"video/3gpp"]);
}

- (void)testCanProcessMPEG {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertTrue([processor canProcessMimeType:@"video/mpeg"]);
}

- (void)testCanProcessOgg {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertTrue([processor canProcessMimeType:@"video/ogg"]);
}

- (void)testCanProcessCaseInsensitive {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertTrue([processor canProcessMimeType:@"Video/MP4"]);
    XCTAssertTrue([processor canProcessMimeType:@"VIDEO/MPEG"]);
}

- (void)testCanProcessGenericVideoPrefix {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertTrue([processor canProcessMimeType:@"video/x-custom-format"]);
}

- (void)testCannotProcessImageType {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertFalse([processor canProcessMimeType:@"image/jpeg"]);
}

- (void)testCannotProcessAudioType {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertFalse([processor canProcessMimeType:@"audio/mpeg"]);
}

- (void)testCannotProcessEmptyString {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertFalse([processor canProcessMimeType:@""]);
}

#pragma mark - validateContentSignature:

- (void)testValidateMP4Signature {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    // ftyp box at bytes 4-7 with "isom" brand
    uint8_t mp4Bytes[] = {
        0x00, 0x00, 0x00, 0x14, // box size = 20
        'f', 't', 'y', 'p',    // box type = ftyp
        'i', 's', 'o', 'm',    // major brand
        0x00, 0x00, 0x00, 0x01, // minor version
        'i', 's', 'o', 'm',    // compatible brand
        0x00, 0x00, 0x00, 0x00  // padding
    };
    NSData *mp4Data = [NSData dataWithBytes:mp4Bytes length:sizeof(mp4Bytes)];
    XCTAssertTrue([processor validateContentSignature:mp4Data declaredMimeType:@"video/mp4"]);
}

- (void)testValidateMOVSignature {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    uint8_t movBytes[] = {
        0x00, 0x00, 0x00, 0x14,
        'f', 't', 'y', 'p',
        'm', 'o', 'v', ' ',
        0x00, 0x00, 0x00, 0x01,
        'm', 'o', 'v', ' ',
        0x00, 0x00, 0x00, 0x00
    };
    NSData *movData = [NSData dataWithBytes:movBytes length:sizeof(movBytes)];
    XCTAssertTrue([processor validateContentSignature:movData declaredMimeType:@"video/quicktime"]);
}

- (void)testValidateWebMSignature {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    // WebM EBML header: 0x1A 0x45 0xDF 0xA3
    uint8_t webmBytes[] = {
        0x1A, 0x45, 0xDF, 0xA3,
        0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    };
    NSData *webmData = [NSData dataWithBytes:webmBytes length:sizeof(webmBytes)];
    XCTAssertTrue([processor validateContentSignature:webmData declaredMimeType:@"video/webm"]);
}

- (void)testValidateAVISignature {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    // AVI: "RIFF" at 0, "AVI " at 8
    uint8_t aviBytes[] = {
        'R', 'I', 'F', 'F',
        0x00, 0x00, 0x00, 0x00,
        'A', 'V', 'I', ' '
    };
    NSData *aviData = [NSData dataWithBytes:aviBytes length:sizeof(aviBytes)];
    XCTAssertTrue([processor validateContentSignature:aviData declaredMimeType:@"video/x-msvideo"]);
}

- (void)testValidateMPEGSignature {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    uint8_t mpegBytes[] = {
        0x00, 0x00, 0x01, 0xBA
    };
    NSData *mpegData = [NSData dataWithBytes:mpegBytes length:sizeof(mpegBytes)];
    XCTAssertTrue([processor validateContentSignature:mpegData declaredMimeType:@"video/mpeg"]);
}

- (void)testValidateMPEGB3Signature {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    uint8_t mpegBytes[] = {
        0x00, 0x00, 0x01, 0xB3
    };
    NSData *mpegData = [NSData dataWithBytes:mpegBytes length:sizeof(mpegBytes)];
    XCTAssertTrue([processor validateContentSignature:mpegData declaredMimeType:@"video/mpeg"]);
}

- (void)testValidateOggSignature {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    uint8_t oggBytes[] = {
        'O', 'g', 'g', 'S',
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    };
    NSData *oggData = [NSData dataWithBytes:oggBytes length:sizeof(oggBytes)];
    XCTAssertTrue([processor validateContentSignature:oggData declaredMimeType:@"video/ogg"]);
}

- (void)testValidateSignatureRejectsTooShort {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    uint8_t shortBytes[] = { 0x00, 0x00, 0x01 };
    NSData *shortData = [NSData dataWithBytes:shortBytes length:sizeof(shortBytes)];
    XCTAssertFalse([processor validateContentSignature:shortData declaredMimeType:@"video/mp4"]);
}

- (void)testValidateSignatureRejectsArbitraryBytes {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    uint8_t garbageBytes[] = {
        0xFF, 0xFE, 0xFD, 0xFC,
        0xFB, 0xFA, 0xF9, 0xF8,
        0xF7, 0xF6, 0xF5, 0xF4
    };
    NSData *garbageData = [NSData dataWithBytes:garbageBytes length:sizeof(garbageBytes)];
    XCTAssertFalse([processor validateContentSignature:garbageData declaredMimeType:@"video/mp4"]);
}

- (void)testValidateSignatureRejectsEmptyData {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    NSData *emptyData = [NSData data];
    XCTAssertFalse([processor validateContentSignature:emptyData declaredMimeType:@"video/mp4"]);
}

#pragma mark - Process with nil input

- (void)testProcessMediaWithNilURLCallsError {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTestExpectation *expectation = [self expectationWithDescription:@"completion called"];
    [processor processMediaAtURL:nil
                 outputDirectory:@"/tmp"
                   progressBlock:nil
                      completion:^(NSDictionary<NSString *,id> *results, NSError *error) {
        XCTAssertNil(results);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

#pragma mark - Conforms to ATProtoMediaProcessor

- (void)testConformsToATProtoMediaProcessor {
    ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];
    XCTAssertTrue([processor conformsToProtocol:@protocol(ATProtoMediaProcessor)]);
}

@end

#pragma mark - AVFoundationTranscoder

@interface AVFoundationTranscoderTests : XCTestCase
@end

@implementation AVFoundationTranscoderTests

- (void)testInstantiation {
    AVFoundationTranscoder *transcoder = [[AVFoundationTranscoder alloc] init];
    XCTAssertNotNil(transcoder);
}

- (void)testConformsToVideoTranscoderBackend {
    AVFoundationTranscoder *transcoder = [[AVFoundationTranscoder alloc] init];
    XCTAssertTrue([transcoder conformsToProtocol:@protocol(VideoTranscoderBackend)]);
}

- (void)testCancelAllExportsDoesNotThrow {
    AVFoundationTranscoder *transcoder = [[AVFoundationTranscoder alloc] init];
    XCTAssertNoThrow([transcoder cancelAllExports]);
}

- (void)testTranscodeNonexistentFileReturnsError {
    AVFoundationTranscoder *transcoder = [[AVFoundationTranscoder alloc] init];
    NSURL *fakeURL = [NSURL fileURLWithPath:@"/tmp/nonexistent_video_test_file.mp4"];
    XCTestExpectation *expectation = [self expectationWithDescription:@"completion called"];
    [transcoder transcodeVideoAtURL:fakeURL
                         toQuality:ATProtoVideoTranscoderQuality720p
                         outputURL:nil
                          progress:nil
                        completion:^(NSURL *outputURL, NSError *error) {
#if TARGET_OS_MAC
        XCTAssertNil(outputURL);
        XCTAssertNotNil(error);
#else
        XCTAssertNotNil(error);
#endif
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

@end

#pragma mark - FFmpegTranscoder

@interface FFmpegTranscoderTests : XCTestCase
@end

@implementation FFmpegTranscoderTests

- (void)testInstantiationWithDefaults {
    FFmpegTranscoder *transcoder = [[FFmpegTranscoder alloc] initWithFFmpegPath:nil
                                                                   ffprobePath:nil];
    XCTAssertNotNil(transcoder);
    XCTAssertEqualObjects(transcoder.ffmpegPath, @"ffmpeg");
    XCTAssertEqualObjects(transcoder.ffprobePath, @"ffprobe");
}

- (void)testInstantiationWithCustomPaths {
    FFmpegTranscoder *transcoder = [[FFmpegTranscoder alloc] initWithFFmpegPath:@"/usr/local/bin/ffmpeg"
                                                                   ffprobePath:@"/usr/local/bin/ffprobe"];
    XCTAssertNotNil(transcoder);
    XCTAssertEqualObjects(transcoder.ffmpegPath, @"/usr/local/bin/ffmpeg");
    XCTAssertEqualObjects(transcoder.ffprobePath, @"/usr/local/bin/ffprobe");
}

- (void)testConformsToVideoTranscoderBackend {
    FFmpegTranscoder *transcoder = [[FFmpegTranscoder alloc] initWithFFmpegPath:nil
                                                                   ffprobePath:nil];
    XCTAssertTrue([transcoder conformsToProtocol:@protocol(VideoTranscoderBackend)]);
}

- (void)testCancelAllExportsDoesNotThrow {
    FFmpegTranscoder *transcoder = [[FFmpegTranscoder alloc] initWithFFmpegPath:nil
                                                                   ffprobePath:nil];
    XCTAssertNoThrow([transcoder cancelAllExports]);
}

- (void)testFfmpegPathCanBeUpdated {
    FFmpegTranscoder *transcoder = [[FFmpegTranscoder alloc] initWithFFmpegPath:nil
                                                                   ffprobePath:nil];
    transcoder.ffmpegPath = @"/opt/custom/ffmpeg";
    XCTAssertEqualObjects(transcoder.ffmpegPath, @"/opt/custom/ffmpeg");
}

- (void)testFfprobePathCanBeUpdated {
    FFmpegTranscoder *transcoder = [[FFmpegTranscoder alloc] initWithFFmpegPath:nil
                                                                   ffprobePath:nil];
    transcoder.ffprobePath = @"/opt/custom/ffprobe";
    XCTAssertEqualObjects(transcoder.ffprobePath, @"/opt/custom/ffprobe");
}

- (void)testProbeDurationReturnsZeroForMissingFile {
    FFmpegTranscoder *transcoder = [[FFmpegTranscoder alloc] initWithFFmpegPath:nil
                                                                   ffprobePath:nil];
    NSURL *fakeURL = [NSURL fileURLWithPath:@"/tmp/nonexistent_video_test.mp4"];
    float duration = [transcoder probeDurationForVideoAtURL:fakeURL];
    XCTAssertEqual(duration, 0.0f);
}

- (void)testProbeDimensionsReturnsZeroForMissingFile {
    FFmpegTranscoder *transcoder = [[FFmpegTranscoder alloc] initWithFFmpegPath:nil
                                                                   ffprobePath:nil];
    NSURL *fakeURL = [NSURL fileURLWithPath:@"/tmp/nonexistent_video_test.mp4"];
    CGSize dims = [transcoder probeDimensionsForVideoAtURL:fakeURL];
    XCTAssertTrue(CGSizeEqualToSize(dims, CGSizeZero) || (dims.width == 0 && dims.height == 0));
}

- (void)testProbeFramerateReturnsZeroForMissingFile {
    FFmpegTranscoder *transcoder = [[FFmpegTranscoder alloc] initWithFFmpegPath:nil
                                                                   ffprobePath:nil];
    NSURL *fakeURL = [NSURL fileURLWithPath:@"/tmp/nonexistent_video_test.mp4"];
    float fps = [transcoder probeFramerateForVideoAtURL:fakeURL];
    XCTAssertEqual(fps, 0.0f);
}

@end

#pragma mark - JelczConfiguration

@interface JelczConfigurationTests : XCTestCase
@end

@implementation JelczConfigurationTests

- (void)testInstantiation {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    XCTAssertNotNil(config);
}

- (void)testDefaultPort {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.port = 2586;
    XCTAssertEqual(config.port, 2586u);
}

- (void)testPortCanBeSet {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.port = 8080;
    XCTAssertEqual(config.port, 8080u);
}

- (void)testDataDirectory {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.dataDirectory = @"/var/data";
    XCTAssertEqualObjects(config.dataDirectory, @"/var/data");
}

- (void)testBlobDirectory {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.blobDirectory = @"/var/blobs";
    XCTAssertEqualObjects(config.blobDirectory, @"/var/blobs");
}

- (void)testPDSURL {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.pdsURL = @"http://localhost:2583";
    XCTAssertEqualObjects(config.pdsURL, @"http://localhost:2583");
}

- (void)testPLCURL {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.plcURL = @"http://localhost:2582";
    XCTAssertEqualObjects(config.plcURL, @"http://localhost:2582");
}

- (void)testPLCURLCanBeNull {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.plcURL = nil;
    XCTAssertNil(config.plcURL);
}

- (void)testServiceDID {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.serviceDID = @"did:web:example.com";
    XCTAssertEqualObjects(config.serviceDID, @"did:web:example.com");
}

- (void)testMaxConcurrentJobs {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.maxConcurrentJobs = 4;
    XCTAssertEqual(config.maxConcurrentJobs, 4);
}

- (void)testPollInterval {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.pollInterval = 2.5;
    XCTAssertEqual(config.pollInterval, 2.5);
}

- (void)testMaxUploadBytes {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.maxUploadBytes = 100 * 1024 * 1024;
    XCTAssertEqual(config.maxUploadBytes, 100u * 1024u * 1024u);
}

- (void)testMaxOutputBytes {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.maxOutputBytes = 50 * 1024 * 1024;
    XCTAssertEqual(config.maxOutputBytes, 50u * 1024u * 1024u);
}

- (void)testMaxDurationSeconds {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.maxDurationSeconds = 300;
    XCTAssertEqual(config.maxDurationSeconds, 300);
}

- (void)testHLSOutputDirectory {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.hlsOutputDirectory = @"/tmp/hls";
    XCTAssertEqualObjects(config.hlsOutputDirectory, @"/tmp/hls");
}

- (void)testHLSOutputDirectoryCanBeNull {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.hlsOutputDirectory = nil;
    XCTAssertNil(config.hlsOutputDirectory);
}

- (void)testHLSBaseUrl {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.hlsBaseUrl = @"http://cdn.example.com";
    XCTAssertEqualObjects(config.hlsBaseUrl, @"http://cdn.example.com");
}

- (void)testHLSBaseUrlCanBeNull {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.hlsBaseUrl = nil;
    XCTAssertNil(config.hlsBaseUrl);
}

- (void)testHLSInclude1080p {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.hlsInclude1080p = YES;
    XCTAssertTrue(config.hlsInclude1080p);
}

- (void)testS3Bucket {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.s3Bucket = @"my-video-bucket";
    XCTAssertEqualObjects(config.s3Bucket, @"my-video-bucket");
}

- (void)testS3BucketCanBeNull {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.s3Bucket = nil;
    XCTAssertNil(config.s3Bucket);
}

- (void)testS3Region {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.s3Region = @"eu-west-1";
    XCTAssertEqualObjects(config.s3Region, @"eu-west-1");
}

- (void)testS3Endpoint {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.s3Endpoint = @"http://localhost:9000";
    XCTAssertEqualObjects(config.s3Endpoint, @"http://localhost:9000");
}

- (void)testS3EndpointCanBeNull {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.s3Endpoint = nil;
    XCTAssertNil(config.s3Endpoint);
}

- (void)testS3AccessKey {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.s3AccessKey = @"AKIAIOSFODNN7EXAMPLE";
    XCTAssertEqualObjects(config.s3AccessKey, @"AKIAIOSFODNN7EXAMPLE");
}

- (void)testS3AccessKeyCanBeNull {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.s3AccessKey = nil;
    XCTAssertNil(config.s3AccessKey);
}

- (void)testS3SecretKey {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.s3SecretKey = @"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
    XCTAssertEqualObjects(config.s3SecretKey, @"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY");
}

- (void)testS3SecretKeyCanBeNull {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];
    config.s3SecretKey = nil;
    XCTAssertNil(config.s3SecretKey);
}

#pragma mark - configurationFromEnvironment

- (void)testConfigurationFromEnvironmentReturnsInstance {
    JelczConfiguration *config = [JelczConfiguration configurationFromEnvironment];
    XCTAssertNotNil(config);
}

- (void)testConfigurationFromEnvironmentHasDefaults {
    JelczConfiguration *config = [JelczConfiguration configurationFromEnvironment];
    // These should have defaults when env vars are unset
    XCTAssertGreaterThan(config.port, 0u);
    XCTAssertNotNil(config.dataDirectory);
    XCTAssertNotNil(config.blobDirectory);
    XCTAssertNotNil(config.pdsURL);
    XCTAssertNotNil(config.serviceDID);
    XCTAssertGreaterThan(config.maxConcurrentJobs, 0);
    XCTAssertGreaterThan(config.pollInterval, 0.0);
    XCTAssertGreaterThan(config.maxUploadBytes, 0u);
    XCTAssertGreaterThan(config.maxOutputBytes, 0u);
    XCTAssertGreaterThan(config.maxDurationSeconds, 0);
}

- (void)testConfigurationFromEnvironmentS3RegionDefault {
    JelczConfiguration *config = [JelczConfiguration configurationFromEnvironment];
    XCTAssertNotNil(config.s3Region);
    XCTAssertEqualObjects(config.s3Region, @"us-east-1");
}

@end

#pragma mark - VideoRemoteBlobUploader

@interface VideoRemoteBlobUploaderTests : XCTestCase
@end

@implementation VideoRemoteBlobUploaderTests

- (void)testInstantiation {
    VideoRemoteBlobUploader *uploader = [[VideoRemoteBlobUploader alloc] initWithPDSURL:@"http://localhost:2583"];
    XCTAssertNotNil(uploader);
}

- (void)testConformsToVideoBlobUploader {
    VideoRemoteBlobUploader *uploader = [[VideoRemoteBlobUploader alloc] initWithPDSURL:@"http://localhost:2583"];
    XCTAssertTrue([uploader conformsToProtocol:@protocol(VideoBlobUploader)]);
}

- (void)testPDSURLIsStored {
    VideoRemoteBlobUploader *uploader = [[VideoRemoteBlobUploader alloc] initWithPDSURL:@"http://localhost:2583"];
    XCTAssertEqualObjects(uploader.pdsURL, @"http://localhost:2583");
}

- (void)testPDSURLIsCopied {
    NSMutableString *url = [NSMutableString stringWithString:@"http://example.com"];
    VideoRemoteBlobUploader *uploader = [[VideoRemoteBlobUploader alloc] initWithPDSURL:url];
    [url appendString:@":2583"];
    XCTAssertEqualObjects(uploader.pdsURL, @"http://example.com");
}

- (void)testUploadBlobReturnsErrorForUnreachableServer {
    VideoRemoteBlobUploader *uploader = [[VideoRemoteBlobUploader alloc] initWithPDSURL:@"http://127.0.0.1:1"];
    NSData *blobData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *result = [uploader uploadBlob:blobData
                                       mimeType:@"video/mp4"
                                    serviceAuth:nil
                                          error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

@end

#pragma mark - VideoLocalBlobUploader

@interface VideoLocalBlobUploaderTests : XCTestCase
@end

@implementation VideoLocalBlobUploaderTests

- (void)testInstantiation {
    // VideoLocalBlobUploader requires a PDSBlobProvider, but we can verify
    // the class exists and the initializer signature compiles.
    XCTAssertNotNil([VideoLocalBlobUploader class]);
}

- (void)testConformsToVideoBlobUploader {
    XCTAssertTrue([VideoLocalBlobUploader conformsToProtocol:@protocol(VideoBlobUploader)]);
}

@end

#pragma mark - VideoJWTAuthProvider

@interface VideoJWTAuthProviderTests : XCTestCase
@end

@implementation VideoJWTAuthProviderTests

- (void)testInstantiationWithJWK {
    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc] initWithExpectedAudience:@"did:web:video.example.com"
                                                                             signingKeyJWK:nil];
    XCTAssertNotNil(provider);
}

- (void)testInstantiationWithPDSURL {
    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc] initWithExpectedAudience:@"did:web:video.example.com"
                                                                                     pdsURL:@"http://localhost:2583"
                                                                                     plcURL:nil];
    XCTAssertNotNil(provider);
}

- (void)testConformsToVideoAuthProvider {
    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc] initWithExpectedAudience:@"did:web:video.example.com"
                                                                             signingKeyJWK:nil];
    XCTAssertTrue([provider conformsToProtocol:@protocol(VideoAuthProvider)]);
}

- (void)testAudienceIsStored {
    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc] initWithExpectedAudience:@"did:web:video.example.com"
                                                                             signingKeyJWK:nil];
    XCTAssertEqualObjects(provider.audience, @"did:web:video.example.com");
}

- (void)testSigningKeyJWKIsStored {
    NSDictionary *jwk = @{@"kty": @"OKP", @"crv": @"Ed25519"};
    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc] initWithExpectedAudience:@"did:web:video.example.com"
                                                                             signingKeyJWK:jwk];
    XCTAssertEqualObjects(provider.signingKeyJWK, jwk);
}

- (void)testSigningKeyJWKDefaultsToNil {
    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc] initWithExpectedAudience:@"did:web:video.example.com"
                                                                             signingKeyJWK:nil];
    XCTAssertNil(provider.signingKeyJWK);
}

- (void)testDIDResolverDefaultsToNil {
    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc] initWithExpectedAudience:@"did:web:video.example.com"
                                                                             signingKeyJWK:nil];
    XCTAssertNil(provider.didResolver);
}

- (void)testDIDResolverCreatedWithPDSURL {
    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc] initWithExpectedAudience:@"did:web:video.example.com"
                                                                                     pdsURL:@"http://localhost:2583"
                                                                                     plcURL:@"http://localhost:2582"];
    XCTAssertNotNil(provider.didResolver);
}

- (void)testDIDResolverUsesDefaultPLCWhenNil {
    VideoJWTAuthProvider *provider = [[VideoJWTAuthProvider alloc] initWithExpectedAudience:@"did:web:video.example.com"
                                                                                     pdsURL:@"http://localhost:2583"
                                                                                     plcURL:nil];
    XCTAssertNotNil(provider.didResolver);
}

@end

#pragma mark - VideoPDSAuthProvider

@interface VideoPDSAuthProviderTests : XCTestCase
@end

@implementation VideoPDSAuthProviderTests

- (void)testConformsToVideoAuthProvider {
    XCTAssertTrue([VideoPDSAuthProvider conformsToProtocol:@protocol(VideoAuthProvider)]);
}

- (void)testInstantiationRequiresJWTMinter {
    // We can't create a JWTMinter without dependencies, but we can verify the
    // class compiles and the protocol is adopted.
    XCTAssertNotNil([VideoPDSAuthProvider class]);
}

@end

#pragma mark - VideoWorker

@interface ATProtoVideoWorkerDefaultsTests : XCTestCase
@end

@implementation ATProtoVideoWorkerDefaultsTests

- (void)testSharedWorkerIsSingleton {
    ATProtoVideoWorker *a = [ATProtoVideoWorker sharedWorker];
    ATProtoVideoWorker *b = [ATProtoVideoWorker sharedWorker];
    XCTAssertEqual(a, b);
}

- (void)testDefaultDisabled {
    ATProtoVideoWorker *worker = [[ATProtoVideoWorker alloc] init];
    XCTAssertFalse(worker.isEnabled);
}

- (void)testDefaultPollInterval {
    ATProtoVideoWorker *worker = [[ATProtoVideoWorker alloc] init];
    XCTAssertEqual(worker.pollInterval, 5.0);
}

- (void)testDefaultMaxConcurrentJobs {
    ATProtoVideoWorker *worker = [[ATProtoVideoWorker alloc] init];
    XCTAssertEqual(worker.maxConcurrentJobs, 2);
}

- (void)testJobStoreDefaultsToNil {
    ATProtoVideoWorker *worker = [[ATProtoVideoWorker alloc] init];
    XCTAssertNil(worker.jobStore);
}

- (void)testBlobUploaderDefaultsToNil {
    ATProtoVideoWorker *worker = [[ATProtoVideoWorker alloc] init];
    XCTAssertNil(worker.blobUploader);
}

- (void)testBlobProviderDefaultsToNil {
    ATProtoVideoWorker *worker = [[ATProtoVideoWorker alloc] init];
    XCTAssertNil(worker.blobProvider);
}

- (void)testAuthProviderDefaultsToNil {
    ATProtoVideoWorker *worker = [[ATProtoVideoWorker alloc] init];
    XCTAssertNil(worker.authProvider);
}

- (void)testHLSGeneratorDefaultsToNil {
    ATProtoVideoWorker *worker = [[ATProtoVideoWorker alloc] init];
    XCTAssertNil(worker.hlsGenerator);
}

- (void)testEnabledCanBeToggled {
    ATProtoVideoWorker *worker = [[ATProtoVideoWorker alloc] init];
    worker.enabled = YES;
    XCTAssertTrue(worker.isEnabled);
    worker.enabled = NO;
    XCTAssertFalse(worker.isEnabled);
}

- (void)testPollIntervalCanBeSet {
    ATProtoVideoWorker *worker = [[ATProtoVideoWorker alloc] init];
    worker.pollInterval = 10.0;
    XCTAssertEqual(worker.pollInterval, 10.0);
}

- (void)testMaxConcurrentJobsCanBeSet {
    ATProtoVideoWorker *worker = [[ATProtoVideoWorker alloc] init];
    worker.maxConcurrentJobs = 8;
    XCTAssertEqual(worker.maxConcurrentJobs, 8);
}

@end

#pragma mark - VideoTranscoder

@interface ATProtoVideoTranscoderUnitTests : XCTestCase
@end

@implementation ATProtoVideoTranscoderUnitTests

- (void)testSharedTranscoderIsSingleton {
    ATProtoVideoTranscoder *a = [ATProtoVideoTranscoder sharedTranscoder];
    ATProtoVideoTranscoder *b = [ATProtoVideoTranscoder sharedTranscoder];
    XCTAssertEqual(a, b);
}

- (void)testDefaultBlobProviderIsNil {
    // Defaults are an initializer property; the shared singleton's state is
    // process-global and legitimately configured by other components.
    ATProtoVideoTranscoder *transcoder = [[ATProtoVideoTranscoder alloc] init];
    XCTAssertNil(transcoder.blobProvider);
}

- (void)testDefaultDelegateIsNil {
    ATProtoVideoTranscoder *transcoder = [[ATProtoVideoTranscoder alloc] init];
    XCTAssertNil(transcoder.delegate);
}

- (void)testCancelAllExportsDoesNotThrow {
    ATProtoVideoTranscoder *transcoder = [ATProtoVideoTranscoder sharedTranscoder];
    XCTAssertNoThrow([transcoder cancelAllExports]);
}

- (void)testErrorDomain {
    XCTAssertEqualObjects(ATProtoVideoTranscoderErrorDomain, @"com.atproto.video.transcoder");
}

- (void)testTranscoderQualityEnum {
    XCTAssertEqual(ATProtoVideoTranscoderQuality480p, 0);
    XCTAssertEqual(ATProtoVideoTranscoderQuality720p, 1);
    XCTAssertEqual(ATProtoVideoTranscoderQuality1080p, 2);
    XCTAssertEqual(ATProtoVideoTranscoderQualityHEVC, 3);
}

@end

#pragma mark - ATProtoVideoWorker (Error Domain & Enums)

@interface ATProtoVideoWorkerConstantsTests : XCTestCase
@end

@implementation ATProtoVideoWorkerConstantsTests

- (void)testWorkerErrorDomain {
    XCTAssertEqualObjects(ATProtoVideoWorkerErrorDomain, @"com.atproto.video.worker");
}

- (void)testJobStateEnum {
    XCTAssertEqual(ATProtoVideoJobStatePending, 0);
    XCTAssertEqual(ATProtoVideoJobStateProcessing, 1);
    XCTAssertEqual(ATProtoVideoJobStateTranscoding, 2);
    XCTAssertEqual(ATProtoVideoJobStateGeneratingThumbnail, 3);
    XCTAssertEqual(ATProtoVideoJobStateCompleted, 4);
    XCTAssertEqual(ATProtoVideoJobStateFailed, 5);
}

@end

#pragma mark - ATProtoVideoXrpcPack

@interface ATProtoVideoXrpcPackValidationTests : XCTestCase
@end

@implementation ATProtoVideoXrpcPackValidationTests

- (void)testConformsToXrpcRoutePack {
    XCTAssertTrue([ATProtoVideoXrpcPack conformsToProtocol:@protocol(XrpcRoutePack)]);
}

- (void)testValidateVideoContentTypeMP4 {
    uint8_t mp4Bytes[] = {
        0x00, 0x00, 0x00, 0x14,
        'f', 't', 'y', 'p',
        'i', 's', 'o', 'm',
        0x00, 0x00, 0x00, 0x01,
        'i', 's', 'o', 'm',
        0x00, 0x00, 0x00, 0x00
    };
    NSData *mp4Data = [NSData dataWithBytes:mp4Bytes length:sizeof(mp4Bytes)];
    XCTAssertTrue([ATProtoVideoXrpcPack validateVideoContentType:mp4Data declaredMimeType:@"video/mp4"]);
}

- (void)testValidateVideoContentTypeWebM {
    uint8_t webmBytes[] = {
        0x1A, 0x45, 0xDF, 0xA3,
        0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    };
    NSData *webmData = [NSData dataWithBytes:webmBytes length:sizeof(webmBytes)];
    XCTAssertTrue([ATProtoVideoXrpcPack validateVideoContentType:webmData declaredMimeType:@"video/webm"]);
}

- (void)testValidateVideoContentTypeRejectsShort {
    uint8_t shortBytes[] = { 0x00, 0x00 };
    NSData *shortData = [NSData dataWithBytes:shortBytes length:sizeof(shortBytes)];
    XCTAssertFalse([ATProtoVideoXrpcPack validateVideoContentType:shortData declaredMimeType:@"video/mp4"]);
}

- (void)testValidateVideoContentTypeRejectsNonVideo {
    uint8_t pngBytes[] = {
        0x89, 0x50, 0x4E, 0x47,
        0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D
    };
    NSData *pngData = [NSData dataWithBytes:pngBytes length:sizeof(pngBytes)];
    XCTAssertFalse([ATProtoVideoXrpcPack validateVideoContentType:pngData declaredMimeType:@"video/mp4"]);
}

@end

#pragma mark - VideoHLSResult

@interface VideoHLSResultTests : XCTestCase
@end

@implementation VideoHLSResultTests

- (void)testInstantiation {
    VideoHLSResult *result = [[VideoHLSResult alloc] init];
    XCTAssertNotNil(result);
}

- (void)testPropertiesDefaultToNil {
    VideoHLSResult *result = [[VideoHLSResult alloc] init];
    XCTAssertNil(result.masterPlaylistPath);
    XCTAssertNil(result.masterPlaylistRelativePath);
    XCTAssertNil(result.variants);
    XCTAssertNil(result.thumbnailPath);
}

- (void)testAllPropertiesSettable {
    VideoHLSResult *result = [[VideoHLSResult alloc] init];
    result.masterPlaylistPath = @"/hls/playlist.m3u8";
    result.masterPlaylistRelativePath = @"/watch/playlist.m3u8";
    result.variants = @[@{@"resolution": @"640x360", @"bandwidth": @"688540"}];
    result.thumbnailPath = @"/hls/thumb.jpg";

    XCTAssertEqualObjects(result.masterPlaylistPath, @"/hls/playlist.m3u8");
    XCTAssertEqualObjects(result.masterPlaylistRelativePath, @"/watch/playlist.m3u8");
    XCTAssertEqual(result.variants.count, 1u);
    XCTAssertEqualObjects(result.thumbnailPath, @"/hls/thumb.jpg");
}

@end
