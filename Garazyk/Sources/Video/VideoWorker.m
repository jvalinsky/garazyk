#import "Video/VideoWorker.h"
#import "Video/VideoThumbnailGenerator.h"
#import "Video/VideoTranscoder.h"
#import "Video/VideoTranscoderBackend.h"
#import "Blob/PDSBlobProvider.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"

#if TARGET_OS_MAC
#import <AVFoundation/AVFoundation.h>
#else
#import "Video/FFmpegTranscoder.h"
#endif

NSString * const ATProtoVideoWorkerErrorDomain = @"com.atproto.video.worker";

@interface ATProtoVideoWorker ()
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) NSMutableSet<NSString *> *processingJobIds;
@end

@implementation ATProtoVideoWorker {
    dispatch_queue_t _workerQueue;
    dispatch_queue_t _stateQueue;
    dispatch_source_t _pollTimer;
}

+ (instancetype)sharedWorker {
    static ATProtoVideoWorker *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ATProtoVideoWorker alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = NO;
        _pollInterval = 5.0;
        _maxConcurrentJobs = 2;
        _workerQueue = dispatch_queue_create("com.atproto.video.worker", DISPATCH_QUEUE_SERIAL);
        _stateQueue = dispatch_queue_create("com.atproto.video.state", DISPATCH_QUEUE_SERIAL);
        _processingJobIds = [NSMutableSet set];
    }
    return self;
}

- (void)setBlobProvider:(id<PDSBlobProvider>)provider {
    _blobProvider = provider;
    [ATProtoVideoThumbnailGenerator sharedGenerator].blobProvider = provider;
    [ATProtoVideoTranscoder sharedTranscoder].blobProvider = provider;
}

- (void)start {
    if (self.enabled) {
        return;
    }

    self.enabled = YES;
    PDS_LOG_INFO(@"Video worker starting");

    [self startPollTimer];
}

- (void)stop {
    if (!self.isRunning) {
        return;
    }

    self.enabled = NO;

    if (_pollTimer) {
        dispatch_source_cancel(_pollTimer);
        _pollTimer = nil;
    }

    [[ATProtoVideoTranscoder sharedTranscoder] cancelAllExports];

    PDS_LOG_INFO(@"Video worker stopped");
}

- (void)startPollTimer {
    if (_pollTimer) {
        dispatch_source_cancel(_pollTimer);
    }

    _pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                          0, 0, _workerQueue);

    dispatch_source_set_timer(_pollTimer,
                           dispatch_time(DISPATCH_TIME_NOW, 0),
                           (uint64_t)(self.pollInterval * NSEC_PER_SEC),
                           (1ull * NSEC_PER_SEC));

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_pollTimer, ^{
        [weakSelf processPendingJobs];
    });

    dispatch_resume(_pollTimer);
    self.isRunning = YES;
}

- (void)processPendingJobs {
    if (!self.enabled) {
        return;
    }

    @synchronized(self.processingJobIds) {
        if (self.processingJobIds.count >= self.maxConcurrentJobs) {
            return;
        }
    }

    if (!self.jobStore) {
        return;
    }

    NSInteger availableSlots = 0;
    @synchronized(self.processingJobIds) {
        availableSlots = self.maxConcurrentJobs - self.processingJobIds.count;
    }
    NSError *error = nil;
    NSArray<NSDictionary *> *pendingJobs = [self.jobStore queryPendingJobsWithLimit:availableSlots
                                                                               error:&error];

    if (error || pendingJobs.count == 0) {
        return;
    }

    for (NSDictionary *job in pendingJobs) {
        __block BOOL shouldBreak = NO;
        dispatch_sync(_stateQueue, ^{
            if (self.processingJobIds.count >= self.maxConcurrentJobs) {
                shouldBreak = YES;
                return;
            }

            NSString *jobId = job[@"job_id"];
            if (![self.processingJobIds containsObject:jobId]) {
                [self.processingJobIds addObject:jobId];
                [self processJob:jobId];
            }
        });
        if (shouldBreak) break;
    }
}

