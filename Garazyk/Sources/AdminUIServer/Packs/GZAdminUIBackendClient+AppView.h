// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract AppView administration operations used by the authenticated admin UI.
 * @discussion Each method performs a synchronous request with the configured AppView admin
 * Bearer token. It returns the upstream JSON on a 2xx response, or a dictionary containing an
 * `error` and `message` key; callers render those dictionaries rather than handling NSError.
 */
@interface GZAdminUIBackendClient (AppView)

/** @abstract Retrieves aggregate AppView metrics without changing server state. */
- (NSDictionary *)fetchAppViewMetrics;

/** @abstract Retrieves ingest health without changing server state. */
- (NSDictionary *)fetchIngestHealth;

/** @abstract Lists backfill entries, forwarding an optional status filter and pagination cursor. */
- (NSDictionary *)fetchBackfillQueueWithStatus:(nullable NSString *)status limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;

/**
 * @abstract Requests a retry of the selected repository backfill job.
 * @discussion An empty DID produces `invalid_did`; a successful call changes AppView queue state.
 */
- (NSDictionary *)retryBackfillForDID:(NSString *)did;

/** @abstract Cancels the selected repository backfill job; an empty DID returns `invalid_did`. */
- (NSDictionary *)cancelBackfillForDID:(NSString *)did;

/** @abstract Enqueues the supplied nonempty DID list for backfill and changes queue state. */
- (NSDictionary *)enqueueBackfillDIDs:(NSArray<NSString *> *)dids;

/** @abstract Starts AppView's backfill-scope rebuild and returns its upstream acknowledgement. */
- (NSDictionary *)rebuildBackfillScope;

@end

NS_ASSUME_NONNULL_END
