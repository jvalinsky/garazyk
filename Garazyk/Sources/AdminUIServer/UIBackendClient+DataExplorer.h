// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Read-only PDS repository and blob inspection operations.
 * @discussion All methods use the PDS administrative transport and block for their request. They
 * return upstream JSON on success, or a dictionary with `error` and `message` on validation or
 * upstream failure. List calls forward cursors; a zero limit is normalized by the implementation.
 */
@interface UIBackendClient (DataExplorer)

/** @abstract Retrieves repository metadata for a nonempty DID. */
- (NSDictionary *)describeRepo:(NSString *)did;

/**
 * @abstract Lists records for a nonempty DID with optional collection and cursor filters.
 */
- (NSDictionary *)listRecordsForDID:(NSString *)did collection:(nullable NSString *)collection limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;

/** @abstract Retrieves the record identified by nonempty DID, collection, and record key values. */
- (NSDictionary *)getRecordForDID:(NSString *)did collection:(NSString *)collection rkey:(NSString *)rkey;

/** @abstract Lists blobs for a nonempty DID, forwarding optional limit and cursor values. */
- (NSDictionary *)fetchBlobsForDID:(NSString *)did limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;

/** @abstract Requests the blob response for nonempty DID and ATProtoCID values. */
- (NSDictionary *)fetchBlobForDID:(NSString *)did cid:(NSString *)cid;

@end

NS_ASSUME_NONNULL_END
