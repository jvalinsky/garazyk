#import "Media/PDSVideoTranscoder.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"
#import <AVFoundation/AVFoundation.h>

NSString * const PDSVideoTranscoderErrorDomain = @"com.atproto.pds.video.transcoder";

@interface PDSVideoTranscoder ()
@property (nonatomic, strong) NSMutableSet *activeExports;
@end

@implementation PDSVideoTranscoder {
    dispatch_queue_t _exportQueue;
}

+ (instancetype)sharedTranscoder {
    static PDSVideoTranscoder *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PDSVideoTranscoder alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _activeExports = [NSMutableSet set];
        _exportQueue = dispatch_queue_create("com.atproto.pds.video.transcoder", DISPATCH_QUEUE_SERIAL);
        _maxConcurrentExports = 2;
    }
    return self;
}

- (void)setBlobProvider:(id<PDSBlobProvider>)provider {
    _blobProvider = provider;
}

- (nullable NSData *)transcodeVideoAtURL:(NSURL *)inputURL
                       toQuality:(PDSVideoTranscoderQuality)quality
                            error:(NSError **)error {
    __block NSData *result = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    [self transcodeVideoAtURL:inputURL
                    toQuality:quality
                    outputURL:nil
                    progress:nil
                  completion:^(NSURL *outputURL, NSError *err) {
        if (outputURL) {
            result = [NSData dataWithContentsOfURL:outputURL];
        }
        if (error) *error = err;
        dispatch_semaphore_signal(sema);
    }];

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return result;
}

- (void)transcodeVideoAtURL:(NSURL *)inputURL
                  toQuality:(PDSVideoTranscoderQuality)quality
                  outputURL:(NSURL *)outputURL
                  progress:(void (^)(float))progressBlock
                completion:(void (^)(NSURL *, NSError *))completion {

    dispatch_async(_exportQueue, ^{
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
                NSError *err = [NSError errorWithDomain:PDSVideoTranscoderErrorDomain
                                                   code:PDSVideoTranscoderErrorAssetNotFound
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
                    NSError *err = [NSError errorWithDomain:PDSVideoTranscoderErrorDomain
                                                       code:PDSVideoTranscoderErrorUnsupportedFormat
                                                   userInfo:@{NSLocalizedDescriptionKey: @"No compatible export preset found"}];
                    if (completion) completion(nil, err);
                    return;
                }
            }

            AVAssetExportSession *session = [AVAssetExportSession exportSessionWithAsset:asset presetName:preset];
            if (!session) {
                NSError *err = [NSError errorWithDomain:PDSVideoTranscoderErrorDomain
                                                   code:PDSVideoTranscoderErrorExportFailed
                                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to create export session"}];
                if (completion) completion(nil, err);
                return;
            }

            [[NSFileManager defaultManager] removeItemAtURL:finalOutputURL error:nil];

            session.outputURL = finalOutputURL;
            session.outputFileType = AVFileTypeMPEG4;
            session.shouldOptimizeForNetworkUse = YES;

            __weak typeof(self) weakSelf = self;
            @synchronized(self.activeExports) {
                [self.activeExports addObject:finalOutputURL];
            }

            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _exportQueue);
            dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
            dispatch_source_set_event_handler(timer, ^{
                if (progressBlock) {
                    progressBlock(session.progress);
                }
            });
            dispatch_resume(timer);

            [session exportAsynchronouslyWithCompletionHandler:^{
                dispatch_source_cancel(timer);

                @synchronized(weakSelf.activeExports) {
                    [weakSelf.activeExports removeObject:finalOutputURL];
                }

                if (session.status == AVAssetExportSessionStatusCompleted) {
                    if (completion) completion(finalOutputURL, nil);
                } else {
                    NSError *err = session.error ?: [NSError errorWithDomain:PDSVideoTranscoderErrorDomain
                                                                       code:PDSVideoTranscoderErrorExportFailed
                                                                   userInfo:@{NSLocalizedDescriptionKey: @"Export failed"}];
                    if (shouldCleanup) {
                        [[NSFileManager defaultManager] removeItemAtURL:finalOutputURL error:nil];
                    }
                    if (completion) completion(nil, err);
                }
            }];
        }
    });
}

- (void)cancelAllExports {
    @synchronized(self.activeExports) {
        [self.activeExports removeAllObjects];
    }
}

- (NSString *)presetForQuality:(PDSVideoTranscoderQuality)quality {
    switch (quality) {
        case PDSVideoTranscoderQuality480p:
            return AVAssetExportPreset640x480;
        case PDSVideoTranscoderQuality720p:
            return AVAssetExportPreset1280x720;
        case PDSVideoTranscoderQuality1080p:
            return AVAssetExportPreset1920x1080;
        case PDSVideoTranscoderQualityHEVC:
            return AVAssetExportPresetHEVCHighestQuality;
        default:
            return AVAssetExportPresetHighestQuality;
    }
}

@end
