// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * XrpcAdminPack registers all com.atproto.admin.* endpoint handlers.
 */
@interface XrpcAdminPack : NSObject <XrpcRoutePack>

@end

NS_ASSUME_NONNULL_END
