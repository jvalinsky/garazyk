// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/VideoThumbnailGenerator.h"
#import "Core/CID.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"

// Suppress -Wblock-capture-autoreleasing: the error out-parameter captured
// by the completion block is written before dispatch_semaphore_signal,
// and the caller waits on the semaphore, so the autorelease pool is valid.
#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

#ifdef LINUX
#define PDS_THUMB_TASK_SET_EXECUTABLE(task, path) task.launchPath = path
#define PDS_THUMB_TASK_LAUNCH(task, error) ([task launch], YES)
#else
#define PDS_THUMB_TASK_SET_EXECUTABLE(task, path) task.executableURL = [NSURL fileURLWithPath:path]
#define PDS_THUMB_TASK_LAUNCH(task, error) [task launchAndReturnError:error]
#endif

#if TARGET_OS_MAC
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <ImageIO/ImageIO.h>
#import <CoreServices/CoreServices.h>
#endif

NSString * const ATProtoVideoThumbnailErrorDomain = @"com.atproto.video.thumbnail";

@implementation ATProtoVideoThumbnailGenerator

+ (instancetype)sharedGenerator {
    static ATProtoVideoThumbnailGenerator *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ATProtoVideoThumbnailGenerator alloc] init];
    });
    return sharedInstance;
}

- (void)setBlobProvider:(id<PDSBlobProvider>)provider {
    _blobProvider = provider;
}

- (nullable NSData *)generateThumbnailAtTime:(NSTimeInterval)seconds
                              fromVideoURL:(NSURL *)videoURL
                                maxWidth:(NSInteger)maxWidth
                               maxHeight:(NSInteger)maxHeight
                                  error:(NSError **)error {

    __block NSData *result = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    [self generateThumbnailAtTime:seconds
                    fromVideoURL:videoURL
                      maxWidth:maxWidth
                     maxHeight:maxHeight
                   completion:^(NSData *thumbnailData, NSError *err) {
        result = thumbnailData;
        if (error) *error = err;
        dispatch_semaphore_signal(sema);
    }];

    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
    return result;
}

- (void)generateThumbnailAtTime:(NSTimeInterval)seconds
                  fromVideoURL:(NSURL *)videoURL
                    maxWidth:(NSInteger)maxWidth
                   maxHeight:(NSInteger)maxHeight
                 completion:(void (^)(NSData *, NSError *))completion {

#if TARGET_OS_MAC
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoURL options:nil];
            if (!asset) {
                NSError *err = [NSError errorWithDomain:ATProtoVideoThumbnailErrorDomain
                                                   code:ATProtoVideoThumbnailErrorAssetNotFound
                                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to load video asset"}];
                if (completion) completion(nil, err);
                return;
            }

            AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
            generator.appliesPreferredTrackTransform = YES;
            generator.maximumSize = CGSizeMake(maxWidth, maxHeight);
            generator.requestedTimeToleranceBefore = kCMTimeZero;
            generator.requestedTimeToleranceAfter = kCMTimeZero;

            CMTime time = CMTimeMakeWithSeconds(seconds, 600);
            NSError *genError = nil;
            CGImageRef imgRef = [generator copyCGImageAtTime:time actualTime:NULL error:&genError];

            if (!imgRef) {
                NSError *err = genError ?: [NSError errorWithDomain:ATProtoVideoThumbnailErrorDomain
                                                                 code:ATProtoVideoThumbnailErrorGenerationFailed
                                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate thumbnail"}];
                if (completion) completion(nil, err);
                return;
            }

            NSData *jpegData = [self jpegDataFromCGImage:imgRef compression:0.8];
            CGImageRelease(imgRef);

            if (!jpegData) {
                NSError *err = [NSError errorWithDomain:ATProtoVideoThumbnailErrorDomain
                                                   code:ATProtoVideoThumbnailErrorGenerationFailed
                                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode thumbnail as JPEG"}];
                if (completion) completion(nil, err);
                return;
            }

            if (completion) completion(jpegData, nil);
        }
    });
