// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

@class GZAdminUIHost;
@class GZSyrenaAdminSnapshot;

NS_ASSUME_NONNULL_BEGIN

@interface GZSyrenaAdminUIPack : NSObject <GZAdminUIPack>

+ (void)configureHost:(GZAdminUIHost *)host snapshot:(GZSyrenaAdminSnapshot *)snapshot;

+ (NSString *)overviewHTML:(NSDictionary *)snapshot;
+ (NSString *)ingestionHTML:(NSDictionary *)snapshot;
+ (NSString *)backfillHTML:(NSDictionary *)snapshot;
+ (NSString *)indexesHTML:(NSDictionary *)snapshot;

@end

NS_ASSUME_NONNULL_END
