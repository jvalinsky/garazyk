// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewBackfillOrchestrator.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Backfill/AppViewBackfillOrchestrator.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"
#import "AppView/Server/Indexers/AppViewIndexer.h"
#import "AppView/Server/Backfill/AppViewBackfillWorker.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"

// ---------------------------------------------------------------------------

@interface AppViewBackfillOrchestrator () <AppViewBackfillWorkerDelegate>

@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) NSArray<id<AppViewIndexer>> *indexers;

// Queue discipline
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t schedulerQueue; // Serial
@property (nonatomic, strong) NSMutableArray<NSString *> *pendingQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *activeWorkersByHost;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *hostBackoffUntil;
@property (nonatomic, assign, readwrite) NSInteger activeWorkers;

// Stop flag
@property (nonatomic, assign) BOOL stopping;

@end

// ---------------------------------------------------------------------------

@implementation AppViewBackfillOrchestrator

- (instancetype)initWithDatabase:(AppViewDatabase *)database
                         indexers:(NSArray<id<AppViewIndexer>> *)indexers
                         plcURL:(NSString *)plcURL {
    self = [super init];
    if (!self) return nil;
    _database             = database;
    _indexers             = [indexers copy];
    _plcURL              = [plcURL copy];
    _globalWorkerCap      = 8;
    _perHostWorkerCap     = 2;
    _baseBackoffSeconds   = 1.0;
    _maxBackoffSeconds    = 300.0;
    _pendingQueue         = [NSMutableArray array];
    _activeWorkersByHost  = [NSMutableDictionary dictionary];
    _hostBackoffUntil     = [NSMutableDictionary dictionary];
    _schedulerQueue       = dispatch_queue_create("dev.garazyk.appview.backfill.scheduler",
                                                   DISPATCH_QUEUE_SERIAL);
    return self;
}

- (NSInteger)queueDepth {
    __block NSInteger depth = 0;
    dispatch_sync(_schedulerQueue, ^{
        depth = (NSInteger)self.pendingQueue.count + self.activeWorkers;
    });
    return depth;
}

// ---------------------------------------------------------------------------
// Start / Stop
// ---------------------------------------------------------------------------

- (void)start {
    _stopping = NO;
    PDS_LOG_INFO(@"[AppView Backfill] Orchestrator starting, sweeping pending repos…");

    dispatch_async(_schedulerQueue, ^{
        [self _sweepPendingRepos];
    });
}

- (void)stop {
    _stopping = YES;
    PDS_LOG_INFO(@"[AppView Backfill] Orchestrator stopping.");
}

- (void)_sweepPendingRepos {
    // Called on _schedulerQueue
    NSError *err = nil;
    NSArray<AppViewRepoSyncState *> *pending =
        [_database loadRepoSyncStatesWithStatus:AppViewRepoSyncStatusPending limit:500 error:&err];
    if (err) {
        PDS_LOG_WARN(@"[AppView Backfill] Sweep failed: %@", err.localizedDescription);
        return;
    }
    NSArray<AppViewRepoSyncState *> *dirty =
        [_database loadRepoSyncStatesWithStatus:AppViewRepoSyncStatusDirty limit:500 error:&err];

    NSMutableArray<NSString *> *dids = [NSMutableArray array];
    for (AppViewRepoSyncState *s in pending) [dids addObject:s.did];
    for (AppViewRepoSyncState *s in dirty)   [dids addObject:s.did];

    if (dids.count > 0) {
        PDS_LOG_INFO(@"[AppView Backfill] Sweep enqueued %lu repos.", (unsigned long)dids.count);
        [_pendingQueue addObjectsFromArray:dids];
        [self _scheduleNextWorkers];
    }
}

// ---------------------------------------------------------------------------
// Enqueue
// ---------------------------------------------------------------------------

- (void)enqueueDIDs:(NSArray<NSString *> *)dids {
    dispatch_async(_schedulerQueue, ^{
        for (NSString *did in dids) {
            NSError *err = nil;
            AppViewRepoSyncState *state = [self.database loadRepoSyncStateForDID:did error:&err];
            if (!state) {
                state = [[AppViewRepoSyncState alloc] initWithDID:did];
                [self.database upsertRepoSyncState:state error:nil];
            } else if (state.status == AppViewRepoSyncStatusSynced) {
                [self.database markRepoDirty:did error:nil];
            } else if (state.status == AppViewRepoSyncStatusProcessing) {
                continue; // Already being processed
            }
            if (![self.pendingQueue containsObject:did])
                [self.pendingQueue addObject:did];
        }
        [self _scheduleNextWorkers];
    });
}

