// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/VideoHLSGenerator.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"

#if TARGET_OS_MAC
#import <AVFoundation/AVFoundation.h>
#endif

#ifdef LINUX
#define PDS_TASK_SET_EXECUTABLE(task, path) task.launchPath = path
#define PDS_TASK_LAUNCH(task, error) ([task launch], YES)
#else
#define PDS_TASK_SET_EXECUTABLE(task, path) task.executableURL = [NSURL fileURLWithPath:path]
#define PDS_TASK_LAUNCH(task, error) [task launchAndReturnError:error]
#endif

NSString * const ATProtoVideoHLSGeneratorErrorDomain = @"com.atproto.video.hls";

@implementation GZVideoHLSResult
@end

@implementation ATProtoVideoHLSGenerator

+ (instancetype)sharedGenerator {
    static ATProtoVideoHLSGenerator *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ATProtoVideoHLSGenerator alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _ffmpegPath = @"ffmpeg";
        _outputBaseDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"hls"];
        _include1080p = NO;
    }
    return self;
}

#pragma mark - Path Construction

- (NSString *)hlsDirectoryForDID:(NSString *)did cid:(NSString *)cid {
    // Sanitize DID and ATProtoCID for use as directory names
    NSString *safeDid = [did stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    NSString *safeCid = [cid stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    return [self.outputBaseDirectory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@/%@", safeDid, safeCid]];
}

- (NSString *)masterPlaylistPathForDID:(NSString *)did cid:(NSString *)cid {
    return [[self hlsDirectoryForDID:did cid:cid] stringByAppendingPathComponent:@"playlist.m3u8"];
}

- (NSString *)thumbnailPathForDID:(NSString *)did cid:(NSString *)cid {
    return [[self hlsDirectoryForDID:did cid:cid] stringByAppendingPathComponent:@"thumbnail.jpg"];
}

#pragma mark - Input Probing

- (BOOL)inputHasAudioTrackAtURL:(NSURL *)inputURL
{
#if TARGET_OS_MAC
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputURL options:nil];
    return [asset tracksWithMediaType:AVMediaTypeAudio].count > 0;
#else
    (void)inputURL;
    return YES;
#endif
}

#pragma mark - HLS Generation

- (nullable GZVideoHLSResult *)generateHLSFromVideoAtURL:(NSURL *)inputURL
                                                    did:(NSString *)did
                                                    cid:(NSString *)cid
                                          thumbnailData:(nullable NSData *)thumbnailData
                                                  error:(NSError **)error {
    if (!inputURL || !did || !cid) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoVideoHLSGeneratorErrorDomain
                                          code:ATProtoVideoHLSErrorInvalidInput
                                      userInfo:@{NSLocalizedDescriptionKey: @"Missing input URL, DID, or CID"}];
        }
        return nil;
    }

    NSString *hlsDir = [self hlsDirectoryForDID:did cid:cid];
    NSFileManager *fm = [NSFileManager defaultManager];

    // Create output directory structure
    if (![fm createDirectoryAtPath:hlsDir withIntermediateDirectories:YES attributes:nil error:error]) {
        GZ_LOG_ERROR(@"Failed to create HLS directory: %@", *error);
        if (error) {
            *error = [NSError errorWithDomain:ATProtoVideoHLSGeneratorErrorDomain
                                          code:ATProtoVideoHLSErrorOutputDirectoryFailed
                                      userInfo:@{NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"Failed to create HLS directory: %@", (*error).localizedDescription]}];
        }
        return nil;
    }

    // Build variant configurations
    NSMutableArray<NSDictionary *> *variantConfigs = [NSMutableArray array];
    [variantConfigs addObject:@{
        @"name": @"360p",
        @"resolution": @"640x360",
        @"bandwidth": @"688540",
        @"bitrate": @"1M",
        @"maxrate": @"1500k",
        @"bufsize": @"3000k"
    }];
    [variantConfigs addObject:@{
        @"name": @"720p",
        @"resolution": @"1280x720",
        @"bandwidth": @"1921217",
        @"bitrate": @"2.5M",
        @"maxrate": @"3500k",
        @"bufsize": @"7000k"
    }];
    if (self.include1080p) {
        [variantConfigs addObject:@{
            @"name": @"1080p",
            @"resolution": @"1920x1080",
            @"bandwidth": @"5000000",
            @"bitrate": @"5M",
            @"maxrate": @"5500k",
            @"bufsize": @"11000k"
        }];
    }

    // Create subdirectories for each variant
    for (NSDictionary *config in variantConfigs) {
        NSString *variantDir = [hlsDir stringByAppendingPathComponent:config[@"name"]];
        if (![fm createDirectoryAtPath:variantDir withIntermediateDirectories:YES attributes:nil error:nil]) {
            GZ_LOG_WARN(@"Failed to create variant directory: %@", variantDir);
        }
    }

    // Generate HLS for each variant using ffmpeg
    // We use a single ffmpeg invocation with multiple -hls outputs for efficiency
    BOOL hasAudio = [self inputHasAudioTrackAtURL:inputURL];
    NSMutableArray<NSString *> *args = [NSMutableArray array];
    [args addObject:@"-i"];
    [args addObject:inputURL.path];
    [args addObject:@"-y"];

    // Add each variant as a separate output stream
    for (NSDictionary *config in variantConfigs) {
        NSString *variantDir = [hlsDir stringByAppendingPathComponent:config[@"name"]];
        NSString *playlistPath = [variantDir stringByAppendingPathComponent:@"video.m3u8"];

        [args addObject:@"-map"];
        [args addObject:@"0:v"];
        if (hasAudio) {
            [args addObject:@"-map"];
            [args addObject:@"0:a"];
        }
        [args addObject:@"-c:v"];
        [args addObject:@"libx264"];
        [args addObject:@"-preset"];
        [args addObject:@"fast"];
        if (hasAudio) {
            [args addObject:@"-c:a"];
            [args addObject:@"aac"];
            [args addObject:@"-b:a"];
            [args addObject:@"128k"];
        } else {
            [args addObject:@"-an"];
        }
        [args addObject:@"-vf"];
        [args addObject:[NSString stringWithFormat:@"scale=%@:force_original_aspect_ratio=decrease", config[@"resolution"]]];
        [args addObject:@"-b:v"];
        [args addObject:config[@"bitrate"]];
        [args addObject:@"-maxrate"];
        [args addObject:config[@"maxrate"]];
        [args addObject:@"-bufsize"];
        [args addObject:config[@"bufsize"]];
        [args addObject:@"-f"];
        [args addObject:@"hls"];
        [args addObject:@"-hls_time"];
        [args addObject:@"6"];
        [args addObject:@"-hls_list_size"];
        [args addObject:@"0"];
        [args addObject:@"-hls_segment_type"];
        [args addObject:@"fmp4"];
        // Resolved relative to playlistPath's directory (i.e. variantDir), not the
        // process CWD -- verified empirically against ffmpeg 9.0. A bare filename
        // here is what keeps the init segment inside the correct variant directory.
        [args addObject:@"-hls_fmp4_init_filename"];
        [args addObject:@"init.mp4"];
        [args addObject:@"-hls_segment_filename"];
        // %05d avoids the %03d wraparound (1,000 segments = 100 min at
        // -hls_time 6), after which ffmpeg would silently overwrite earlier
        // segments.
        [args addObject:[variantDir stringByAppendingPathComponent:@"segment_%05d.m4s"]];
        [args addObject:playlistPath];
    }

    // Launch ffmpeg
    NSTask *task = [[NSTask alloc] init];
    PDS_TASK_SET_EXECUTABLE(task, self.ffmpegPath);
    task.arguments = args;

    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardError = stderrPipe;

    NSError *taskError = nil;
    BOOL launched = PDS_TASK_LAUNCH(task, &taskError);
    if (!launched) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoVideoHLSGeneratorErrorDomain
                                          code:ATProtoVideoHLSErrorFFmpegLaunchFailed
                                      userInfo:@{NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"Failed to launch ffmpeg: %@",
                                                      taskError.localizedDescription ?: @"unknown error"]}];
        }
        return nil;
    }

    [task waitUntilExit];
    int status = task.terminationStatus;

    if (status != 0) {
        NSData *stderrData = [stderrPipe.fileHandleForReading readDataToEndOfFile];
        NSString *stderrStr = stderrData ? [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] : @"(no stderr)";
        GZ_LOG_ERROR(@"ffmpeg HLS generation failed (exit %d): %@", status, stderrStr);

        if (error) {
            *error = [NSError errorWithDomain:ATProtoVideoHLSGeneratorErrorDomain
                                          code:ATProtoVideoHLSErrorFFmpegFailed
                                      userInfo:@{NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"ffmpeg exited with status %d: %@",
                                                      status, [stderrStr substringToIndex:MIN(stderrStr.length, 500)]]}];
        }
        return nil;
    }

    // Build the master playlist
    NSString *masterPlaylistPath = [self masterPlaylistPathForDID:did cid:cid];
    NSMutableString *masterPlaylist = [NSMutableString string];
    [masterPlaylist appendString:@"#EXTM3U\n"];
    [masterPlaylist appendString:@"#EXT-X-VERSION:3\n"];

    NSMutableArray<NSDictionary *> *variantResults = [NSMutableArray array];
    for (NSDictionary *config in variantConfigs) {
        NSString *variantPlaylistRelative = [NSString stringWithFormat:@"%@/video.m3u8", config[@"name"]];

        [masterPlaylist appendFormat:@"#EXT-X-STREAM-INF:BANDWIDTH=%@,CODECS=\"avc1.64001e,mp4a.40.2\",RESOLUTION=%@\n",
            config[@"bandwidth"], config[@"resolution"]];
        [masterPlaylist appendFormat:@"%@\n", variantPlaylistRelative];

        [variantResults addObject:@{
            @"resolution": config[@"resolution"],
            @"bandwidth": config[@"bandwidth"],
            @"playlistPath": [hlsDir stringByAppendingPathComponent:variantPlaylistRelative]
        }];
    }

    NSError *writeError = nil;
    NSData *playlistData = [masterPlaylist dataUsingEncoding:NSUTF8StringEncoding];
    if (![playlistData writeToFile:masterPlaylistPath options:NSDataWritingAtomic error:&writeError]) {
        GZ_LOG_ERROR(@"Failed to write master playlist: %@", writeError);
        if (error) {
            *error = [NSError errorWithDomain:ATProtoVideoHLSGeneratorErrorDomain
                                          code:ATProtoVideoHLSErrorOutputDirectoryFailed
                                      userInfo:@{NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"Failed to write master playlist: %@",
                                                      writeError.localizedDescription]}];
        }
        return nil;
    }

    // Write thumbnail if provided
    NSString *thumbnailPath = nil;
    if (thumbnailData) {
        thumbnailPath = [self thumbnailPathForDID:did cid:cid];
        if (![thumbnailData writeToFile:thumbnailPath options:NSDataWritingAtomic error:nil]) {
            GZ_LOG_WARN(@"Failed to write HLS thumbnail for %@/%@", did, cid);
            thumbnailPath = nil;
        }
    }

    // Walk the on-disk tree once here so callers never need to re-scan it: map
    // every produced file to its MASL bundle-root-relative path.
    NSMutableDictionary<NSString *, NSString *> *producedFiles = [NSMutableDictionary dictionary];
    producedFiles[@"/"] = masterPlaylistPath;
    for (NSDictionary *config in variantConfigs) {
        NSString *variantName = config[@"name"];
        NSString *variantDir = [hlsDir stringByAppendingPathComponent:variantName];
        NSString *variantPlaylistPath = [variantDir stringByAppendingPathComponent:@"video.m3u8"];
        NSString *initSegmentPath = [variantDir stringByAppendingPathComponent:@"init.mp4"];

        producedFiles[[NSString stringWithFormat:@"/%@/video.m3u8", variantName]] = variantPlaylistPath;
        if ([fm fileExistsAtPath:initSegmentPath]) {
            producedFiles[[NSString stringWithFormat:@"/%@/init.mp4", variantName]] = initSegmentPath;
        } else {
            GZ_LOG_WARN(@"HLS init segment missing for variant %@ at %@", variantName, initSegmentPath);
        }

        NSArray<NSString *> *variantDirContents = [fm contentsOfDirectoryAtPath:variantDir error:nil] ?: @[];
        NSPredicate *segmentPredicate = [NSPredicate predicateWithBlock:^BOOL(NSString *filename, NSDictionary *bindings) {
            return [filename hasPrefix:@"segment_"] && [filename hasSuffix:@".m4s"];
        }];
        NSArray<NSString *> *segmentFilenames = [[variantDirContents filteredArrayUsingPredicate:segmentPredicate]
            sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *segmentFilename in segmentFilenames) {
            producedFiles[[NSString stringWithFormat:@"/%@/%@", variantName, segmentFilename]] =
                [variantDir stringByAppendingPathComponent:segmentFilename];
        }
    }

    // Build result
    GZVideoHLSResult *result = [[GZVideoHLSResult alloc] init];
    result.masterPlaylistPath = masterPlaylistPath;
    result.masterPlaylistRelativePath = [NSString stringWithFormat:@"/watch/%@/%@/playlist.m3u8",
                                          [did stringByReplacingOccurrencesOfString:@":" withString:@"_"],
                                          [cid stringByReplacingOccurrencesOfString:@":" withString:@"_"]];
    result.variants = [variantResults copy];
    result.thumbnailPath = thumbnailPath;
    result.producedFiles = [producedFiles copy];

    GZ_LOG_INFO(@"HLS generation complete for %@/%@: %lu variants, master at %@",
                 did, cid, (unsigned long)variantConfigs.count, masterPlaylistPath);

    return result;
}

#pragma mark - Cleanup

- (void)removeHLSForDID:(NSString *)did cid:(NSString *)cid {
    NSString *hlsDir = [self hlsDirectoryForDID:did cid:cid];
    [[NSFileManager defaultManager] removeItemAtPath:hlsDir error:nil];
}

@end
