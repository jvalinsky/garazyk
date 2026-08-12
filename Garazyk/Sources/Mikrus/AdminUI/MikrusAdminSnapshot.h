// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class GZMikrusMetrics;
@class GZMikrusDatabase;
@class GZMikrusConfiguration;
@class GZAppViewIngestEngine;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * _Nullable GZMikrusAdminPasswordFromFile(NSString *path,
                                                                      NSError * _Nullable * _Nullable error);

@interface GZMikrusAdminSnapshot : NSObject

- (instancetype)initWithDatabase:(GZMikrusDatabase *)database
                         metrics:(GZMikrusMetrics *)metrics
                   configuration:(GZMikrusConfiguration *)configuration
                    ingestEngine:(nullable GZAppViewIngestEngine *)ingestEngine NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSDictionary<NSString *, id> *)snapshot;

/// Per-collection record counts (limited to top N collections to avoid unbounded queries)
- (NSDictionary<NSString *, NSNumber *> *)topCollectionCounts:(NSInteger)limit;

/// Bounded error log entries (most recent N errors)
- (NSArray<NSDictionary *> *)recentErrors:(NSInteger)limit;

/// Index family statistics
- (NSDictionary<NSString *, id> *)indexFamilyStatistics;

/**
 * @abstract Lists records in a collection, ordered by URI ascending.
 * @param collection Exact collection NSID.
 * @param limit Max rows to return (clamped 1…100).
 * @param cursor Exclusive URI cursor from a previous page; nil for the first page.
 * @param nextCursor Receives the next URI cursor when more rows exist.
 */
- (NSArray<NSDictionary *> *)listRecordsInCollection:(NSString *)collection
                                               limit:(NSInteger)limit
                                              cursor:(nullable NSString *)cursor
                                          nextCursor:(NSString * _Nullable * _Nullable)nextCursor;

/**
 * @abstract Searches indexed records by URI, DID, handle, or collection NSID/prefix.
 * @param query Operator search string.
 * @param limit Max rows (clamped 1…100).
 */
- (NSArray<NSDictionary *> *)searchIndexWithQuery:(NSString *)query limit:(NSInteger)limit;

/**
 * @abstract Loads one record plus a sample of inbound backlinks for admin inspection.
 * @param uri Exact at:// URI.
 */
- (nullable NSDictionary<NSString *, id> *)recordDetailForURI:(NSString *)uri;

@end

NS_ASSUME_NONNULL_END
