// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/VideoHLSGenerator.h"

@interface ATProtoVideoHLSGeneratorTests : XCTestCase
@property (nonatomic, strong) ATProtoVideoHLSGenerator *generator;
@end

@implementation ATProtoVideoHLSGeneratorTests

- (void)setUp {
    [super setUp];
    self.generator = [[ATProtoVideoHLSGenerator alloc] init];
    // Use a temp directory for test output
    self.generator.outputBaseDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                          [NSString stringWithFormat:@"hls_test_%@", [[NSUUID UUID] UUIDString]]];
    self.generator.ffmpegPath = @"ffmpeg";
    self.generator.include1080p = NO;
}

- (void)tearDown {
    // Clean up temp directory
    if (self.generator.outputBaseDirectory) {
        [[NSFileManager defaultManager] removeItemAtPath:self.generator.outputBaseDirectory error:nil];
    }
    [super tearDown];
}

#pragma mark - Path Construction

- (void)testHlsDirectoryForDIDCID {
    NSString *path = [self.generator hlsDirectoryForDID:@"did:plc:abc123" cid:@"bafyrei123"];
    XCTAssertNotNil(path);
    XCTAssertTrue([path containsString:@"did_plc_abc123"]);
    XCTAssertTrue([path containsString:@"bafyrei123"]);
}

- (void)testMasterPlaylistPath {
    NSString *path = [self.generator masterPlaylistPathForDID:@"did:plc:abc123" cid:@"bafyrei123"];
    XCTAssertNotNil(path);
    XCTAssertTrue([path hasSuffix:@"playlist.m3u8"]);
}

- (void)testThumbnailPath {
    NSString *path = [self.generator thumbnailPathForDID:@"did:plc:abc123" cid:@"bafyrei123"];
    XCTAssertNotNil(path);
    XCTAssertTrue([path hasSuffix:@"thumbnail.jpg"]);
}

- (void)testDIDColonReplacedInPath {
    // DIDs contain colons which are invalid in paths
    NSString *path = [self.generator hlsDirectoryForDID:@"did:plc:test" cid:@"cid:val"];
    XCTAssertNotNil(path);
    XCTAssertFalse([path containsString:@":"]); // colons should be replaced
}

#pragma mark - Shared Generator

- (void)testSharedGeneratorIsSingleton {
    ATProtoVideoHLSGenerator *a = [ATProtoVideoHLSGenerator sharedGenerator];
    ATProtoVideoHLSGenerator *b = [ATProtoVideoHLSGenerator sharedGenerator];
    XCTAssertEqual(a, b);
}

#pragma mark - Invalid Input

- (void)testGenerateHLSWithNilURLReturnsError {
    NSError *error = nil;
    VideoHLSResult *result = [self.generator generateHLSFromVideoAtURL:nil
                                                                   did:@"did:plc:abc"
                                                                   cid:@"bafyrei123"
                                                         thumbnailData:nil
                                                                 error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoVideoHLSErrorInvalidInput);
}

- (void)testGenerateHLSWithNilDIDReturnsError {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/nonexistent.mp4"];
    NSError *error = nil;
    VideoHLSResult *result = [self.generator generateHLSFromVideoAtURL:url
                                                                   did:nil
                                                                   cid:@"bafyrei123"
                                                         thumbnailData:nil
                                                                 error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoVideoHLSErrorInvalidInput);
}

- (void)testGenerateHLSWithNilCIDReturnsError {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/nonexistent.mp4"];
    NSError *error = nil;
    VideoHLSResult *result = [self.generator generateHLSFromVideoAtURL:url
                                                                   did:@"did:plc:abc"
                                                                   cid:nil
                                                         thumbnailData:nil
                                                                 error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, ATProtoVideoHLSErrorInvalidInput);
}

#pragma mark - Cleanup

- (void)testRemoveHLSForDIDCID {
    NSString *hlsDir = [self.generator hlsDirectoryForDID:@"did:plc:abc" cid:@"bafyrei123"];
    // Create a dummy file
    [[NSFileManager defaultManager] createDirectoryAtPath:hlsDir withIntermediateDirectories:YES attributes:nil error:nil];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:hlsDir]);

    [self.generator removeHLSForDID:@"did:plc:abc" cid:@"bafyrei123"];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:hlsDir]);
}

#pragma mark - Include1080p

- (void)testDefaultInclude1080pIsNO {
    ATProtoVideoHLSGenerator *gen = [[ATProtoVideoHLSGenerator alloc] init];
    XCTAssertFalse(gen.include1080p);
}

- (void)testInclude1080pCanBeSet {
    self.generator.include1080p = YES;
    XCTAssertTrue(self.generator.include1080p);
}

#pragma mark - VideoHLSResult

- (void)testVideoHLSResultProperties {
    VideoHLSResult *result = [[VideoHLSResult alloc] init];
    result.masterPlaylistPath = @"/tmp/hls/test/playlist.m3u8";
    result.masterPlaylistRelativePath = @"/watch/did_plc_abc/bafyrei123/playlist.m3u8";
    result.variants = @[@{@"resolution": @"640x360", @"bandwidth": @"688540"}];
    result.thumbnailPath = @"/tmp/hls/test/thumbnail.jpg";

    XCTAssertEqualObjects(result.masterPlaylistPath, @"/tmp/hls/test/playlist.m3u8");
    XCTAssertEqualObjects(result.masterPlaylistRelativePath, @"/watch/did_plc_abc/bafyrei123/playlist.m3u8");
    XCTAssertEqual(result.variants.count, 1);
    XCTAssertEqualObjects(result.thumbnailPath, @"/tmp/hls/test/thumbnail.jpg");
}

@end
