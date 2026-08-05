// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

NS_ASSUME_NONNULL_BEGIN

/** @abstract Admin UI pack for the AppView surface. */
@interface GZAdminUIAppViewPack : NSObject <GZAdminUIPack>

/** @abstract Renders AppView aggregate metrics. */
+ (NSString *)renderAppViewMetricsPartial:(NSDictionary *)result;
/** @abstract Renders AppView ingest health. */
+ (NSString *)renderIngestHealthPartial:(NSDictionary *)result;
/** @abstract Renders the AppView backfill queue. */
+ (NSString *)renderBackfillQueuePartial:(NSDictionary *)result;

@end

NS_ASSUME_NONNULL_END
