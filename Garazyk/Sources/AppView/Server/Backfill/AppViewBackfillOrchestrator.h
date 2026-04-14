/*!
 @file AppViewBackfillOrchestrator.h

 @abstract Backfill plane: schedules and runs per-repo `sync.getRepo` workers.

 @discussion The orchestrator manages the full backfill lifecycle:
  - Startup sweep: on start, transitions all `pending` repos to the work queue.
  - Gap detection: the ingest engine notifies when a rev gap is detected.
  - Admin enqueue: callers can enqueue specific DIDs on demand.
  - On-demand miss enqueue: query API enqueues a DID when materialized data
    is missing (partial-mode query path).

 Scheduling constraints:
  - Global worker cap (default 8): limits total concurrent backfill goroutines.
  - Per-host cap (default 2): limits concurrent requests to a single PDS host.
  - Exponential backoff per host on 429 responses or connection errors.

 Worker flow per DID:
  1. Mark repo `processing`.
  2. Fetch `com.atproto.sync.getRepo(did, since=lastRev)`.
  3. Parse CAR blocks.
  4. Dispatch decoded ops through registered indexers.
  5. On success: mark repo `synced`, dequeue and replay pending deltas.
  6. On failure: increment error count, exponential backoff, re-enqueue.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AppViewDatabase;
@class AppViewBackfillOrchestrator;
@protocol AppViewIndexer;

/*!
 @protocol AppViewBackfillOrchestratorDelegate

 @abstract Delegate for backfill lifecycle events.
 */
@protocol AppViewBackfillOrchestratorDelegate <NSObject>
@optional

/*!
 @method orchestrator:didCompleteBackfillForDID:

 @abstract Called when a repo's backfill completes successfully.
 At this point pending deltas have been replayed.
 */
- (void)orchestrator:(AppViewBackfillOrchestrator *)orchestrator
didCompleteBackfillForDID:(NSString *)did;

/*!
 @method orchestrator:didFailBackfillForDID:error:

 @abstract Called when a backfill attempt fails after retries.
 */
- (void)orchestrator:(AppViewBackfillOrchestrator *)orchestrator
didFailBackfillForDID:(NSString *)did
               error:(NSError *)error;

@end

/*!
 @interface AppViewBackfillOrchestrator

 @abstract Manages the backfill queue and worker pool.
 */
@interface AppViewBackfillOrchestrator : NSObject

/*! Delegate for lifecycle events. */
@property (nonatomic, weak, nullable) id<AppViewBackfillOrchestratorDelegate> delegate;

/*! PLC directory URL for DID resolution. */
@property (nonatomic, copy) NSString *plcURL;

/*! Maximum concurrent backfill workers globally. Default 8. */
@property (nonatomic, assign) NSUInteger globalWorkerCap;

/*! Maximum concurrent backfill workers per PDS host. Default 2. */
@property (nonatomic, assign) NSUInteger perHostWorkerCap;

/*! Base delay for exponential backoff (seconds). Default 1.0. */
@property (nonatomic, assign) NSTimeInterval baseBackoffSeconds;

/*! Maximum backoff delay (seconds). Default 300.0 (5 min). */
@property (nonatomic, assign) NSTimeInterval maxBackoffSeconds;

/*! Current queue depth (pending + processing). */
@property (nonatomic, readonly) NSInteger queueDepth;

/*! Active worker count. */
@property (nonatomic, readonly) NSInteger activeWorkers;

/*!
 @method initWithDatabase:indexers:plcURL:

 @param database  AppView database for state tracking.
 @param indexers  Array of indexers that process decoded ops from a repo CAR.
 @param plcURL   PLC directory URL for DID resolution.
 */
- (instancetype)initWithDatabase:(AppViewDatabase *)database
                        indexers:(NSArray<id<AppViewIndexer>> *)indexers
                        plcURL:(NSString *)plcURL;

/*!
 @method start

 @abstract Begin the orchestrator: sweep pending repos and start workers.
 */
- (void)start;

/*!
 @method stop

 @abstract Stop accepting new work. Wait for in-flight workers to finish.
 */
- (void)stop;

/*!
 @method enqueueDIDs:

 @abstract Add DIDs to the work queue. Already-processing DIDs are skipped.
 Already-synced DIDs are re-enqueued as dirty for re-check.
 */
- (void)enqueueDIDs:(NSArray<NSString *> *)dids;

/*!
 @method notifyGapDetectedForDID:atSeq:

 @abstract Called by ingest when a rev gap is detected for a repo.
 Transitions repo to dirty and re-enqueues.
 */
- (void)notifyGapDetectedForDID:(NSString *)did atSeq:(int64_t)seq;

/*!
 @method statusReport

 @abstract Returns a dictionary suitable for the admin /status endpoint.
 */
- (NSDictionary *)statusReport;

/*!
 @method queueWithLimit:cursor:status:

 @abstract Returns paginated queue entries.
 */
- (NSDictionary *)queueWithLimit:(NSInteger)limit
                           cursor:(nullable NSString *)cursor
                           status:(nullable NSString *)status;

/*!
 @method repoDetail:

 @abstract Returns detail for a specific repo.
 */
- (nullable NSDictionary *)repoDetail:(NSString *)did;

/*!
 @method retryRepo:

 @abstract Retries a failed repo.
 */
- (BOOL)retryRepo:(NSString *)did;

/*!
 @method cancelRepo:

 @abstract Cancels a repo backfill.
 */
- (BOOL)cancelRepo:(NSString *)did;

@end

NS_ASSUME_NONNULL_END
