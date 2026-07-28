// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;

/*!
 @class PDSPasswordResetTokenPruner

 @abstract Periodically removes expired, unused rows from the
 password_reset_tokens table.

 @discussion Password-reset and account-deletion tokens have a 15-minute TTL.
 Once expired, they are never used again. Without periodic cleanup, the
 password_reset_tokens table grows unboundedly — one row per password-reset
 or account-delete request, every 15 minutes, indefinitely. This pruner
 runs on a configurable interval (default 5 minutes) and deletes all rows
 where expires_at < now.
 */
@interface PDSPasswordResetTokenPruner : NSObject

/*!
 @method initWithServiceDatabases:intervalInSeconds:

 @param serviceDatabases Service databases for raw sqlite3 access.
 @param interval Minimum interval between prune cycles in seconds
        (clamped to 300 minimum).
 */
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                       intervalInSeconds:(NSTimeInterval)interval;

/*! Start periodic pruning. Safe to call multiple times. */
- (void)start;

/*! Stop periodic pruning and release the timer. */
- (void)stop;

/*! Trigger an immediate prune cycle (does not affect the schedule). */
- (void)pruneNow;

@end

NS_ASSUME_NONNULL_END
