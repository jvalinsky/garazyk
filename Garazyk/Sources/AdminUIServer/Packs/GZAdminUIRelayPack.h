// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

NS_ASSUME_NONNULL_BEGIN

/** @abstract Admin UI pack for the Relay surface. */
@interface GZAdminUIRelayPack : NSObject <GZAdminUIPack>

/** @abstract Renders relay metrics. */
+ (NSString *)renderRelayMetricsPartial:(NSDictionary *)result;
/** @abstract Renders relay upstream status. */
+ (NSString *)renderRelayUpstreamsPartial:(NSDictionary *)result;
/** @abstract Renders relay health. */
+ (NSString *)renderRelayHealthPartial:(NSDictionary *)result;

@end

NS_ASSUME_NONNULL_END