- (void)notifyGapDetectedForDID:(NSString *)did atSeq:(int64_t)seq {
    PDS_LOG_INFO(@"[AppView Backfill] Gap detected for %@ at seq %lld — marking dirty", did, (long long)seq);
    dispatch_async(_schedulerQueue, ^{
        [self.database markRepoDirty:did error:nil];
        if (![self.pendingQueue containsObject:did])
            [self.pendingQueue addObject:did];
        [self _scheduleNextWorkers];
    });
}

// ---------------------------------------------------------------------------
// Scheduler (always called on _schedulerQueue)
// ---------------------------------------------------------------------------

- (void)_scheduleNextWorkers {
    while (!_stopping
           && _pendingQueue.count > 0
           && _activeWorkers < (NSInteger)_globalWorkerCap) {

        NSString *did = _pendingQueue.firstObject;
        [_pendingQueue removeObjectAtIndex:0];

        NSString *host = [self _hostForDID:did];

        // Per-host cap check
        NSInteger hostCount = [_activeWorkersByHost[host] integerValue];
        if (hostCount >= (NSInteger)_perHostWorkerCap) {
            // Push to back, try next
            [_pendingQueue addObject:did];
            break;
        }

        // Backoff check
        NSDate *backoffUntil = _hostBackoffUntil[host];
        if (backoffUntil && [backoffUntil timeIntervalSinceNow] > 0) {
            [_pendingQueue addObject:did];
            break;
        }

        // Mark as processing
        NSArray<NSString *> *transitioned = [_database markReposAsProcessing:@[did] error:nil];
        if (transitioned.count == 0) continue; // race — already processing

        _activeWorkers++;
        _activeWorkersByHost[host] = @(hostCount + 1);

        AppViewBackfillWorker *worker = [[AppViewBackfillWorker alloc]
            initWithDID:did database:_database indexers:_indexers plcURL:_plcURL ?: @"https://plc.directory"];
        worker.delegate = self;
        [worker start];
    }
}

- (NSString *)_hostForDID:(NSString *)did {
    // did:plc:xxx → plc.directory (all via same PLC endpoint)
    // did:web:host → host
    if ([did hasPrefix:@"did:web:"]) {
        NSString *domain = [did substringFromIndex:8];
        return domain.lowercaseString;
    }
    // For did:plc and other methods, the PDS host is not known until resolution
    // Use a round-robin slot derived from the did hash
    NSUInteger hash = did.hash % 4;
    return [NSString stringWithFormat:@"_plc_slot_%lu", (unsigned long)hash];
}

// ---------------------------------------------------------------------------
// AppViewBackfillWorkerDelegate
// ---------------------------------------------------------------------------

- (void)worker:(AppViewBackfillWorker *)worker didCompleteForDID:(NSString *)did lastRev:(NSString *)lastRev {
    PDS_LOG_INFO(@"[AppView Backfill] Completed backfill for %@", did);

    dispatch_async(_schedulerQueue, ^{
        NSString *host = [self _hostForDID:did];
        NSInteger hostCount = [self.activeWorkersByHost[host] integerValue];
        self.activeWorkersByHost[host] = @(MAX(0, hostCount - 1));
        self.activeWorkers = MAX(0, self.activeWorkers - 1);
        [self _scheduleNextWorkers];
    });

    // Replay pending deltas
    __block NSArray<AppViewPendingDelta *> *cachedDeltas = nil;
    __block id cachedDelegate = nil;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSError *err = nil;
        cachedDeltas = [self.database dequeuePendingDeltasForDID:did error:&err];
        if (cachedDeltas.count > 0) {
            PDS_LOG_INFO(@"[AppView Backfill] Replaying %lu pending deltas for %@",
                         (unsigned long)cachedDeltas.count, did);
            for (AppViewPendingDelta *delta in cachedDeltas) {
                // Dispatch to indexers as if it were a live event
                for (id<AppViewIndexer> indexer in self.indexers) {
                    if ([indexer respondsToSelector:@selector(processPendingDelta:error:)]) {
                        [indexer processPendingDelta:delta error:nil];
                    }
                }
            }
        }

        cachedDelegate = self.delegate;
        if ([cachedDelegate respondsToSelector:@selector(orchestrator:didCompleteBackfillForDID:)]) {
            [cachedDelegate orchestrator:self didCompleteBackfillForDID:did];
        }
    });
}

