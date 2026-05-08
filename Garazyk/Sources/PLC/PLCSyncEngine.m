#import "PLCSyncEngine.h"
#import "PLC/PLCMetrics.h"
#import "Debug/PDSLogger.h"
#import "libkern/OSAtomic.h"

NSString * const PLCSyncEngineErrorDomain = @"com.atproto.pds.plc.syncengine";

static const NSUInteger kDefaultBatchSize = 100;
static const NSTimeInterval kDefaultPollInterval = 5.0;
static const NSUInteger kDefaultMaxRetries = 3;
static const NSTimeInterval kDefaultMaxRetryDelay = 60.0;

@interface PLCSyncEngine ()

@property (nonatomic, strong) PLCReplicaStore *store;
@property (nonatomic, strong) PLCSyncClient *client;
@property (nonatomic, strong) PLCAuditor *auditor;
@property (nonatomic, assign, readwrite) PLCSyncState state;
@property (nonatomic, assign, readwrite) NSUInteger totalOperationsIngested;
@property (nonatomic, assign, readwrite) NSUInteger totalOperationsFailed;
@property (nonatomic, strong, readwrite, nullable) NSDate *lastSyncDate;
@property (nonatomic, assign, readwrite) NSInteger currentCursor;
@property (nonatomic, assign) dispatch_source_t pollTimer;
@property (nonatomic, assign) BOOL shouldStop;
@property (nonatomic, assign) BOOL isPaused;
@property (nonatomic, assign) NSUInteger currentRetryCount;

@end

