#import "Video/FFmpegTranscoder.h"
#import "Video/VideoTranscoder.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"

#ifdef LINUX
// GNUstep NSTask doesn't have executableURL; use setLaunchPath: instead
#define PDS_TASK_SET_EXECUTABLE(task, path) task.launchPath = path
#define PDS_TASK_LAUNCH(task, error) ([task launch], YES)
#else
#define PDS_TASK_SET_EXECUTABLE(task, path) task.executableURL = [NSURL fileURLWithPath:path]
#define PDS_TASK_LAUNCH(task, error) [task launchAndReturnError:error]
#endif

// CGSize compat for GNUstep (no CoreGraphics)
#ifndef __APPLE__
typedef struct CGSize { double width; double height; } CGSize;
#endif

#ifndef CGSizeZero
#define CGSizeZero ((CGSize){0, 0})
#endif
#ifndef CGSizeMake
#define CGSizeMake(w, h) ((CGSize){(CGFloat)(w), (CGFloat)(h)})
#endif

NSString * const FFmpegTranscoderErrorDomain = @"com.atproto.video.transcoder.ffmpeg";

@implementation FFmpegTranscoder

- (instancetype)initWithFFmpegPath:(nullable NSString *)ffmpegPath
                      ffprobePath:(nullable NSString *)ffprobePath {
    self = [super init];
    if (self) {
        _ffmpegPath = ffmpegPath ?: @"ffmpeg";
        _ffprobePath = ffprobePath ?: @"ffprobe";
    }
    return self;
}

- (void)transcodeVideoAtURL:(NSURL *)inputURL
                  toQuality:(ATProtoVideoTranscoderQuality)quality
                  outputURL:(nullable NSURL *)outputURL
                   progress:(nullable void (^)(float))progressBlock
                 completion:(void (^)(NSURL *, NSError *))completion {

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            NSURL *finalOutputURL = outputURL;
            BOOL shouldCleanup = NO;

            if (!finalOutputURL) {
                NSString *tempDir = NSTemporaryDirectory();
                NSString *outputPath = [tempDir stringByAppendingFormat:@"video_%@.mp4", [[NSUUID UUID] UUIDString]];
                finalOutputURL = [NSURL fileURLWithPath:outputPath];
                shouldCleanup = YES;
            }

            // Read source framerate via ffprobe
            float sourceFramerate = [self probeFramerateForVideoAtURL:inputURL];

            // Build ffmpeg arguments
            NSMutableArray<NSString *> *args = [NSMutableArray array];
            [args addObject:@"-i"];
            [args addObject:inputURL.path];
            [args addObject:@"-c:v"];
            [args addObject:@"libx264"];
            [args addObject:@"-preset"];
            [args addObject:@"medium"];
            [args addObject:@"-c:a"];
            [args addObject:@"aac"];
            [args addObject:@"-movflags"];
            [args addObject:@"+faststart"];

            // Resolution and bitrate based on quality
            switch (quality) {
                case ATProtoVideoTranscoderQuality480p:
                    [args addObject:@"-vf"];
                    [args addObject:@"scale=640:480:force_original_aspect_ratio=decrease"];
                    [args addObject:@"-b:v"];
                    [args addObject:@"1M"];
                    break;
                case ATProtoVideoTranscoderQuality720p:
                    [args addObject:@"-vf"];
                    [args addObject:@"scale=1280:720:force_original_aspect_ratio=decrease"];
                    [args addObject:@"-b:v"];
                    [args addObject:@"2.5M"];
                    break;
                case ATProtoVideoTranscoderQuality1080p:
                    [args addObject:@"-vf"];
                    [args addObject:@"scale=1920:1080:force_original_aspect_ratio=decrease"];
                    [args addObject:@"-b:v"];
                    [args addObject:@"5M"];
                    break;
                case ATProtoVideoTranscoderQualityHEVC:
                    [args addObject:@"-c:v"];
                    [args replaceObjectAtIndex:args.count - 1 withObject:@"libx265"];
                    [args addObject:@"-vf"];
                    [args addObject:@"scale=1920:1080:force_original_aspect_ratio=decrease"];
                    [args addObject:@"-b:v"];
                    [args addObject:@"5M"];
                    break;
            }

            // Framerate handling: preserve source if <= 30 FPS, cap at 30 if higher
            if (sourceFramerate > 0 && sourceFramerate <= 30.0) {
                [args addObject:@"-r"];
                [args addObject:[NSString stringWithFormat:@"%.0f", sourceFramerate]];
            } else {
                [args addObject:@"-r"];
                [args addObject:@"30"];
            }

            [args addObject:@"-y"];
            [args addObject:finalOutputURL.path];

            NSTask *task = [[NSTask alloc] init];
            PDS_TASK_SET_EXECUTABLE(task, self.ffmpegPath);
            task.arguments = args;

            NSPipe *stderrPipe = [NSPipe pipe];
            task.standardError = stderrPipe;

            NSError *taskError = nil;
            BOOL launched = PDS_TASK_LAUNCH(task, &taskError);
            if (!launched) {
                if (shouldCleanup) {
                    [[NSFileManager defaultManager] removeItemAtURL:finalOutputURL error:nil];
                }
                NSError *err = [NSError errorWithDomain:FFmpegTranscoderErrorDomain
                                                   code:ATProtoVideoTranscoderErrorExportFailed
                                               userInfo:@{NSLocalizedDescriptionKey:
                                                              [NSString stringWithFormat:@"Failed to launch ffmpeg: %@", taskError.localizedDescription]}];
                if (completion) completion(nil, err);
                return;
            }

            [task waitUntilExit];
            int status = task.terminationStatus;

            if (status == 0) {
                if (progressBlock) progressBlock(1.0);
                if (completion) completion(finalOutputURL, nil);
            } else {
                if (shouldCleanup) {
                    [[NSFileManager defaultManager] removeItemAtURL:finalOutputURL error:nil];
                }
                NSData *stderrData = [stderrPipe.fileHandleForReading readDataToEndOfFile];
                NSString *stderrStr = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
                NSString *msg = [NSString stringWithFormat:@"ffmpeg exited with status %d: %@", status, stderrStr ?: @"(no stderr)"];
                PDS_LOG_ERROR(@"%@", msg);
                NSError *err = [NSError errorWithDomain:FFmpegTranscoderErrorDomain
                                                   code:ATProtoVideoTranscoderErrorExportFailed
                                               userInfo:@{NSLocalizedDescriptionKey: msg}];
                if (completion) completion(nil, err);
            }
        }
    });
}

