// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PLCSyncEngine.h
 * @abstract Sync orchestration engine for PLC replica.
 * @discussion PLCSyncEngine manages the complete sync lifecycle for a PLC read replica,
 * including initial backfill from /export endpoint, live sync via polling, parallel
 * operation validation, and error recovery with exponential backoff.
 */

#import <Foundation/Foundation.h>
#import "PLC/PLCSyncClient.h"
#import "PLC/PLCReplicaStore.h"
#import "PLC/PLCAuditor.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Current synchronization state of the replica.
 */
typedef NS_ENUM(NSInteger, PLCSyncState) {
    PLCSyncStateIdle,
    PLCSyncStateBackfilling,
    PLCSyncStateLiveSyncing,
    PLCSyncStatePaused,
    PLCSyncStateError
};

/**
 * @abstract Delegate for monitoring synchronization progress and state changes.
 */
@protocol PLCSyncEngineDelegate <NSObject>
@optional

/** @abstract Sync backfill started. */
- (void)syncEngineDidStartBackfill:(id)engine;

/**
 * @abstract Backfill progress update.
 * @param progress Fraction of backfill completed (0.0 to 1.0).
 * @param count Number of operations ingested.
 */
- (void)syncEngine:(id)engine backfillProgress:(float)progress operationsIngested:(NSUInteger)count;

/**
 * @abstract Backfill completed successfully.
 */
- (void)syncEngineDidCompleteBackfill:(id)engine operationsIngested:(NSUInteger)count;

/**
 * @abstract Operations were successfully ingested.
 */
- (void)syncEngine:(id)engine didIngestOperations:(NSArray *)ops count:(NSUInteger)count;

/**
 * @abstract Synchronization encountered an error.
 */
- (void)syncEngine:(id)engine didEncounterError:(NSError *)error;

/**
 * @abstract Synchronization state transitioned.
 */
- (void)syncEngineStateDidChange:(id)engine fromState:(PLCSyncState)fromState toState:(PLCSyncState)toState;
@end

/**
 * @abstract Orchestrates synchronization lifecycle for a PLC replica.
 */
@interface PLCSyncEngine : NSObject

/** @abstract Delegate for notifications. */
@property (nonatomic, weak, nullable) id<PLCSyncEngineDelegate> delegate;
/** @abstract Current synchronization state. */
@property (nonatomic, assign, readonly) PLCSyncState state;
/** @abstract Number of concurrent workers. */
@property (nonatomic, assign) NSUInteger numWorkers;
/** @abstract Operations per batch. */
@property (nonatomic, assign) NSUInteger batchSize;
/** @abstract Interval between poll requests. */
@property (nonatomic, assign) NSTimeInterval pollInterval;
/** @abstract Max retry attempts. */
@property (nonatomic, assign) NSUInteger maxRetries;
/** @abstract Maximum delay between retries. */
@property (nonatomic, assign) NSTimeInterval maxRetryDelay;

/** @abstract Total count of ingested operations. */
@property (nonatomic, assign, readonly) NSUInteger totalOperationsIngested;
/** @abstract Total count of failed operations. */
@property (nonatomic, assign, readonly) NSUInteger totalOperationsFailed;
/** @abstract Last successful sync timestamp. */
@property (nonatomic, strong, readonly, nullable) NSDate *lastSyncDate;
/** @abstract Current sync cursor index. */
@property (nonatomic, assign, readonly) NSInteger currentCursor;

/**
 * @abstract Initializes the engine with the required storage, client, and auditor.
 * @param store The replica store.
 * @param client The sync client.
 * @param auditor The PLC auditor.
 * @return An initialized engine instance.
 */
- (instancetype)initWithStore:(PLCReplicaStore *)store
                       client:(PLCSyncClient *)client
                      auditor:(PLCAuditor *)auditor NS_DESIGNATED_INITIALIZER;

/** @abstract Unavailable initializer. */
- (instancetype)init NS_UNAVAILABLE;

/** @abstract Starts the sync engine. */
- (void)start;
/** @abstract Stops the sync engine. */
- (void)stop;
/** @abstract Pauses synchronization. */
- (void)pause;
/** @abstract Resumes synchronization. */
- (void)resume;

/**
 * @abstract Triggers a single sync cycle.
 * @param error Receives failure details.
 * @return YES if successful.
 */
- (BOOL)syncOnceWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END