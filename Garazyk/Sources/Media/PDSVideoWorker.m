#import "Media/PDSVideoWorker.h"
#import "Media/PDSVideoThumbnailGenerator.h"
#import "Media/PDSVideoTranscoder.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Blob/PDSBlobProvider.h"
#import "Debug/PDSLogger.h"
#import <AVFoundation/AVFoundation.h>

NSString * const PDSVideoWorkerErrorDomain = @"com.atproto.pds.video.worker";

@interface PDSVideoWorker ()
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) NSMutableSet<NSString *> *processingJobIds;
@end

@implementation PDSVideoWorker {
    dispatch_queue_t _workerQueue;
    dispatch_source_t _pollTimer;
}

+ (instancetype)sharedWorker {
    static PDSVideoWorker *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PDSVideoWorker alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = NO;
        _pollInterval = 5.0;
        _maxConcurrentJobs = 2;
        _workerQueue = dispatch_queue_create("com.atproto.pds.video.worker", DISPATCH_QUEUE_SERIAL);
        _processingJobIds = [NSMutableSet set];
    }
    return self;
}

- (void)setBlobProvider:(id<PDSBlobProvider>)provider {
    _blobProvider = provider;
    [PDSVideoThumbnailGenerator sharedGenerator].blobProvider = provider;
    [PDSVideoTranscoder sharedTranscoder].blobProvider = provider;
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

    [[PDSVideoTranscoder sharedTranscoder] cancelAllExports];

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

    PDSDatabase *database = [self.serviceDatabases serviceDatabaseWithError:nil];
    if (!database || !database.isOpen) {
        return;
    }

    NSError *error = nil;
    NSArray<NSDictionary *> *pendingJobs = [self queryPendingJobsWithLimit:self.maxConcurrentJobs - self.processingJobIds.count
                                                               error:&error];

    if (error || pendingJobs.count == 0) {
        return;
    }

    for (NSDictionary *job in pendingJobs) {
        @synchronized(self.processingJobIds) {
            if (self.processingJobIds.count >= self.maxConcurrentJobs) {
                break;
            }

            NSString *jobId = job[@"job_id"];
            if (![self.processingJobIds containsObject:jobId]) {
                [self.processingJobIds addObject:jobId];
                [self processJob:jobId];
            }
        }
    }
}

- (NSArray<NSDictionary *> *)queryPendingJobsWithLimit:(NSInteger)limit error:(NSError **)error {
    PDSDatabase *database = [self.serviceDatabases serviceDatabaseWithError:error];
    if (!database) return @[];
    NSString *sql = @"SELECT * FROM video_jobs WHERE state = 'PENDING' ORDER BY created_at ASC LIMIT ?";
    return [database executeParameterizedQuery:sql params:@[@(limit)] error:error];
}