@implementation PLCSyncEngine {
    dispatch_queue_t _syncQueue;
    dispatch_queue_t _validationQueue;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithStore:(PLCReplicaStore *)store
                       client:(PLCSyncClient *)client
                      auditor:(PLCAuditor *)auditor {
    self = [super init];
    if (self) {
        _store = store;
        _client = client;
        _auditor = auditor;
        _state = PLCSyncStateIdle;
        _numWorkers = 4;
        _batchSize = kDefaultBatchSize;
        _pollInterval = kDefaultPollInterval;
        _maxRetries = kDefaultMaxRetries;
        _maxRetryDelay = kDefaultMaxRetryDelay;
        _totalOperationsIngested = 0;
        _totalOperationsFailed = 0;
        _currentCursor = 0;
        _shouldStop = NO;
        _isPaused = NO;
        _currentRetryCount = 0;
        
        _syncQueue = dispatch_queue_create("com.atproto.plc.syncengine", DISPATCH_QUEUE_SERIAL);
        _validationQueue = dispatch_queue_create("com.atproto.plc.syncengine.validation", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Public Methods

- (void)start {
    dispatch_async(_syncQueue, ^{
        if (self.state == PLCSyncStateBackfilling || self.state == PLCSyncStateLiveSyncing) {
            return;
        }
        
        self.shouldStop = NO;
        self.isPaused = NO;
        
        [self updateState:PLCSyncStateBackfilling];
        
        if ([self.delegate respondsToSelector:@selector(syncEngineDidStartBackfill:)]) {
            [self.delegate syncEngineDidStartBackfill:self];
        }
        
        [self performBackfill];
    });
}

- (void)stop {
    dispatch_sync(_syncQueue, ^{
        self.shouldStop = YES;
        
        if (self.pollTimer) {
            dispatch_source_cancel(self.pollTimer);
            self.pollTimer = nil;
        }
        
        [self updateState:PLCSyncStateIdle];
    });
}

- (void)pause {
    dispatch_async(_syncQueue, ^{
        self.isPaused = YES;
        [self updateState:PLCSyncStatePaused];
    });
}

- (void)resume {
    dispatch_async(_syncQueue, ^{
        if (self.state != PLCSyncStatePaused) {
            return;
        }
        
        self.isPaused = NO;
        
        if (self.currentCursor > 0) {
            [self updateState:PLCSyncStateLiveSyncing];
            [self startPolling];
        } else {
            [self updateState:PLCSyncStateBackfilling];
            [self performBackfill];
        }
    });
}

- (BOOL)syncOnceWithError:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *syncError = nil;
    
    dispatch_sync(_syncQueue, ^{
        success = [self syncBatchWithError:&syncError];
    });
    
    if (error && syncError) {
        *error = syncError;
    }
    
    return success;
}

#pragma mark - Private Methods

- (void)updateState:(PLCSyncState)newState {
    if (self.state == newState) {
        return;
    }
    
    PLCSyncState oldState = self.state;
    self.state = newState;
    
    NSString *stateStr = [self stateToString:newState];
    [self.store updateSyncState:stateStr error:nil];
    
    if ([self.delegate respondsToSelector:@selector(syncEngineStateDidChange:fromState:toState:)]) {
        [self.delegate syncEngineStateDidChange:self fromState:oldState toState:newState];
    }
}

- (NSString *)stateToString:(PLCSyncState)state {
    switch (state) {
        case PLCSyncStateIdle: return @"idle";
        case PLCSyncStateBackfilling: return @"backfilling";
        case PLCSyncStateLiveSyncing: return @"live";
        case PLCSyncStatePaused: return @"paused";
        case PLCSyncStateError: return @"error";
    }
}

- (void)performBackfill {
    NSError *error = nil;
    NSInteger lastCursor = [self.store lastSyncCursorWithError:&error];
    
    if (lastCursor > 0) {
        self.currentCursor = lastCursor;
    }
    
    NSUInteger ingestedCount = 0;
    BOOL done = NO;
    
    while (!self.shouldStop && !done) {
        if (self.isPaused) {
            return;
        }
        
        NSArray<PLCOperation *> *ops = [self.client fetchOperationsAfterCursorSync:self.currentCursor count:self.batchSize error:&error];
        
        if (error) {
            [self handleSyncError:error];
            return;
        }
        
        if (ops.count == 0) {
            done = YES;
            continue;
        }
        
        NSUInteger validCount = [self validateAndIngestOperations:ops];
        ingestedCount += validCount;
        
        PLCOperation *lastOp = ops.lastObject;
        if (lastOp.createdAt) {
            self.currentCursor = (NSInteger)[lastOp.createdAt timeIntervalSince1970];
            [self.store updateSyncCursor:self.currentCursor error:nil];
        }
        
        float progress = (float)ops.count / (float)self.batchSize;
        
        if ([self.delegate respondsToSelector:@selector(syncEngine:backfillProgress:operationsIngested:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate syncEngine:self backfillProgress:progress operationsIngested:ingestedCount];
            });
        }
    }
    
    if (self.shouldStop) {
        return;
    }
    
    self.totalOperationsIngested += ingestedCount;
    self.lastSyncDate = [NSDate date];
    [self.store updateLastSyncTimestamp:self.lastSyncDate error:nil];
    
    [self updateState:PLCSyncStateLiveSyncing];
    
    if ([self.delegate respondsToSelector:@selector(syncEngineDidCompleteBackfill:operationsIngested:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate syncEngineDidCompleteBackfill:self operationsIngested:ingestedCount];
        });
    }
    
    [self startPolling];
}

- (void)startPolling {
    if (self.pollTimer) {
        dispatch_source_cancel(self.pollTimer);
    }
    
    self.pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _syncQueue);
    
    dispatch_source_set_timer(self.pollTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.pollInterval * NSEC_PER_SEC)),
                              (uint64_t)(self.pollInterval * NSEC_PER_SEC),
                              (uint64_t)(0.1 * NSEC_PER_SEC));
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.pollTimer, ^{
        [weakSelf pollForNewOperations];
    });
    
    dispatch_resume(self.pollTimer);
}

- (void)pollForNewOperations {
    if (self.shouldStop || self.isPaused) {
        return;
    }
    
    NSError *error = nil;
    NSArray<PLCOperation *> *ops = [self.client fetchOperationsAfterCursorSync:self.currentCursor count:self.batchSize error:&error];
    
    if (error) {
        [self handleSyncError:error];
        return;
    }
    
    if (ops.count == 0) {
        return;
    }
    
    NSUInteger validCount = [self validateAndIngestOperations:ops];
    self.totalOperationsIngested += validCount;
    
    PLCOperation *lastOp = ops.lastObject;
    if (lastOp.createdAt) {
        self.currentCursor = (NSInteger)[lastOp.createdAt timeIntervalSince1970];
        [self.store updateSyncCursor:self.currentCursor error:nil];
    }
    
    self.lastSyncDate = [NSDate date];
    [self.store updateLastSyncTimestamp:self.lastSyncDate error:nil];
    [self updateSyncMetrics];
    
    if ([self.delegate respondsToSelector:@selector(syncEngine:didIngestOperations:count:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate syncEngine:self didIngestOperations:ops count:validCount];
        });
    }
}

