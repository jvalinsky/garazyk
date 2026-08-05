// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

NS_ASSUME_NONNULL_BEGIN

/** @abstract Admin UI pack for the MST surface. */
@interface GZAdminUIMSTPack : NSObject <GZAdminUIPack>

/** @abstract Renders Merkle-search-tree account results. */
+ (NSString *)renderMSTAccountsPartial:(NSDictionary *)result;
/** @abstract Renders Merkle-search-tree nodes. */
+ (NSString *)renderMSTTreePartial:(NSDictionary *)result;
/** @abstract Renders Merkle-search-tree statistics. */
+ (NSString *)renderMSTStatsPartial:(NSDictionary *)result;

@end

NS_ASSUME_NONNULL_END
