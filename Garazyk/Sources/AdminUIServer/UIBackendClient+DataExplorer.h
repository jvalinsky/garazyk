// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIBackendClient (DataExplorer)

- (NSDictionary *)describeRepo:(NSString *)did;

/**
 * @abstract List records for did.
 * @param did Actor DID for the request.
 * @param collection Repository collection NSID.
 * @param limit Maximum number of records to return.
 * @param cursor Pagination cursor from a previous response.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)listRecordsForDID:(NSString *)did collection:(nullable NSString *)collection limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;

- (NSDictionary *)getRecordForDID:(NSString *)did collection:(NSString *)collection rkey:(NSString *)rkey;

- (NSDictionary *)fetchBlobsForDID:(NSString *)did limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;

- (NSDictionary *)fetchBlobForDID:(NSString *)did cid:(NSString *)cid;

@end

NS_ASSUME_NONNULL_END
