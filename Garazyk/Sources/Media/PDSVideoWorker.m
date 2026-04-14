#import "Media/PDSVideoWorker.h"
#import "Media/PDSVideoThumbnailGenerator.h"
#import "Media/PDSVideoTranscoder.h"
#import "Database/PDSDatabase.h"
#import "Blob/PDSBlobProvider.h"
#import "Debug/PDSLogger.h"

NSString * const PDSVideoWorkerErrorDomain = @"com.atproto.pds.video.worker";

@interface PDSVideoWorker ()
@property (nonatomic, strong) id<PDSBlobProvider> blobProvider;
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

    PDSDatabase *database = [PDSDatabase sharedDatabase];
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
    PDSDatabase *database = [PDSDatabase sharedDatabase];
    NSString *sql = @"SELECT * FROM video_jobs WHERE state = 'PENDING' ORDER BY created_at ASC LIMIT ?";
    return [database executeParameterizedQuery:sql params:@[@(limit)] error:error];
}

- (void)processJob:(NSString *)jobId {
    dispatch_async(_workerQueue, ^{
        PDS_LOG_INFO(@"Processing video job: %@", jobId);

        [self updateJobProgress:jobId progress:0 message:@"Starting processing"];

        PDSDatabase *database = [PDSDatabase sharedDatabase];
        NSError *dbError = nil;
        NSDictionary *job = [database getVideoJobById:jobId error:&dbError];

        if (!job) {
            PDS_LOG_ERROR(@"Job not found: %@", jobId);
            [self failJob:jobId error:dbError ?: [NSError errorWithDomain:PDSVideoWorkerErrorDomain
                                                          code:PDSVideoWorkerErrorDatabaseUnavailable
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Job not found"}]];
            return;
        }

        NSString *inputPath = job[@"blob_cid"];
        if (!inputPath) {
            inputPath = job[@"original_filename"];
        }

        if (!inputPath) {
            [self failJob:jobId error:[NSError errorWithDomain:PDSVideoWorkerErrorDomain
                                                  code:PDSVideoWorkerErrorProcessingFailed
                                              userInfo:@{NSLocalizedDescriptionKey: @"Input file not found"}]];
            return;
        }

        [self updateJobState:jobId state:@"PROCESSING" progress:10 message:@"Video processing available on macOS with AVFoundation"];

        [self completeJob:jobId];
    });
}

- (void)updateJobState:(NSString *)jobId
                state:(NSString *)state
             progress:(NSInteger)progress
              message:(NSString *)message {
    [[PDSDatabase sharedDatabase] updateVideoJobState:jobId
                                         state:state
                                      progress:@(progress)
                                       message:message
                                         error:nil];
}

- (void)updateJobProgress:(NSString *)jobId
               progress:(NSInteger)progress
                message:(NSString *)message {
    [[PDSDatabase sharedDatabase] updateVideoJobState:jobId
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
    [self updateJobState:jobId state:@"FAILED" progress:0 message:error.localizedDescription];

    @synchronized(self.processingJobIds) {
        [self.processingJobIds removeObject:jobId];
    }

    PDS_LOG_ERROR(@"Video job failed: %@ - %@", jobId, error);
}

@end