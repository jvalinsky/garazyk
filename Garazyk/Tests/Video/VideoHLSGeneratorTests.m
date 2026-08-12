// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/VideoHLSGenerator.h"

#ifdef LINUX
#define PDS_TASK_SET_EXECUTABLE(task, path) task.launchPath = path
#define PDS_TASK_LAUNCH(task, error) ([task launch], YES)
#else
#define PDS_TASK_SET_EXECUTABLE(task, path) task.executableURL = [NSURL fileURLWithPath:path]
#define PDS_TASK_LAUNCH(task, error) [task launchAndReturnError:error]
#endif

// Phase 1 of docs/plans/workstreams/12-content-addressed-video.md: HLS output
// switched from MPEG-TS to fragmented MP4, with the segment_%03d wraparound
// defect fixed to %05d. This suite exercises the real ffmpeg invocation against
// a short synthetic fixture and asserts the produced tree shape rather than
// trusting argument construction alone. Tagged "integration" (see
// PDSGatedClassMap in test_main.m) and skipped cleanly when ffmpeg is absent,
// consistent with ATProtoVideoTranscoderIntegrationTests et al.
//
// Each test method re-runs the generator against its own fixture rather than
// sharing one. That costs a few seconds across the suite but keeps every
// assertion independently attributable: a failure names the property that
// broke (segment format, init segment, numbering width, playlist/disk
// agreement, producedFiles completeness) instead of one method failing for any
// of five reasons.

@interface VideoHLSGeneratorTests : XCTestCase
@property (nonatomic, strong, nullable) ATProtoVideoHLSGenerator *generator;
@property (nonatomic, copy, nullable) NSURL *fixtureURL;
@end

@implementation VideoHLSGeneratorTests

// NSTask's executableURL (macOS) / launchPath (GNUstep) both require a
// resolvable path -- a bare "ffmpeg" is looked up relative to the process CWD,
// not $PATH, so it will not launch here even when ffmpeg is installed. Resolve
// the absolute path once via `which` and hand it to both this fixture helper
// and the generator under test (through the public -ffmpegPath property).
+ (nullable NSString *)resolvedFfmpegPath {
    NSTask *task = [[NSTask alloc] init];
    PDS_TASK_SET_EXECUTABLE(task, @"/usr/bin/env");
    task.arguments = @[@"which", @"ffmpeg"];
    NSPipe *stdoutPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = [NSPipe pipe];
    NSError *launchError = nil;
    if (!PDS_TASK_LAUNCH(task, &launchError)) {
        return nil;
    }
    NSData *outputData = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        return nil;
    }
    NSString *path = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    path = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return path.length > 0 ? path : nil;
}

+ (BOOL)ffmpegIsAvailable {
    return [self resolvedFfmpegPath] != nil;
}

- (nullable NSURL *)generateFixtureVideoWithFfmpegPath:(NSString *)ffmpegPath {
    NSURL *outputURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingFormat:@"hls_fmp4_fixture_%@.mp4", [[NSUUID UUID] UUIDString]]];

    // A synthetic lavfi source keeps this fixture self-contained (no checked-in
    // binary asset) and, unlike an AVFoundation-generated source, exercises the
    // same ffmpeg binary the generator itself shells out to on every platform.
    NSTask *task = [[NSTask alloc] init];
    PDS_TASK_SET_EXECUTABLE(task, ffmpegPath);
    task.arguments = @[
        @"-f", @"lavfi", @"-i", @"testsrc=duration=13:size=320x240:rate=15",
        @"-f", @"lavfi", @"-i", @"sine=frequency=1000:duration=13",
        @"-c:v", @"libx264", @"-preset", @"ultrafast",
        @"-c:a", @"aac", @"-b:a", @"64k",
        @"-y", outputURL.path
    ];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    NSError *launchError = nil;
    if (!PDS_TASK_LAUNCH(task, &launchError)) {
        return nil;
    }
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        return nil;
    }
    return [[NSFileManager defaultManager] fileExistsAtPath:outputURL.path] ? outputURL : nil;
}

- (void)setUp {
    [super setUp];
    NSString *ffmpegPath = [[self class] resolvedFfmpegPath];
    if (!ffmpegPath) {
        return;
    }
    self.generator = [[ATProtoVideoHLSGenerator alloc] init];
    self.generator.ffmpegPath = ffmpegPath;
    self.generator.outputBaseDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"hls_fmp4_test_%@", [[NSUUID UUID] UUIDString]]];
    self.generator.include1080p = NO;
    self.fixtureURL = [self generateFixtureVideoWithFfmpegPath:ffmpegPath];
}