- (void)cancelAllExports {
    // NSTask doesn't support cancellation from outside easily.
    // For production use, track active tasks and send SIGTERM.
}

- (float)probeFramerateForVideoAtURL:(NSURL *)videoURL {
    NSTask *task = [[NSTask alloc] init];
    PDS_TASK_SET_EXECUTABLE(task, self.ffprobePath);
    task.arguments = @[
        @"-v", @"error",
        @"-select_streams", @"v:0",
        @"-show_entries", @"stream=r_frame_rate",
        @"-of", @"default=noprint_wrappers=1:nokey=1",
        videoURL.path
    ];

    NSPipe *stdoutPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;

    NSError *taskError = nil;
    BOOL launched = PDS_TASK_LAUNCH(task, &taskError);
    if (!launched) {
        PDS_LOG_WARN(@"Failed to launch ffprobe: %@", taskError);
        return 0;
    }

    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        return 0;
    }

    NSData *data = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // ffprobe returns framerate as "N/D" (e.g., "24000/1001" for 23.976 FPS)
    NSArray *parts = [output componentsSeparatedByString:@"/"];
    if (parts.count == 2) {
        double numerator = [parts[0] doubleValue];
        double denominator = [parts[1] doubleValue];
        if (denominator > 0) {
            return (float)(numerator / denominator);
        }
    }

    // Try as a plain number
    float value = [output floatValue];
    return (value > 0) ? value : 0;
}

- (float)probeDurationForVideoAtURL:(NSURL *)videoURL {
    NSTask *task = [[NSTask alloc] init];
    PDS_TASK_SET_EXECUTABLE(task, self.ffprobePath);
    task.arguments = @[
        @"-v", @"error",
        @"-show_entries", @"format=duration",
        @"-of", @"default=noprint_wrappers=1:nokey=1",
        videoURL.path
    ];

    NSPipe *stdoutPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;

    NSError *taskError = nil;
    BOOL launched = PDS_TASK_LAUNCH(task, &taskError);
    if (!launched) {
        PDS_LOG_WARN(@"Failed to launch ffprobe: %@", taskError);
        return 0;
    }

    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        return 0;
    }

    NSData *data = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    float value = [output floatValue];
    return (value > 0) ? value : 0;
}

- (CGSize)probeDimensionsForVideoAtURL:(NSURL *)videoURL {
    NSTask *task = [[NSTask alloc] init];
    PDS_TASK_SET_EXECUTABLE(task, self.ffprobePath);
    task.arguments = @[
        @"-v", @"error",
        @"-select_streams", @"v:0",
        @"-show_entries", @"stream=width,height",
        @"-of", @"csv=s=x:p=0",
        videoURL.path
    ];

    NSPipe *stdoutPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;

    NSError *taskError = nil;
    BOOL launched = PDS_TASK_LAUNCH(task, &taskError);
    if (!launched) {
        PDS_LOG_WARN(@"Failed to launch ffprobe: %@", taskError);
        return CGSizeZero;
    }

    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        return CGSizeZero;
    }

    NSData *data = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // ffprobe returns "WIDTHxHEIGHT" (e.g., "1920x1080")
    NSArray *parts = [output componentsSeparatedByString:@"x"];
    if (parts.count == 2) {
        NSInteger width = [parts[0] integerValue];
        NSInteger height = [parts[1] integerValue];
        if (width > 0 && height > 0) {
            return CGSizeMake(width, height);
        }
    }

    return CGSizeZero;
}

@end