- (void)worker:(AppViewBackfillWorker *)worker
didFailForDID:(NSString *)did
 error:(NSError *)error
rateLimitedUntil:(nullable NSDate *)rateLimitedUntil {
    PDS_LOG_WARN(@"[AppView Backfill] Backfill failed for %@: %@", did, error.localizedDescription);

    dispatch_async(_schedulerQueue, ^{
        NSString *host = [self _hostForDID:did];
        NSInteger hostCount = [self.activeWorkersByHost[host] integerValue];
        self.activeWorkersByHost[host] = @(MAX(0, hostCount - 1));
        self.activeWorkers = MAX(0, self.activeWorkers - 1);

        // Apply backoff
        if (rateLimitedUntil) {
            self.hostBackoffUntil[host] = rateLimitedUntil;
        } else {
            // Exponential backoff based on error count
            NSError *stateErr = nil;
            AppViewRepoSyncState *state = [self.database loadRepoSyncStateForDID:did error:&stateErr];
            NSInteger errorCount = state ? state.errorCount : 1;
            NSTimeInterval delay = MIN(
                self.baseBackoffSeconds * pow(2.0, errorCount - 1),
                self.maxBackoffSeconds
            );
            NSDate *backoff = [NSDate dateWithTimeIntervalSinceNow:delay];
            self.hostBackoffUntil[host] = backoff;
        }

        // Re-enqueue for retry (goes to the end of the queue)
        [self.pendingQueue addObject:did];

        id<AppViewBackfillOrchestratorDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(orchestrator:didFailBackfillForDID:error:)]) {
            [delegate orchestrator:self didFailBackfillForDID:did error:error];
        }

        [self _scheduleNextWorkers];
    });
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

- (NSDictionary *)statusReport {
    __block NSInteger qDepth = 0;
    __block NSInteger active = 0;
    dispatch_sync(_schedulerQueue, ^{
        qDepth = (NSInteger)self.pendingQueue.count;
        active = self.activeWorkers;
    });

    NSError *err = nil;
    NSInteger pendingCount  = [_database countRepoSyncStatesWithStatus:AppViewRepoSyncStatusPending  error:&err];
    NSInteger processingCount = [_database countRepoSyncStatesWithStatus:AppViewRepoSyncStatusProcessing error:&err];
    NSInteger syncedCount   = [_database countRepoSyncStatesWithStatus:AppViewRepoSyncStatusSynced   error:&err];
    NSInteger dirtyCount    = [_database countRepoSyncStatesWithStatus:AppViewRepoSyncStatusDirty    error:&err];

    return @{
        @"queue_depth":    @(qDepth),
        @"active_workers": @(active),
        @"repos_pending":  @(pendingCount),
        @"repos_processing": @(processingCount),
        @"repos_synced":   @(syncedCount),
        @"repos_dirty":    @(dirtyCount),
    };
}

// ---------------------------------------------------------------------------
// Queue and detail operations
// ---------------------------------------------------------------------------

