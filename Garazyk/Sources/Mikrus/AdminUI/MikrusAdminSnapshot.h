// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class MikrusMetrics;
@class MikrusDatabase;
@class MikrusConfiguration;
@class AppViewIngestEngine;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * _Nullable GZMikrusAdminPasswordFromFile(NSString *path,
                                                                      NSError * _Nullable * _Nullable error);

@interface GZMikrusAdminSnapshot : NSObject

- (instancetype)initWithDatabase:(MikrusDatabase *)database
                         metrics:(MikrusMetrics *)metrics
                   configuration:(MikrusConfiguration *)configuration
                    ingestEngine:(nullable AppViewIngestEngine *)ingestEngine NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSDictionary<NSString *, id> *)snapshot;

/// Per-collection record counts (limited to top N collections to avoid unbounded queries)
- (NSDictionary<NSString *, NSNumber *> *)topCollectionCounts:(NSInteger)limit;

/// Bounded error log entries (most recent N errors)
- (NSArray<NSDictionary *> *)recentErrors:(NSInteger)limit;

/// Index family statistics
- (NSDictionary<NSString *, id> *)indexFamilyStatistics;

@end

NS_ASSUME_NONNULL_END
