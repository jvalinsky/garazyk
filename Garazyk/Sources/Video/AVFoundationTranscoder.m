#import "Video/AVFoundationTranscoder.h"
#import "Video/VideoTranscoder.h"
#import "Debug/PDSLogger.h"

#if TARGET_OS_MAC
#import <AVFoundation/AVFoundation.h>
#endif

NSString * const AVFoundationTranscoderErrorDomain = @"com.atproto.video.transcoder.avfoundation";

@implementation AVFoundationTranscoder

- (void)transcodeVideoAtURL:(NSURL *)inputURL
                  toQuality:(ATProtoVideoTranscoderQuality)quality
                  outputURL:(nullable NSURL *)outputURL
                   progress:(nullable void (^)(float))progressBlock
                 completion:(void (^)(NSURL *, NSError *))completion {

#if TARGET_OS_MAC
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

            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputURL options:nil];
            if (!asset) {
                NSError *err = [NSError errorWithDomain:AVFoundationTranscoderErrorDomain
                                                   code:ATProtoVideoTranscoderErrorAssetNotFound
                                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to load video asset"}];
                if (completion) completion(nil, err);
                return;
            }

            NSString *preset = [self presetForQuality:quality];
            NSArray *compatible = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];

            if (![compatible containsObject:preset]) {
                PDS_LOG_WARN(@"Preset %@ not compatible, falling back to HighestQuality", preset);
                preset = AVAssetExportPresetHighestQuality;
                if (![compatible containsObject:preset]) {
                    NSError *err = [NSError errorWithDomain:AVFoundationTranscoderErrorDomain
                                                       code:ATProtoVideoTranscoderErrorUnsupportedFormat
                                                   userInfo:@{NSLocalizedDescriptionKey: @"No compatible export preset found"}];
                    if (completion) completion(nil, err);
                    return;
                }
            }

            AVAssetExportSession *session = [AVAssetExportSession exportSessionWithAsset:asset presetName:preset];
            if (!session) {
                NSError *err = [NSError errorWithDomain:AVFoundationTranscoderErrorDomain
                                                   code:ATProtoVideoTranscoderErrorExportFailed
                                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to create export session"}];
                if (completion) completion(nil, err);
                return;
            }

            [[NSFileManager defaultManager] removeItemAtURL:finalOutputURL error:nil];

            session.outputURL = finalOutputURL;
            session.outputFileType = AVFileTypeMPEG4;
            session.shouldOptimizeForNetworkUse = YES;

            // Preserve source framerate for 24 FPS content (fixes judder)
            float sourceFramerate = 0;
            NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
            if (videoTracks.count > 0) {
                sourceFramerate = videoTracks.firstObject.nominalFrameRate;
            }

            if (sourceFramerate > 0 && sourceFramerate <= 30.0 && sourceFramerate != 30.0) {
                AVMutableVideoComposition *composition = [AVMutableVideoComposition videoComposition];
                composition.frameDuration = CMTimeMake(1, (int32_t)lroundf(sourceFramerate));
                composition.renderSize = videoTracks.firstObject.naturalSize;

                AVMutableVideoCompositionInstruction *instruction =
                    [AVMutableVideoCompositionInstruction videoCompositionInstruction];
                instruction.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);

                AVMutableVideoCompositionLayerInstruction *layerInstruction =
                    [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTracks.firstObject];
                instruction.layerInstructions = @[layerInstruction];

                composition.instructions = @[instruction];
                session.videoComposition = composition;
            }

            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
            dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
            dispatch_source_set_event_handler(timer, ^{
                if (progressBlock) {
                    progressBlock(session.progress);
                }
            });
            dispatch_resume(timer);

            [session exportAsynchronouslyWithCompletionHandler:^{
                dispatch_source_cancel(timer);

                if (session.status == AVAssetExportSessionStatusCompleted) {
                    if (completion) completion(finalOutputURL, nil);
                } else {
                    NSError *err = session.error ?: [NSError errorWithDomain:AVFoundationTranscoderErrorDomain
                                                                       code:ATProtoVideoTranscoderErrorExportFailed
                                                                   userInfo:@{NSLocalizedDescriptionKey: @"Export failed"}];
                    if (shouldCleanup) {
                        [[NSFileManager defaultManager] removeItemAtURL:finalOutputURL error:nil];
                    }
                    if (completion) completion(nil, err);
                }
            }];
        }
    });
#else
    NSError *err = [NSError errorWithDomain:AVFoundationTranscoderErrorDomain
                                        code:ATProtoVideoTranscoderErrorUnsupportedFormat
                                    userInfo:@{NSLocalizedDescriptionKey: @"AVFoundation not available on this platform"}];
    if (completion) completion(nil, err);
#endif
}

- (void)cancelAllExports {
    // No-op: AVAssetExportSession handles its own cancellation.
    // Individual sessions are not tracked here; the caller should
    // manage session lifecycle if cancellation is needed.
}

- (NSString *)presetForQuality:(ATProtoVideoTranscoderQuality)quality {
#if TARGET_OS_MAC
    switch (quality) {
        case ATProtoVideoTranscoderQuality480p:
            return AVAssetExportPreset640x480;
        case ATProtoVideoTranscoderQuality720p:
            return AVAssetExportPreset1280x720;
        case ATProtoVideoTranscoderQuality1080p:
            return AVAssetExportPreset1920x1080;
        case ATProtoVideoTranscoderQualityHEVC:
            return AVAssetExportPresetHEVCHighestQuality;
        default:
            return AVAssetExportPresetHighestQuality;
    }
#else
    return @"";
#endif
}

@end