- (void)tearDown {
    if (self.generator.outputBaseDirectory) {
        [[NSFileManager defaultManager] removeItemAtPath:self.generator.outputBaseDirectory error:nil];
    }
    if (self.fixtureURL) {
        [[NSFileManager defaultManager] removeItemAtURL:self.fixtureURL error:nil];
    }
    [super tearDown];
}

#pragma mark - Helpers

// YES when the suite cannot run at all (no ffmpeg, or fixture generation
// failed). Callers must invoke XCTSkip themselves: XCTSkip expands to a return,
// so skipping from inside a helper would return from the helper and let the
// test body continue.
- (BOOL)prerequisitesMissing {
    return ![[self class] ffmpegIsAvailable] || self.fixtureURL == nil;
}

// Runs the generator under test. Records a failure and returns nil when
// generation fails, so each test body can bail without repeating the assert.
- (nullable GZVideoHLSResult *)generateHLS {
    NSError *error = nil;
    GZVideoHLSResult *result = [self.generator generateHLSFromVideoAtURL:self.fixtureURL
                                                                   did:@"did:plc:hlstest"
                                                                   cid:@"bafyreihlstest"
                                                         thumbnailData:nil
                                                                 error:&error];
    XCTAssertNotNil(result, @"HLS generation failed: %@", error);
    return result;
}

// Absolute directory holding one variant's playlist, init segment, and media
// segments.
- (NSString *)variantDirectoryForVariant:(NSDictionary *)variant {
    return [variant[@"playlistPath"] stringByDeletingLastPathComponent];
}

- (NSArray<NSString *> *)segmentFilenamesInDirectory:(NSString *)directory {
    NSArray<NSString *> *entries =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] ?: @[];
    NSPredicate *segmentPredicate = [NSPredicate predicateWithBlock:^BOOL(NSString *filename, NSDictionary *bindings) {
        return [filename hasPrefix:@"segment_"] && [filename hasSuffix:@".m4s"];
    }];
    return [entries filteredArrayUsingPredicate:segmentPredicate];
}

- (nullable NSString *)contentsOfFileAtPath:(NSString *)path {
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark - Segment container format

- (void)testProducesFragmentedMP4SegmentsAndNoMPEGTSArtifacts {
    if ([self prerequisitesMissing]) {
        XCTSkip(@"ffmpeg unavailable or fixture generation failed");
    }
    GZVideoHLSResult *result = [self generateHLS];
    if (!result) {
        return;
    }

    for (NSDictionary *variant in result.variants) {
        NSString *variantDir = [self variantDirectoryForVariant:variant];
        XCTAssertTrue([self segmentFilenamesInDirectory:variantDir].count > 0,
                      @"no .m4s segments produced in %@", variantDir);

        NSArray<NSString *> *entries =
            [[NSFileManager defaultManager] contentsOfDirectoryAtPath:variantDir error:nil] ?: @[];
        for (NSString *entry in entries) {
            XCTAssertFalse([entry hasSuffix:@".ts"], @"unexpected legacy .ts file: %@", entry);
        }
    }
}

#pragma mark - Init segments

- (void)testEachVariantHasInitSegmentReferencedByEXTXMAP {
    if ([self prerequisitesMissing]) {
        XCTSkip(@"ffmpeg unavailable or fixture generation failed");
    }
    GZVideoHLSResult *result = [self generateHLS];
    if (!result) {
        return;
    }

    // ffmpeg resolves -hls_fmp4_init_filename against the playlist's own
    // directory rather than the process CWD, so a bare filename must land the
    // init segment beside its variant playlist.
    for (NSDictionary *variant in result.variants) {
        NSString *variantDir = [self variantDirectoryForVariant:variant];
        NSString *initPath = [variantDir stringByAppendingPathComponent:@"init.mp4"];
        XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:initPath],
                      @"init segment missing at %@", initPath);

        NSString *playlist = [self contentsOfFileAtPath:variant[@"playlistPath"]];
        XCTAssertNotNil(playlist);
        XCTAssertTrue([playlist containsString:@"#EXT-X-MAP:URI=\"init.mp4\""],
                      @"variant playlist %@ missing correct #EXT-X-MAP line: %@",
                      variantDir.lastPathComponent, playlist);
    }
}

#pragma mark - Segment numbering width

