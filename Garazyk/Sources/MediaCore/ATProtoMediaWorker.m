// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoMediaWorker.h"
#import "Blob/PDSBlobProvider.h"
#import "Core/CID.h"
#import "Debug/GZLogger.h"

NSString * const ATProtoMediaWorkerErrorDomain = @"com.atproto.mediacore.worker";

@interface ATProtoMediaWorker ()
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) NSMutableSet<NSString *> *processingJobIds;
@end

@implementation ATProtoMediaWorker {
    dispatch_queue_t _workerQueue;
    dispatch_queue_t _stateQueue;
    dispatch_source_t _pollTimer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = NO;
        _pollInterval = 5.0;
        _maxConcurrentJobs = 2;
        _workerQueue = dispatch_queue_create("com.atproto.mediacore.worker", DISPATCH_QUEUE_SERIAL);
        _stateQueue = dispatch_queue_create("com.atproto.mediacore.state", DISPATCH_QUEUE_SERIAL);
        _processingJobIds = [NSMutableSet set];
    }
    return self;
}

#pragma mark - Lifecycle

- (void)start {
    if (self.enabled) return;
    self.enabled = YES;
    GZ_LOG_INFO(@"Media worker starting");
    [self startPollTimer];
}

- (void)stop {
    if (!self.isRunning) return;
    self.enabled = NO;
    if (_pollTimer) {
        dispatch_source_cancel(_pollTimer);
        _pollTimer = nil;
    }
    GZ_LOG_INFO(@"Media worker stopped");
}

- (void)startPollTimer {
    if (_pollTimer) dispatch_source_cancel(_pollTimer);
    _pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _workerQueue);
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

#pragma mark - Job Polling

- (void)processPendingJobs {
    if (!self.enabled) return;

    __block BOOL atCapacity = NO;
    dispatch_sync(_stateQueue, ^{
        atCapacity = self.processingJobIds.count >= self.maxConcurrentJobs;
    });
    if (atCapacity) return;

    if (!self.jobStore || !self.processor) return;

    __block NSInteger availableSlots = 0;
    dispatch_sync(_stateQueue, ^{
        availableSlots = self.maxConcurrentJobs - self.processingJobIds.count;
    });

    NSError *error = nil;
    NSArray<NSDictionary *> *pendingJobs = [self.jobStore queryPendingJobsWithLimit:availableSlots error:&error];
    if (error || pendingJobs.count == 0) return;

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
            GZ_LOG_INFO(@"Processing media job: %@", jobId);
            [self updateJobProgress:jobId progress:10 message:@"Loading media"];

            NSError *dbError = nil;
            NSDictionary *job = [self.jobStore getJobById:jobId error:&dbError];
            if (!job) {
                [self failJob:jobId error:dbError ?: [NSError errorWithDomain:ATProtoMediaWorkerErrorDomain
                                                                         code:ATProtoMediaWorkerErrorDatabaseUnavailable
                                                                     userInfo:@{NSLocalizedDescriptionKey: @"Job not found"}]];
                return;
            }

            NSString *blobCid = job[@"blob_cid"];
            if (!blobCid || [blobCid isEqual:[NSNull null]]) {
                [self failJob:jobId error:[NSError errorWithDomain:ATProtoMediaWorkerErrorDomain
                                                              code:ATProtoMediaWorkerErrorProcessingFailed
                                                          userInfo:@{NSLocalizedDescriptionKey: @"Missing blob CID"}]];
                return;
            }

            CID *cid = [CID cidFromString:blobCid];
            if (!cid) {
                [self failJob:jobId error:[NSError errorWithDomain:ATProtoMediaWorkerErrorDomain
                                                              code:ATProtoMediaWorkerErrorProcessingFailed
                                                          userInfo:@{NSLocalizedDescriptionKey: @"Invalid blob CID"}]];
                return;
            }

            // Create workspace temp directories
            NSString *tempDir = NSTemporaryDirectory();
            NSString *workspace = [tempDir stringByAppendingFormat:@"media_%@", jobId];
            [[NSFileManager defaultManager] createDirectoryAtPath:workspace
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];

            NSString *tempInputPath = [workspace stringByAppendingPathComponent:@"input.bin"];
            NSURL *inputURL = [NSURL fileURLWithPath:tempInputPath];

            // Download source blob
            [self updateJobState:jobId state:ATProtoMediaJobStateProcessing progress:15 message:@"Downloading source"];

            BOOL hasLocalFile = NO;
            NSError *blobError = nil;

            if ([self.blobProvider respondsToSelector:@selector(blobFileURLForCID:error:)]) {
                NSURL *fileURL = [self.blobProvider blobFileURLForCID:cid error:nil];
                if (fileURL && [[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:inputURL error:&blobError]) {
                    hasLocalFile = YES;
                }
            }

            if (!hasLocalFile) {
                NSInputStream *inputStream = [self.blobProvider retrieveBlobStreamForCID:cid error:&blobError];
                if (!inputStream) {
                    GZ_LOG_ERROR(@"Failed to open stream for blob %@: %@", blobCid, blobError);
                    [self failJob:jobId error:blobError ?: [NSError errorWithDomain:ATProtoMediaWorkerErrorDomain
                                                                               code:ATProtoMediaWorkerErrorBlobProviderUnavailable
                                                                           userInfo:@{NSLocalizedDescriptionKey: @"Failed to retrieve blob stream"}]];
                    return;
                }
                NSOutputStream *outputStream = [NSOutputStream outputStreamToFileAtPath:inputURL.path append:NO];
                [outputStream open];
                [inputStream open];
                uint8_t buffer[65536];
                BOOL streamErr = NO;
                while ([inputStream hasBytesAvailable]) {
                    NSInteger bytesRead = [inputStream read:buffer maxLength:sizeof(buffer)];
                    if (bytesRead < 0) { blobError = [inputStream streamError]; streamErr = YES; break; }
                    if (bytesRead == 0) break;
                    if ([outputStream write:buffer maxLength:bytesRead] < 0) {
                        blobError = [outputStream streamError]; streamErr = YES; break;
                    }
                }
                [inputStream close];
                [outputStream close];
                if (streamErr) {
                    [self failJob:jobId error:blobError ?: [NSError errorWithDomain:ATProtoMediaWorkerErrorDomain
                                                                               code:ATProtoMediaWorkerErrorProcessingFailed
                                                                           userInfo:@{NSLocalizedDescriptionKey: @"Stream pipe write failed"}]];
                    return;
                }
            }

            // Delegate to domain-specific processor
            [self updateJobProgress:jobId progress:20 message:@"Processing media"];
            NSString *outputDir = [workspace stringByAppendingPathComponent:@"output"];
            [[NSFileManager defaultManager] createDirectoryAtPath:outputDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];

            [self.processor processMediaAtURL:inputURL
                              outputDirectory:outputDir
                                progressBlock:^(float progress) {
                NSInteger p = 20 + (NSInteger)(progress * 60);
                [self updateJobProgress:jobId progress:p message:@"Processing media"];
            }
                                   completion:^(NSDictionary *results, NSError *processingError) {
                // Clean up workspace input
                [[NSFileManager defaultManager] removeItemAtPath:workspace error:nil];

                if (!results || processingError) {
                    GZ_LOG_ERROR(@"Processing failed for job %@: %@", jobId, processingError);
                    [self handleJobFailure:jobId error:processingError ?: [NSError errorWithDomain:ATProtoMediaWorkerErrorDomain
                                                                                              code:ATProtoMediaWorkerErrorProcessingFailed
                                                                                          userInfo:@{NSLocalizedDescriptionKey: @"Processing failed"}]];
                    return;
                }

                [self updateJobProgress:jobId progress:85 message:@"Storing results"];

                // Store results and complete
                NSError *storeError = nil;
                BOOL updated = [self.jobStore updateJobResults:jobId results:results error:&storeError];
                if (updated) {
                    [self completeJob:jobId];
                } else {
                    GZ_LOG_ERROR(@"Failed to update job results: %@", storeError);
                    [self handleJobFailure:jobId error:storeError];
                }
            }];
        }
    });
}

