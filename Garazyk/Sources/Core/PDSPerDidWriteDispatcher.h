// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSPerDidWriteDispatcher.h

 @abstract Per-DID write dispatcher: serializes writes for the same DID while
 allowing writes for different DIDs to proceed concurrently.

 @discussion Replaces the single global write queue in PDSRecordService with a
 bounded concurrent worker pool. Each DID's writes are serialized via a
 per-DID pthread_mutex, but writes for different DIDs run in parallel (up to
 the concurrency limit).

 This avoids the thread explosion that would result from creating one
 dispatch_queue_t per DID on Linux/GNUstep, where libdispatch lacks the
 kernel workqueue integration that macOS provides.

 Architecture:
 - Concurrent dispatch queue as the worker pool (configurable lane count)
 - Counting semaphore to bound total concurrent writers
 - Per-DID state (pthread_mutex + pending work queue + active flag)
 - Serial queue to protect the DID -> state map
 - Idle eviction timer to reclaim memory for inactive DIDs

 Thread safety: All public methods are thread-safe.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Compat/PDSTypes.h"

NS_ASSUME_NONNULL_BEGIN

/*!

 @abstract A block that performs a write operation for a specific DID.

 @discussion The block is called on the worker pool queue. It must not
 block indefinitely or call dispatch_sync back into the dispatcher.
 */
typedef void (^PDSWriteBlock)(void);

/*!
 @class PDSPerDidWriteDispatcher

 @abstract Dispatches write operations per-DID with serialization guarantees.

 @discussion Writes for the same DID are always executed sequentially.
 Writes for different DIDs execute concurrently, bounded by the
 concurrency limit.

 Usage:
 @code
 PDSPerDidWriteDispatcher *dispatcher = [[PDSPerDidWriteDispatcher alloc]
     initWithConcurrencyLimit:32 idleEvictionSeconds:60];

 [dispatcher dispatchWriteForDid:@"did:plc:abc123" block:^{
     // ... perform write ...
 }];
 @endcode
 */
@interface PDSPerDidWriteDispatcher : NSObject

/*!
 @method initWithConcurrencyLimit:idleEvictionSeconds:

 @abstract Initialize the dispatcher.

 @param concurrencyLimit Maximum number of concurrent writers. Must be > 0.
 @param idleEvictionSeconds Seconds before idle per-DID state is evicted.
        0 disables eviction.
 @return Initialized dispatcher instance.
 */
- (instancetype)initWithConcurrencyLimit:(NSUInteger)concurrencyLimit
                    idleEvictionSeconds:(NSTimeInterval)idleEvictionSeconds;

/*!
 @method dispatchWriteForDid:block:

 @abstract Dispatch a write operation for a specific DID.

 @discussion If no write is currently in progress for the given DID, the
 block executes immediately (subject to the concurrency limit). If a write
 is already in progress, the block is queued and will execute after the
 current write completes.

 The block is called on a background queue. Callers must not call
 dispatch_sync back into this dispatcher from within the block.

 @param did The DID this write belongs to.
 @param block The write operation to perform.
 */
- (void)dispatchWriteForDid:(NSString *)did block:(PDSWriteBlock)block;

/*!
 @method activeDidCount

 @abstract Number of DIDs with writes currently in progress.

 @discussion Useful for monitoring and diagnostics.
 */
@property (nonatomic, readonly) NSUInteger activeDidCount;

/*!
 @method pendingWriteCount

 @abstract Total number of pending writes across all DIDs.

 @discussion Useful for monitoring and diagnostics.
 */
@property (nonatomic, readonly) NSUInteger pendingWriteCount;

/*!
 @method totalDidCount

 @abstract Total number of DIDs with state (active + pending).

 @discussion Includes DIDs that are currently active and those with
 pending writes. Idle DIDs that have been evicted are not counted.
 */
@property (nonatomic, readonly) NSUInteger totalDidCount;

/*!
 @property concurrencyLimit

 @abstract Maximum number of concurrent writers.
 */
@property (nonatomic, readonly) NSUInteger concurrencyLimit;

/*!
 @property idleEvictionSeconds

 @abstract Seconds before idle per-DID state is evicted. 0 disables.
 */
@property (nonatomic, readonly) NSTimeInterval idleEvictionSeconds;

@end

NS_ASSUME_NONNULL_END