- (void)testSegmentNumberingIsAtLeastFiveDigits {
    if ([self prerequisitesMissing]) {
        XCTSkip(@"ffmpeg unavailable or fixture generation failed");
    }
    GZVideoHLSResult *result = [self generateHLS];
    if (!result) {
        return;
    }

    // The defect this guards: segment_%03d wraps at 1000 segments -- 100
    // minutes at the configured -hls_time 6 -- silently overwriting earlier
    // segments of any longer video.
    for (NSDictionary *variant in result.variants) {
        NSString *variantDir = [self variantDirectoryForVariant:variant];
        NSArray<NSString *> *segments = [self segmentFilenamesInDirectory:variantDir];
        XCTAssertTrue(segments.count > 0, @"no segments to check numbering width in %@", variantDir);

        for (NSString *segmentFilename in segments) {
            NSString *numberPart = [segmentFilename stringByReplacingOccurrencesOfString:@"segment_" withString:@""];
            numberPart = [numberPart stringByReplacingOccurrencesOfString:@".m4s" withString:@""];
            XCTAssertGreaterThanOrEqual(numberPart.length, (NSUInteger)5,
                                        @"segment numbering width < 5 digits: %@", segmentFilename);
        }
    }
}

#pragma mark - Playlist structure

- (void)testMasterPlaylistReferencesEveryVariantPlaylist {
    if ([self prerequisitesMissing]) {
        XCTSkip(@"ffmpeg unavailable or fixture generation failed");
    }
    GZVideoHLSResult *result = [self generateHLS];
    if (!result) {
        return;
    }

    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:result.masterPlaylistPath]);
    XCTAssertEqual(result.variants.count, (NSUInteger)2); // 360p + 720p, include1080p is NO

    NSString *masterContents = [self contentsOfFileAtPath:result.masterPlaylistPath];
    XCTAssertNotNil(masterContents);

    for (NSDictionary *variant in result.variants) {
        NSString *variantPlaylistPath = variant[@"playlistPath"];
        XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:variantPlaylistPath],
                      @"variant playlist missing at %@", variantPlaylistPath);

        // Master references each variant by its hlsDir-relative path,
        // e.g. "360p/video.m3u8".
        NSString *variantName = [self variantDirectoryForVariant:variant].lastPathComponent;
        NSString *variantRelative = [NSString stringWithFormat:@"%@/video.m3u8", variantName];
        XCTAssertTrue([masterContents containsString:variantRelative],
                      @"master playlist missing reference to %@", variantRelative);
    }
}

- (void)testVariantPlaylistsReferenceEverySegmentOnDisk {
    if ([self prerequisitesMissing]) {
        XCTSkip(@"ffmpeg unavailable or fixture generation failed");
    }
    GZVideoHLSResult *result = [self generateHLS];
    if (!result) {
        return;
    }

    for (NSDictionary *variant in result.variants) {
        NSString *variantDir = [self variantDirectoryForVariant:variant];
        NSString *playlist = [self contentsOfFileAtPath:variant[@"playlistPath"]];
        XCTAssertNotNil(playlist);

        for (NSString *segmentFilename in [self segmentFilenamesInDirectory:variantDir]) {
            XCTAssertTrue([playlist containsString:segmentFilename],
                          @"variant playlist does not reference %@", segmentFilename);
        }
    }
}

#pragma mark - producedFiles

- (void)testProducedFilesMapsEveryFileOnDisk {
    if ([self prerequisitesMissing]) {
        XCTSkip(@"ffmpeg unavailable or fixture generation failed");
    }
    GZVideoHLSResult *result = [self generateHLS];
    if (!result) {
        return;
    }

    // producedFiles must be complete and disk-accurate: a later phase builds
    // the MASL manifest straight off this map and must never re-scan the
    // output directory.
    XCTAssertNotNil(result.producedFiles);
    XCTAssertEqualObjects(result.producedFiles[@"/"], result.masterPlaylistPath);

    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger diskFileCount = 1; // master playlist
    for (NSDictionary *variant in result.variants) {
        NSString *variantDir = [self variantDirectoryForVariant:variant];
        NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:variantDir error:nil] ?: @[];
        diskFileCount += entries.count; // video.m3u8 + init.mp4 + segment_*.m4s
    }
    XCTAssertEqual(result.producedFiles.count, diskFileCount,
                   @"producedFiles count does not match files actually on disk");

    for (NSString *bundlePath in result.producedFiles) {
        NSString *diskPath = result.producedFiles[bundlePath];
        XCTAssertTrue([fm fileExistsAtPath:diskPath],
                      @"producedFiles entry %@ -> %@ does not exist on disk", bundlePath, diskPath);
    }
}

@end