#pragma mark - State Transitions

- (void)updateJobState:(NSString *)jobId
                 state:(ATProtoMediaJobState)state
              progress:(NSInteger)progress
               message:(NSString *)message {
    [self.jobStore updateJobState:jobId state:state progress:progress message:message error:nil];
}

- (void)updateJobProgress:(NSString *)jobId progress:(NSInteger)progress message:(NSString *)message {
    [self.jobStore updateJobState:jobId state:ATProtoMediaJobStateProcessing progress:progress message:message error:nil];
}

- (void)completeJob:(NSString *)jobId {
    [self updateJobState:jobId state:ATProtoMediaJobStateCompleted progress:100 message:@"Processing complete"];
    dispatch_sync(_stateQueue, ^{ [self.processingJobIds removeObject:jobId]; });
    GZ_LOG_INFO(@"Media job completed: %@", jobId);
}

- (void)failJob:(NSString *)jobId error:(NSError *)error {
    [self.jobStore updateJobState:jobId state:ATProtoMediaJobStateFailed progress:0 message:error.localizedDescription ?: @"Unknown error" error:nil];
    dispatch_sync(_stateQueue, ^{ [self.processingJobIds removeObject:jobId]; });
    GZ_LOG_ERROR(@"Media job failed: %@ - %@", jobId, error);
}

- (void)handleJobFailure:(NSString *)jobId error:(NSError *)error {
    NSError *dbError = nil;
    NSDictionary *job = [self.jobStore getJobById:jobId error:&dbError];
    NSInteger retryCount = [job[@"retry_count"] integerValue];
    if (retryCount < 3) {
        GZ_LOG_WARN(@"Job %@ failed, retrying (%ld/3): %@", jobId, (long)retryCount + 1, error);
        [self.jobStore incrementJobRetry:jobId error:nil];
        dispatch_sync(_stateQueue, ^{ [self.processingJobIds removeObject:jobId]; });
    } else {
        GZ_LOG_ERROR(@"Job %@ failed permanently after %ld retries: %@", jobId, (long)retryCount, error);
        [self failJob:jobId error:error];
    }
}

@end