- (NSDictionary *)queueWithLimit:(NSInteger)limit
                           cursor:(NSString *)cursor
                           status:(NSString *)status {
    NSMutableArray *entries = [NSMutableArray array];
    NSInteger boundedLimit = limit > 0 ? limit : 50;

    NSMutableArray<NSNumber *> *statusFilters = [NSMutableArray array];
    if (status.length == 0 || [status isEqualToString:@"all"]) {
        [statusFilters addObject:@(AppViewRepoSyncStatusPending)];
        [statusFilters addObject:@(AppViewRepoSyncStatusProcessing)];
        [statusFilters addObject:@(AppViewRepoSyncStatusSynced)];
        [statusFilters addObject:@(AppViewRepoSyncStatusDirty)];
    } else if ([status isEqualToString:@"pending"]) {
        [statusFilters addObject:@(AppViewRepoSyncStatusPending)];
    } else if ([status isEqualToString:@"processing"]) {
        [statusFilters addObject:@(AppViewRepoSyncStatusProcessing)];
    } else if ([status isEqualToString:@"synced"]) {
        [statusFilters addObject:@(AppViewRepoSyncStatusSynced)];
    } else if ([status isEqualToString:@"dirty"]) {
        [statusFilters addObject:@(AppViewRepoSyncStatusDirty)];
    } else {
        return @{
            @"entries": @[],
            @"total": @0,
            @"cursor": [NSNull null],
        };
    }

    NSError *err = nil;
    NSMutableArray<AppViewRepoSyncState *> *repos = [NSMutableArray array];
    for (NSNumber *statusNumber in statusFilters) {
        NSArray<AppViewRepoSyncState *> *batch =
            [_database loadRepoSyncStatesWithStatus:(AppViewRepoSyncStatus)statusNumber.integerValue
                                              limit:boundedLimit
                                              error:&err];
        if (err) {
            break;
        }
        if (batch.count > 0) {
            [repos addObjectsFromArray:batch];
        }
    }

    if (err) {
        return @{
            @"entries": @[],
            @"total": @0,
            @"cursor": [NSNull null],
            @"error": err.localizedDescription ?: @"failed to load queue",
        };
    }

    if (cursor.length > 0) {
        NSIndexSet *toRemove =
            [repos indexesOfObjectsPassingTest:^BOOL(AppViewRepoSyncState *repo, NSUInteger idx, BOOL *stop) {
                return [repo.did compare:cursor] != NSOrderedDescending;
            }];
        if (toRemove.count > 0) {
            [repos removeObjectsAtIndexes:toRemove];
        }
    }

    [repos sortUsingComparator:^NSComparisonResult(AppViewRepoSyncState *a, AppViewRepoSyncState *b) {
        return [a.did compare:b.did];
    }];
    if (repos.count > boundedLimit) {
        [repos removeObjectsInRange:NSMakeRange(boundedLimit, repos.count - boundedLimit)];
    }

    for (AppViewRepoSyncState *repo in repos) {
        [entries addObject:@{
            @"did": repo.did ?: @"",
            @"status": [self stringFromSyncStatus:repo.status],
            @"last_rev": repo.lastRev ?: @"",
            @"last_backfill_at": repo.lastBackfillAt ? [repo.lastBackfillAt description] : @"",
            @"retry_count": @(repo.errorCount),
            @"last_error": repo.lastError ?: @"",
        }];
    }

    NSString *nextCursor = nil;
    if (repos.count >= boundedLimit) {
        nextCursor = [repos.lastObject did];
    }

    return @{
        @"entries": entries,
        @"total": @(entries.count),
        @"cursor": nextCursor ?: [NSNull null],
    };
}

- (NSDictionary *)repoDetail:(NSString *)did {
    if (!did || did.length == 0) return nil;

    NSError *err = nil;
    AppViewRepoSyncState *repo = [_database getRepoSyncState:did error:&err];
    if (!repo) return nil;

    return @{
        @"did": did,
        @"status": [self stringFromSyncStatus:repo.status],
        @"last_rev": repo.lastRev ?: @"",
        @"last_backfill_at": repo.lastBackfillAt ? [repo.lastBackfillAt description] : @"",
        @"retry_count": @(repo.errorCount),
        @"last_error": repo.lastError ?: @"",
        @"created_at": @"",
    };
}

- (BOOL)retryRepo:(NSString *)did {
    if (!did || did.length == 0) return NO;

    dispatch_async(_schedulerQueue, ^{
        [self.pendingQueue removeObject:did];
    });

    [self enqueueDIDs:@[did]];
    return YES;
}

- (BOOL)cancelRepo:(NSString *)did {
    if (!did || did.length == 0) return NO;

    __block BOOL found = NO;
    dispatch_sync(_schedulerQueue, ^{
        NSUInteger idx = [self.pendingQueue indexOfObject:did];
        if (idx != NSNotFound) {
            [self.pendingQueue removeObjectAtIndex:idx];
            found = YES;
        }
    });

    NSError *err = nil;
    AppViewRepoSyncState *repo = [_database getRepoSyncState:did error:&err];
    if (repo) {
        repo.status = AppViewRepoSyncStatusPending;
        [_database setRepoSyncState:repo error:&err];
        found = YES;
    }

    return found;
}

- (NSString *)stringFromSyncStatus:(AppViewRepoSyncStatus)status {
    switch (status) {
        case AppViewRepoSyncStatusPending: return @"pending";
        case AppViewRepoSyncStatusProcessing: return @"processing";
        case AppViewRepoSyncStatusSynced: return @"synced";
        case AppViewRepoSyncStatusDirty: return @"dirty";
        default: return @"unknown";
    }
}

@end
