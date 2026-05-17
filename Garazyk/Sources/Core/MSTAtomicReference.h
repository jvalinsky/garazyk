// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file MSTAtomicReference.h

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MST;

/*!
 @class MSTAtomicReference

 @brief Thread-safe wrapper for MST objects using pthread_mutex.

 @discussion Provides atomic snapshot reads and atomic swaps of MST objects.
 The MST is a path-copying persistent data structure, so once published,
 it is immutable. Readers can safely access a snapshot without blocking
 other readers or the writer.

 Uses pthread_mutex instead of dispatch_queue for lower overhead —
 pthread_mutex lock/unlock is ~10-20x faster than dispatch_sync on a
 serial queue for uncontended access.

 Pattern matches PDSPerDidWriteState which uses pthread_mutex for
 per-DID serialization.
 */
/**
 * @abstract Declares the MSTAtomicReference public API.
 */
@interface MSTAtomicReference : NSObject {
@public
    pthread_mutex_t _mutex;
}

/*!
 @brief Initialize with an MST object.

 @param mst The initial MST (may be nil).
 @return A new MSTAtomicReference.
 */
- (instancetype)initWithMST:(nullable MST *)mst;

/*!
 @brief Get the current MST snapshot.

 @discussion Thread-safe. Locks the mutex, retains the MST, unlocks,
 returns it. The returned MST is immutable once published.

 Callers should not mutate the returned MST directly — use swapMST:
 to publish a new version.

 @return The current MST, or nil if cleared.
 */
/**
 * @abstract Returns the current snapshot result.
 */
- (nullable MST *)currentSnapshot;

/*!
 @brief Atomically replace the current MST with a new one.

 @discussion Thread-safe. Locks the mutex, releases the old MST,
 retains the new one, unlocks.

 @param newMst The new MST to publish.
 */
- (void)swapMST:(MST *)newMst;

/*!
 @brief Set the reference to nil.

 @discussion Equivalent to swapMST:nil but clearer intent.
 */
- (void)clear;

@end

NS_ASSUME_NONNULL_END