#else
    // FFmpeg-based thumbnail extraction for Linux/GNUstep
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            NSString *tempDir = NSTemporaryDirectory();
            NSString *outputPath = [tempDir stringByAppendingFormat:@"thumb_%@.jpg", [[NSUUID UUID] UUIDString]];
            NSURL *outputURL = [NSURL fileURLWithPath:outputPath];

            // ffmpeg -ss <time> -i <input> -frames:v 1 -f image2 -q:v 2 <output>
            NSTask *task = [[NSTask alloc] init];
            PDS_THUMB_TASK_SET_EXECUTABLE(task, @"ffmpeg");
            task.arguments = @[
                @"-ss", [NSString stringWithFormat:@"%.1f", seconds],
                @"-i", videoURL.path,
                @"-frames:v", @"1",
                @"-f", @"image2",
                @"-q:v", @"2",
                @"-y",
                outputPath
            ];

            NSPipe *stderrPipe = [NSPipe pipe];
            task.standardError = stderrPipe;

            NSError *taskError = nil;
            BOOL launched = PDS_THUMB_TASK_LAUNCH(task, &taskError);
            if (!launched) {
                NSError *err = [NSError errorWithDomain:ATProtoVideoThumbnailErrorDomain
                                                   code:ATProtoVideoThumbnailErrorGenerationFailed
                                               userInfo:@{NSLocalizedDescriptionKey:
                                                              [NSString stringWithFormat:@"Failed to launch ffmpeg: %@", taskError.localizedDescription]}];
                if (completion) completion(nil, err);
                return;
            }

            [task waitUntilExit];

            if (task.terminationStatus != 0) {
                [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
                NSData *stderrData = [stderrPipe.fileHandleForReading readDataToEndOfFile];
                NSString *stderrStr = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
                NSString *msg = [NSString stringWithFormat:@"ffmpeg thumbnail extraction failed: %@", stderrStr ?: @"(unknown)"];
                GZ_LOG_ERROR(@"%@", msg);
                NSError *err = [NSError errorWithDomain:ATProtoVideoThumbnailErrorDomain
                                                   code:ATProtoVideoThumbnailErrorGenerationFailed
                                               userInfo:@{NSLocalizedDescriptionKey: msg}];
                if (completion) completion(nil, err);
                return;
            }

            NSData *jpegData = [NSData dataWithContentsOfURL:outputURL];
            [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];

            if (!jpegData) {
                NSError *err = [NSError errorWithDomain:ATProtoVideoThumbnailErrorDomain
                                                   code:ATProtoVideoThumbnailErrorGenerationFailed
                                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to read thumbnail output"}];
                if (completion) completion(nil, err);
                return;
            }

            if (completion) completion(jpegData, nil);
        }
    });
#endif
}

#if TARGET_OS_MAC
- (nullable NSData *)jpegDataFromCGImage:(CGImageRef)image compression:(float)quality {
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, kUTTypeJPEG, 1, NULL);
    if (!dest) return nil;

    NSDictionary *props = @{(__bridge id)kCGImageDestinationLossyCompressionQuality: @(quality)};
    CGImageDestinationAddImage(dest, image, (__bridge CFDictionaryRef)props);
    BOOL success = CGImageDestinationFinalize(dest);
    CFRelease(dest);

    return success ? data : nil;
}
#endif

- (nullable CID *)storeThumbnailData:(NSData *)thumbnailData
                             forJob:(NSString *)jobId
                             error:(NSError **)error {
    if (!self.blobProvider) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoVideoThumbnailErrorDomain
                                         code:ATProtoVideoThumbnailErrorWriteFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Blob provider not configured"}];
        }
        return nil;
    }

    CID *cid = [CID sha256:thumbnailData];
    BOOL stored = [self.blobProvider storeBlobData:thumbnailData forCID:cid error:error];
    return stored ? cid : nil;
}

@end