- (void)processJob:(NSString *)jobId {
    dispatch_async(_workerQueue, ^{
        @autoreleasepool {
            PDS_LOG_INFO(@"Processing video job: %@", jobId);

            [self updateJobProgress:jobId progress:10 message:@"Loading video"];

            PDSDatabase *database = [self.serviceDatabases serviceDatabaseWithError:nil];
            NSError *dbError = nil;
            NSDictionary *job = [database getVideoJobById:jobId error:&dbError];

            if (!job) {
                PDS_LOG_ERROR(@"Job not found: %@", jobId);
                [self failJob:jobId error:dbError ?: [NSError errorWithDomain:PDSVideoWorkerErrorDomain
                                                                       code:PDSVideoWorkerErrorDatabaseUnavailable
                                                                   userInfo:@{NSLocalizedDescriptionKey: @"Job not found"}]];
                return;
            }

            NSString *blobCid = job[@"blob_cid"];
            if (!blobCid || [blobCid isEqual:[NSNull null]]) {
                [self failJob:jobId error:[NSError errorWithDomain:PDSVideoWorkerErrorDomain
                                                          code:PDSVideoWorkerErrorProcessingFailed
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Missing blob CID"}]];
                return;
            }

            NSError *blobError = nil;
            CID *cid = [CID cidFromString:blobCid];
            if (!cid) {
                [self failJob:jobId error:blobError ?: [NSError errorWithDomain:PDSVideoWorkerErrorDomain
                                                                           code:PDSVideoWorkerErrorProcessingFailed
                                                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid blob CID"}]];
                return;
            }
            NSData *videoData = [self.blobProvider retrieveBlobDataForCID:cid error:&blobError];
            if (!videoData) {
                PDS_LOG_ERROR(@"Failed to retrieve blob %@: %@", blobCid, blobError);
                [self failJob:jobId error:blobError ?: [NSError errorWithDomain:PDSVideoWorkerErrorDomain
                                                                           code:PDSVideoWorkerErrorBlobProviderUnavailable
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

            [self updateJobProgress:jobId progress:20 message:@"Transcoding video"];

            [[PDSVideoTranscoder sharedTranscoder] transcodeVideoAtURL:inputURL
                                                              toQuality:PDSVideoTranscoderQuality720p
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

                [[PDSVideoThumbnailGenerator sharedGenerator] generateThumbnailAtTime:1.0
                                                                       fromVideoURL:transcodedURL
                                                                         maxWidth:640
                                                                        maxHeight:360
                                                                      completion:^(NSData *thumbnailData, NSError *thumbError) {

                    CID *thumbnailCid = nil;
                    if (thumbnailData) {
                        thumbnailCid = [[PDSVideoThumbnailGenerator sharedGenerator] storeThumbnailData:thumbnailData
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
                        processedCid = [CID sha256:processedData];
                        [self.blobProvider storeBlobData:processedData forCID:processedCid error:&storeError];
                    }

                    [[NSFileManager defaultManager] removeItemAtURL:inputURL error:nil];
                    [[NSFileManager defaultManager] removeItemAtURL:transcodedURL error:nil];

                    if (processedCid) {
                        [self updateJobProgress:jobId progress:90 message:@"Updating job record"];

                        BOOL updated = [database updateVideoJobResults:jobId
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
                    [self handleJobFailure:jobId error:storeError ?: [NSError errorWithDomain:PDSVideoWorkerErrorDomain
                                                                                     code:PDSVideoWorkerErrorProcessingFailed
                                                                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to store processed video"}]];
                }
            }];
            }];
        }
    });
}

- (void)handleJobFailure:(NSString *)jobId error:(NSError *)error {
    PDSDatabase *database = [self.serviceDatabases serviceDatabaseWithError:nil];
    NSDictionary *job = [database getVideoJobById:jobId error:nil];
    NSInteger retryCount = [job[@"retry_count"] integerValue];

    if (retryCount < 3) {
        PDS_LOG_WARN(@"Job %@ failed, retrying (%ld/3): %@", jobId, (long)retryCount + 1, error);
        [database incrementVideoJobRetry:jobId error:nil];
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
    PDSDatabase *database = [self.serviceDatabases serviceDatabaseWithError:nil];
    [database updateVideoJobState:jobId
                             state:state
                          progress:@(progress)
                           message:message
                             error:nil];
}

- (void)updateJobProgress:(NSString *)jobId
                progress:(NSInteger)progress
                 message:(NSString *)message {
    PDSDatabase *database = [self.serviceDatabases serviceDatabaseWithError:nil];
    [database updateVideoJobState:jobId
                             state:@"PROCESSING"
                          progress:@(progress)
                           message:message
                             error:nil];
}

- (void)completeJob:(NSString *)jobId {
    [self updateJobState:jobId state:@"COMPLETED" progress:100 message:@"Processing complete"];

    @synchronized(self.processingJobIds) {
        [self.processingJobIds removeObject:jobId];
    }

    PDS_LOG_INFO(@"Video job completed: %@", jobId);
}

- (void)failJob:(NSString *)jobId error:(NSError *)error {
    PDSDatabase *database = [self.serviceDatabases serviceDatabaseWithError:nil];
    NSString *errorMsg = error.localizedDescription ?: @"Unknown error";
    [database updateVideoJobState:jobId
                             state:@"FAILED"
                          progress:@0
                           message:errorMsg
                             error:nil];

    @synchronized(self.processingJobIds) {
        [self.processingJobIds removeObject:jobId];
    }

    PDS_LOG_ERROR(@"Video job failed: %@ - %@", jobId, error);
}

@end
