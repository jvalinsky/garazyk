// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewIndexer.h

 @abstract Protocol defining a single indexer in the materialization plane.

 @discussion Each indexer handles one logical domain of app.bsky records.
 Indexers are called from both the live ingest path and the backfill worker.

 All methods must be safe to call concurrently from multiple queues, since
 the backfill worker pool runs parallel goroutines.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AppViewIngestEvent;
@class AppViewPendingDelta;

/*!
 @protocol AppViewIndexer

 @abstract A single-domain record indexer for the AppView materialization plane.
 */
@protocol AppViewIndexer <NSObject>

/*!
 @method canIndexCollection:

 @abstract Returns YES if this indexer handles the given Lexicon collection NSID.

 @discussion Called to route records to the correct indexer. Each NSID should
 be claimed by exactly one indexer.

 @param collection NSID string (e.g. "app.bsky.feed.post")
 */
- (BOOL)canIndexCollection:(NSString *)collection;

/*!
 @method indexRecord:did:collection:rkey:cid:error:

 @abstract Index (upsert) a single record into the materialized view.

 @param record      Decoded record dictionary.
 @param did         DID of the repo the record belongs to.
 @param collection  NSID of the record's collection.
 @param rkey        The record key.
 @param cid         CID of the record.
 @param error       On validation failure, describes the problem.
 @return YES if indexed successfully, NO on validation or storage failure.
 */
- (BOOL)indexRecord:(NSDictionary *)record
                did:(NSString *)did
         collection:(NSString *)collection
               rkey:(NSString *)rkey
                cid:(nullable NSString *)cid
              error:(NSError **)error;

@optional

/*!
 @method handleIngestEvent:error:

 @abstract Called for live ingest events on the realtime path.

 @discussion This is called with a fully-decoded AppViewIngestEvent (which
 may contain multiple ops). Indexers that need to handle create/update/delete
 ops individually can implement this instead of — or in addition to —
 indexRecord:did:collection:error:.
 */
- (BOOL)handleIngestEvent:(AppViewIngestEvent *)event error:(NSError **)error;

/*!
 @method processPendingDelta:error:

 @abstract Replay a buffered pending delta after backfill completes.
 */
- (BOOL)processPendingDelta:(AppViewPendingDelta *)delta error:(NSError **)error;

/*!
 @method deleteRecord:did:collection:error:

 @abstract Remove a record from the materialized view.
 Called when a delete op is received.
 */
- (BOOL)deleteRecord:(NSString *)rkey
                 did:(NSString *)did
          collection:(NSString *)collection
               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