- (BOOL)syncBatchWithError:(NSError **)error {
    NSArray<PLCOperation *> *ops = [self.client fetchOperationsAfterCursorSync:self.currentCursor count:self.batchSize error:error];
    
    if (!ops || ops.count == 0) {
        return YES;
    }
    
    NSUInteger validCount = [self validateAndIngestOperations:ops];
    
    PLCOperation *lastOp = ops.lastObject;
    if (lastOp.createdAt) {
        self.currentCursor = (NSInteger)[lastOp.createdAt timeIntervalSince1970];
        [self.store updateSyncCursor:self.currentCursor error:nil];
    }
    
    self.totalOperationsIngested += validCount;
    self.lastSyncDate = [NSDate date];
    
    return YES;
}

- (NSUInteger)validateAndIngestOperations:(NSArray<PLCOperation *> *)operations {
    __block NSUInteger validCount = 0;
    __block NSUInteger failedCount = 0;
    
    dispatch_group_t validationGroup = dispatch_group_create();
    
    NSMutableArray<PLCOperation *> *validatedOps = [NSMutableArray array];
    NSLock *validatedOpsLock = [[NSLock alloc] init];
    
    for (PLCOperation *op in operations) {
        dispatch_group_async(validationGroup, _validationQueue, ^{
            NSError *validationError = nil;
            BOOL valid = [self.auditor verifyOperation:op error:&validationError];
            
            if (valid) {
                [validatedOpsLock lock];
                [validatedOps addObject:op];
                [validatedOpsLock unlock];
            } else {
                OSAtomicIncrement64((int64_t *)&failedCount);
                PDS_LOG_CORE_ERROR(@"PLC replica: operation validation failed for DID %@: %@", op.did, validationError.localizedDescription);
            }
        });
    }
    
    dispatch_group_wait(validationGroup, DISPATCH_TIME_FOREVER);
    
    validCount = validatedOps.count;
    self.totalOperationsFailed += failedCount;
    
    for (PLCOperation *op in validatedOps) {
        NSError *appendError = nil;
        BOOL stored = [self.store appendOperation:op nullifyCIDs:nil error:&appendError];
        
        if (!stored) {
            PDS_LOG_CORE_ERROR(@"PLC replica: failed to append operation for DID %@: %@", op.did, appendError.localizedDescription);
        }
    }
    
    return validCount;
}

- (void)handleSyncError:(NSError *)error {
    self.currentRetryCount++;
    
    NSTimeInterval delay = MIN(pow(2, self.currentRetryCount), self.maxRetryDelay);
    
    if (self.currentRetryCount >= self.maxRetries) {
        PDS_LOG_CORE_ERROR(@"PLC replica: sync failed after %lu retries: %@", (unsigned long)self.currentRetryCount, error.localizedDescription);
        
        [self updateState:PLCSyncStateError];
        
        if ([self.delegate respondsToSelector:@selector(syncEngine:didEncounterError:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate syncEngine:self didEncounterError:error];
            });
        }
        
        self.currentRetryCount = 0;
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _syncQueue, ^{
            if (!self.shouldStop && self.state == PLCSyncStateError) {
                [self resume];
            }
        });
        
        return;
    }
    
    PDS_LOG_CORE_WARN(@"PLC replica: sync error, retry %lu/%lu in %.1fs: %@",
                     (unsigned long)self.currentRetryCount,
                     (unsigned long)self.maxRetries,
                     delay,
                     error.localizedDescription);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _syncQueue, ^{
        if (!self.shouldStop && !self.isPaused) {
            [self pollForNewOperations];
        }
    });
}

- (void)updateSyncMetrics {
    [[PLCMetrics sharedMetrics] setGauge:@"plc_replica_operations_ingested_total" value:self.totalOperationsIngested];
    [[PLCMetrics sharedMetrics] setGauge:@"plc_replica_operations_failed_total" value:self.totalOperationsFailed];
    [[PLCMetrics sharedMetrics] setGauge:@"plc_replica_cursor" value:self.currentCursor];
}

@end