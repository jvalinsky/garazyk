// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class JWTMinter;
@class PDSDatabasePool;
@class PDSSpaceStore;

NS_ASSUME_NONNULL_BEGIN

/**
 * Replays local writer heads to their authoritative space hosts and syncs
 * inbound state from authorities.
 *
 * Outbound: replays local writer heads via notifyWrite so the authority's
 * writer set converges even when individual notifications are lost.
 *
 * Inbound: detects when a remote authority has advanced beyond the local
 * copy and reconciles via incremental oplog replay, lightweight
 * listRecords diff, or full-state CAR import.
 */
@interface PDSSpaceReconciler : NSObject

- (instancetype)initWithSpaceStore:(PDSSpaceStore *)spaceStore
                   userDatabasePool:(PDSDatabasePool *)userDatabasePool
                         jwtMinter:(JWTMinter *)jwtMinter
                intervalInSeconds:(NSTimeInterval)interval;
- (instancetype)init NS_UNAVAILABLE;

- (void)start;
- (void)stop;

/** Schedules an immediate best-effort reconciliation pass. */
- (void)reconcileNow;

/**
 * Runs one inbound reconciliation for a stored head and reports the selected
 * path with outbound request counts.  Only the binary scenario fixture's
 * test control plane calls this; production routes never expose it.
 */
- (void)reconcileOnceForSpace:(NSString *)space
                       author:(NSString *)author
                   completion:(void (^)(NSDictionary<NSString *, id> *result))completion;

@end

NS_ASSUME_NONNULL_END
