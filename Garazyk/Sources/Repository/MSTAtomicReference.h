// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMSTAtomicReference.h

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ATProtoMST;

/*!
 @class ATProtoMSTAtomicReference

 @brief Thread-safe wrapper for ATProtoMST objects using pthread_mutex.

 @discussion Provides atomic snapshot reads and atomic swaps of ATProtoMST objects.
 The ATProtoMST is a path-copying persistent data structure, so once published,
 it is immutable. Readers can safely access a snapshot without blocking
 other readers or the writer.

 Uses pthread_mutex instead of dispatch_queue for lower overhead —
 pthread_mutex lock/unlock is ~10-20x faster than dispatch_sync on a
 serial queue for uncontended access.

 Pattern matches PDSPerDidWriteState which uses pthread_mutex for
 per-DID serialization.
 */
/**
 * @abstract Declares the ATProtoMSTAtomicReference public API.
 */
@interface ATProtoMSTAtomicReference : NSObject {
@public
    pthread_mutex_t _mutex;
}

/*!
 @brief Initialize with an ATProtoMST object.

 @param mst The initial ATProtoMST (may be nil).
 @return A new ATProtoMSTAtomicReference.
 */
- (instancetype)initWithMST:(nullable ATProtoMST *)mst;

/*!
 @brief Get the current ATProtoMST snapshot.

 @discussion Thread-safe. Locks the mutex, retains the ATProtoMST, unlocks,
 returns it. The returned ATProtoMST is immutable once published.

 Callers should not mutate the returned ATProtoMST directly — use swapMST:
 to publish a new version.

 @return The current ATProtoMST, or nil if cleared.
 */
/**
 * @abstract Returns the current snapshot result.
 */
- (nullable ATProtoMST *)currentSnapshot;

/*!
 @brief Atomically replace the current ATProtoMST with a new one.

 @discussion Thread-safe. Locks the mutex, releases the old ATProtoMST,
 retains the new one, unlocks.

 @param newMst The new ATProtoMST to publish.
 */
- (void)swapMST:(ATProtoMST *)newMst;

/*!
 @brief Set the reference to nil.

 @discussion Equivalent to swapMST:nil but clearer intent.
 */
- (void)clear;

@end

NS_ASSUME_NONNULL_END
