// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

@class GZAdminUIHost;
@class JelczAdminSnapshot;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Embedded admin UI pack for the Jelcz video processing service.
 *
 * @discussion Registers direct routes that read from an attached
 *             JelczAdminSnapshot for real-time worker/queue counters.
 *             Follows the same pattern as GZMikrusAdminUIPack.
 */
@interface JelczAdminUIPack : NSObject <GZAdminUIPack>

+ (void)configureHost:(GZAdminUIHost *)host snapshot:(JelczAdminSnapshot *)snapshot;

@end

NS_ASSUME_NONNULL_END
