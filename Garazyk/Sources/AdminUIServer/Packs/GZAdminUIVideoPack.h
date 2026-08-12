// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

NS_ASSUME_NONNULL_BEGIN

/** @abstract Admin UI pack for the Video surface. */
@interface GZAdminUIVideoPack : NSObject <GZAdminUIPack>

/** @abstract Renders the overview dashboard (health, worker, queue, throughput, storage). */
+ (NSString *)renderVideoOverviewPartial:(NSDictionary *)snapshot;

/** @abstract Renders video-service health. */
+ (NSString *)renderVideoHealthPartial:(NSDictionary *)result;

/** @abstract Renders video-job results. */
+ (NSString *)renderVideoJobsPartial:(NSDictionary *)result;

/** @abstract Renders a video-job detail result (allowlisted keys only). */
+ (NSString *)renderVideoJobDetailPartial:(NSDictionary *)result;

/** @abstract Renders capacity and configuration summary. */
+ (NSString *)renderVideoCapacityPartial:(NSDictionary *)result;

/** @abstract Renders video quota information. */
+ (NSString *)renderVideoQuotasPartial:(NSDictionary *)result;

@end

NS_ASSUME_NONNULL_END