- (void)processJob:(NSString *)jobId {
    dispatch_async(_workerQueue, ^{
        @autoreleasepool {
            PDS_LOG_INFO(@"Processing video job: %@", jobId);

            [self updateJobProgress:jobId progress:10 message:@"Loading video"];

            NSError *dbError = nil;
            NSDictionary *job = [self.jobStore getVideoJobById:jobId error:&dbError];

            if (!job) {
                PDS_LOG_ERROR(@"Job not found: %@", jobId);
                [self failJob:jobId error:dbError ?: [NSError errorWithDomain:ATProtoVideoWorkerErrorDomain
                                                                       code:ATProtoVideoWorkerErrorDatabaseUnavailable
                                                                   userInfo:@{NSLocalizedDescriptionKey: @"Job not found"}]];
                return;
            }

            NSString *blobCid = job[@"blob_cid"];
            if (!blobCid || [blobCid isEqual:[NSNull null]]) {
                [self failJob:jobId error:[NSError errorWithDomain:ATProtoVideoWorkerErrorDomain
                                                          code:ATProtoVideoWorkerErrorProcessingFailed
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Missing blob CID"}]];
                return;
            }

            NSError *blobError = nil;
            CID *cid = [CID cidFromString:blobCid];
            if (!cid) {
                [self failJob:jobId error:blobError ?: [NSError errorWithDomain:ATProtoVideoWorkerErrorDomain
                                                                           code:ATProtoVideoWorkerErrorProcessingFailed
                                                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid blob CID"}]];
                return;
            }

            NSData *videoData = [self.blobProvider retrieveBlobDataForCID:cid error:&blobError];
            if (!videoData) {
                PDS_LOG_ERROR(@"Failed to retrieve blob %@: %@", blobCid, blobError);
                [self failJob:jobId error:blobError ?: [NSError errorWithDomain:ATProtoVideoWorkerErrorDomain
                                                                           code:ATProtoVideoWorkerErrorBlobProviderUnavailable
                                                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to retrieve video blob"}]];
                return;
            }

            [self updateJobState:jobId state:@"PROCESSING" progress:15 message:@"Writing video to temp file"];

            NSString *tempDir = NSTemporaryDirectory();
            NSString *tempInputPath = [tempDir stringByAppendingFormat:@"video_in_%@.mp4", jobId];
            NSString *tempOutputPath = [tempDir stringByAppendingFormat:@"video_out_%@.mp4", jobId];

            NSURL *inputURL = [NSURL fileURLWithPath:tempInputPath];
            NSURL *outputURL = [NSURL fileURLWithPath:tempOutputPath];

            BOOL written = [videoData writeToURL:inputURL options:NSDataWritingAtomic error:&blobError];
            if (!written) {
                PDS_LOG_ERROR(@"Failed to write temp file: %@", blobError);
                [self failJob:jobId error:blobError];
                return;
            }

            [self updateJobProgress:jobId progress:20 message:@"Inspecting video metadata"];

#if TARGET_OS_MAC
            // Extract video metadata (aspect ratio, duration)
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputURL options:nil];
            if (asset) {
                NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
                if (videoTracks.count > 0) {
                    AVAssetTrack *videoTrack = videoTracks.firstObject;
                    CGSize naturalSize = videoTrack.naturalSize;
                    if (naturalSize.width > 0 && naturalSize.height > 0) {
                        [self.jobStore updateVideoJobDimensions:jobId
                                                          width:(NSInteger)naturalSize.width
                                                         height:(NSInteger)naturalSize.height
                                                          error:nil];
                    }
                }

                Float64 durationSeconds = CMTimeGetSeconds(asset.duration);
                if (durationSeconds > 0) {
                    [self.jobStore updateVideoJobDuration:jobId
                                                 seconds:(NSInteger)round(durationSeconds)
                                                    error:nil];

                    // Validate duration limits (1s–180s)
                    if (durationSeconds < 1.0) {
                        PDS_LOG_ERROR(@"Video too short (%.1fs) for job %@", durationSeconds, jobId);
                        [[NSFileManager defaultManager] removeItemAtURL:inputURL error:nil];
                        [self failJob:jobId error:[NSError errorWithDomain:ATProtoVideoWorkerErrorDomain
                                                                    code:ATProtoVideoWorkerErrorProcessingFailed
                                                                userInfo:@{NSLocalizedDescriptionKey: @"Video must be at least 1 second long"}]];
                        return;
                    }
                    if (durationSeconds > 180.0) {
                        PDS_LOG_ERROR(@"Video too long (%.1fs) for job %@", durationSeconds, jobId);
                        [[NSFileManager defaultManager] removeItemAtURL:inputURL error:nil];
                        [self failJob:jobId error:[NSError errorWithDomain:ATProtoVideoWorkerErrorDomain
                                                                    code:ATProtoVideoWorkerErrorProcessingFailed
                                                                userInfo:@{NSLocalizedDescriptionKey: @"Video must be at most 180 seconds long"}]];
                        return;
                    }
                }
            }
#else
            // FFmpeg-based metadata extraction for Linux/GNUstep
            FFmpegTranscoder *probe = [[FFmpegTranscoder alloc] initWithFFmpegPath:nil ffprobePath:nil];

            CGSize dimensions = [probe probeDimensionsForVideoAtURL:inputURL];
            if (dimensions.width > 0 && dimensions.height > 0) {
                [self.jobStore updateVideoJobDimensions:jobId
                                                  width:(NSInteger)dimensions.width
                                                 height:(NSInteger)dimensions.height
                                                  error:nil];
            }

            float durationSeconds = [probe probeDurationForVideoAtURL:inputURL];
            if (durationSeconds > 0) {
                [self.jobStore updateVideoJobDuration:jobId
                                             seconds:(NSInteger)roundf(durationSeconds)
                                                error:nil];

                // Validate duration limits (1s–180s)
                if (durationSeconds < 1.0) {
                    PDS_LOG_ERROR(@"Video too short (%.1fs) for job %@", durationSeconds, jobId);
                    [[NSFileManager defaultManager] removeItemAtURL:inputURL error:nil];
                    [self failJob:jobId error:[NSError errorWithDomain:ATProtoVideoWorkerErrorDomain
                                                                code:ATProtoVideoWorkerErrorProcessingFailed
                                                            userInfo:@{NSLocalizedDescriptionKey: @"Video must be at least 1 second long"}]];
                    return;
                }
                if (durationSeconds > 180.0) {
                    PDS_LOG_ERROR(@"Video too long (%.1fs) for job %@", durationSeconds, jobId);
                    [[NSFileManager defaultManager] removeItemAtURL:inputURL error:nil];
                    [self failJob:jobId error:[NSError errorWithDomain:ATProtoVideoWorkerErrorDomain
                                                                code:ATProtoVideoWorkerErrorProcessingFailed
                                                            userInfo:@{NSLocalizedDescriptionKey: @"Video must be at most 180 seconds long"}]];
                    return;
                }
            }
#endif

            [self updateJobProgress:jobId progress:25 message:@"Transcoding video"];

            [[ATProtoVideoTranscoder sharedTranscoder] transcodeVideoAtURL:inputURL
                                                              toQuality:ATProtoVideoTranscoderQuality720p
                                                              outputURL:outputURL
                                                              progress:^(float progress) {
                NSInteger p = 20 + (NSInteger)(progress * 40);
                [self updateJobProgress:jobId progress:p message:@"Transcoding video"];
            }
                                                            completion:^(NSURL *transcodedURL, NSError *transcodeError) {

                if (!transcodedURL) {
                    PDS_LOG_ERROR(@"Transcoding failed for job %@: %@", jobId, transcodeError);
                    [[NSFileManager defaultManager] removeItemAtURL:inputURL error:nil];
                    [self handleJobFailure:jobId error:transcodeError];
                    return;
                }

                [self updateJobProgress:jobId progress:65 message:@"Generating thumbnail"];

                [[ATProtoVideoThumbnailGenerator sharedGenerator] generateThumbnailAtTime:1.0
                                                                       fromVideoURL:transcodedURL
                                                                         maxWidth:640
                                                                        maxHeight:360
                                                                      completion:^(NSData *thumbnailData, NSError *thumbError) {

                    CID *thumbnailCid = nil;
                    if (thumbnailData) {
                        thumbnailCid = [[ATProtoVideoThumbnailGenerator sharedGenerator] storeThumbnailData:thumbnailData
                                                                                                forJob:jobId
                                                                                                error:nil];
                    } else {
                        PDS_LOG_WARN(@"Thumbnail generation failed for job %@: %@", jobId, thumbError);
                    }

                    [self updateJobProgress:jobId progress:80 message:@"Storing processed video"];

                    NSError *storeError = nil;
                    NSData *processedData = [NSData dataWithContentsOfURL:transcodedURL];
                    CID *processedCid = nil;

                    if (processedData) {
                        // Check 50MB output limit
                        if (processedData.length > 50 * 1024 * 1024) {
                            PDS_LOG_ERROR(@"Transcoded video exceeds 50MB limit for job %@", jobId);
                            [[NSFileManager defaultManager] removeItemAtURL:inputURL error:nil];
                            [[NSFileManager defaultManager] removeItemAtURL:transcodedURL error:nil];
                            [self failJob:jobId error:[NSError errorWithDomain:ATProtoVideoWorkerErrorDomain
                                                                          code:ATProtoVideoWorkerErrorProcessingFailed
                                                                      userInfo:@{NSLocalizedDescriptionKey: @"Transcoded video exceeds 50MB limit"}]];
                            return;
                        }

                        if (self.blobUploader) {
                            // Upload via the blob uploader protocol (remote or local)
                            NSString *serviceToken = job[@"service_auth_token"];
                            NSDictionary *uploadResult = [self.blobUploader uploadBlob:processedData
                                                                               mimeType:@"video/mp4"
                                                                            serviceAuth:serviceToken
                                                                                  error:&storeError];
                            if (uploadResult) {
                                processedCid = [CID cidFromString:uploadResult[@"cid"]];
                            }
                        } else if (self.blobProvider) {
                            // Direct blob store (legacy in-process mode)
                            processedCid = [CID sha256:processedData];
                            [self.blobProvider storeBlobData:processedData forCID:processedCid error:&storeError];
                        }
                    }

                    [[NSFileManager defaultManager] removeItemAtURL:inputURL error:nil];
                    [[NSFileManager defaultManager] removeItemAtURL:transcodedURL error:nil];

                    if (processedCid) {
                        [self updateJobProgress:jobId progress:90 message:@"Updating job record"];

                        BOOL updated = [self.jobStore updateVideoJobResults:jobId
                                                         processedBlobCid:processedCid.stringValue
                                                        thumbnailBlobCid:thumbnailCid.stringValue
                                                                   error:&storeError];

                        if (updated) {
                            [self completeJob:jobId];
                        } else {
                            PDS_LOG_ERROR(@"Failed to update job results: %@", storeError);
                            [self handleJobFailure:jobId error:storeError];
                        }
                    } else {
                        [self handleJobFailure:jobId error:storeError ?: [NSError errorWithDomain:ATProtoVideoWorkerErrorDomain
                                                                                         code:ATProtoVideoWorkerErrorProcessingFailed
                                                                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to store processed video"}]];
                    }
            }];
            }];
        }
    });
}

- (void)handleJobFailure:(NSString *)jobId error:(NSError *)error {
    NSError *dbError = nil;
    NSDictionary *job = [self.jobStore getVideoJobById:jobId error:&dbError];
    NSInteger retryCount = [job[@"retry_count"] integerValue];

    if (retryCount < 3) {
        PDS_LOG_WARN(@"Job %@ failed, retrying (%ld/3): %@", jobId, (long)retryCount + 1, error);
        [self.jobStore incrementVideoJobRetry:jobId error:nil];
        @synchronized(self.processingJobIds) {
            [self.processingJobIds removeObject:jobId];
        }
    } else {
        PDS_LOG_ERROR(@"Job %@ failed permanently after %ld retries: %@", jobId, (long)retryCount, error);
        [self failJob:jobId error:error];
    }
}

- (void)updateJobState:(NSString *)jobId
                 state:(NSString *)state
              progress:(NSInteger)progress
               message:(NSString *)message {
    [self.jobStore updateVideoJobState:jobId
                                 state:state
                              progress:@(progress)
                               message:message
                                 error:nil];
}

- (void)updateJobProgress:(NSString *)jobId
                progress:(NSInteger)progress
                 message:(NSString *)message {
    [self.jobStore updateVideoJobState:jobId
                                 state:@"PROCESSING"
                              progress:@(progress)
                               message:message
                                 error:nil];
}

- (void)completeJob:(NSString *)jobId {
    [self updateJobState:jobId state:@"COMPLETED" progress:100 message:@"Processing complete"];

    dispatch_sync(_stateQueue, ^{
        [self.processingJobIds removeObject:jobId];
    });

    PDS_LOG_INFO(@"Video job completed: %@", jobId);
}

- (void)failJob:(NSString *)jobId error:(NSError *)error {
    NSString *errorMsg = error.localizedDescription ?: @"Unknown error";
    [self.jobStore updateVideoJobState:jobId
                                 state:@"FAILED"
                              progress:@0
                               message:errorMsg
                                 error:nil];

    dispatch_sync(_stateQueue, ^{
        [self.processingJobIds removeObject:jobId];
    });

    PDS_LOG_ERROR(@"Video job failed: %@ - %@", jobId, error);
}

@end
