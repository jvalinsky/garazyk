// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class PDSSpaceStore;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Periodically removes obsolete space-record oplog revisions.
 * @discussion Each pass asks the store to retain the newest distinct revision
 * values for every repository with an oplog. Pruning affects recovery history,
 * not current records: a replica whose cursor predates retained history must
 * use the reconciler's fallback recovery path. Work runs on a private serial
 * queue; public control methods may be called from other queues.
 */
@interface PDSSpaceOplogPruner : NSObject

/**
 * @abstract Creates a stopped oplog pruner.
 * @param spaceStore The store whose repository oplogs are pruned.
 * @param retentionRevisions The retained newest distinct revisions per repository; zero disables pruning.
 * @param interval The requested timer interval; values below 300 seconds become 300.
 */
- (instancetype)initWithSpaceStore:(PDSSpaceStore *)spaceStore
                retentionRevisions:(NSUInteger)retentionRevisions
      intervalInSeconds:(NSTimeInterval)interval;

/**
 * @abstract Starts an immediate pruning pass and periodic passes.
 * @discussion Calling this method while running has no effect. A zero
 * retention configuration leaves the pruner stopped.
 */
- (void)start;

/**
 * @abstract Stops future timer-driven pruning passes.
 * @discussion This method synchronously waits for the pruner's private queue.
 */
- (void)stop;

/**
 * @abstract Enqueues one best-effort pruning pass.
 * @discussion The method returns before store work starts and has no effect
 * while stopped or when retention is zero. Store failures are logged; they are
 * not reported to the caller.
 */
- (void)pruneNow;

@end

NS_ASSUME_NONNULL_END
