// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class GZBeskidMetrics;
@class GZBeskidDatabase;
@class GZBeskidConfiguration;

NS_ASSUME_NONNULL_BEGIN

/** Loads a nonempty admin password from a credential file without exposing its contents in errors. */
FOUNDATION_EXPORT NSString * _Nullable GZBeskidAdminPasswordFromFile(NSString *path,
                                                                      NSError * _Nullable * _Nullable error);

/** Bounded, synchronized Beskid cache server snapshot for the embedded Admin UI. */
@interface GZBeskidAdminSnapshot : NSObject

- (instancetype)initWithDatabase:(GZBeskidDatabase *)database
                         metrics:(GZBeskidMetrics *)metrics
                   configuration:(GZBeskidConfiguration *)configuration NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSDictionary<NSString *, id> *)snapshot;

@end

NS_ASSUME_NONNULL_END
