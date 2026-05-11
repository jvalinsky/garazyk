// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewBackfillWorker.h

 @abstract Single-repo backfill worker: fetches repo CAR, parses, indexes.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AppViewDatabase;
@class AppViewBackfillWorker;
@class AppViewPendingDelta;
@protocol AppViewIndexer;

/*!
 @protocol AppViewBackfillWorkerDelegate

 @abstract Outcome callbacks for a single backfill attempt.
 */
@protocol AppViewBackfillWorkerDelegate <NSObject>

- (void)worker:(AppViewBackfillWorker *)worker
didCompleteForDID:(NSString *)did
       lastRev:(NSString *)lastRev;

- (void)worker:(AppViewBackfillWorker *)worker
 didFailForDID:(NSString *)did
         error:(NSError *)error
rateLimitedUntil:(nullable NSDate *)rateLimitedUntil;

@end

/*!
 @interface AppViewBackfillWorker

 @abstract Executes one backfill pass for a single DID.
 */
@interface AppViewBackfillWorker : NSObject

/*! Delegate for completion callbacks. */
@property (nonatomic, weak, nullable) id<AppViewBackfillWorkerDelegate> delegate;

/*! PLC directory URL for DID resolution. */
@property (nonatomic, copy) NSString *plcURL;

/*!
 @method initWithDID:database:indexers:plcURL:

 @param did       The repo DID to backfill.
 @param database  AppView database (for sync state updates).
 @param indexers  Indexers to call for each decoded record.
 @param plcURL   PLC directory URL for DID resolution.
 */
- (instancetype)initWithDID:(NSString *)did
                    database:(AppViewDatabase *)database
                    indexers:(NSArray<id<AppViewIndexer>> *)indexers
                    plcURL:(NSString *)plcURL;

/*!
 @method start

 @abstract Begin the backfill on a background queue. Calls delegate on completion.
 */
- (void)start;

@end

NS_ASSUME_NONNULL_END
