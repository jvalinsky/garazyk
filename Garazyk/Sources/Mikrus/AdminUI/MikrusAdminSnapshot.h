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

@end

NS_ASSUME_NONNULL_END
