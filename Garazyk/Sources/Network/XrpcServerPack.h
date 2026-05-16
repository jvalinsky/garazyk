// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * XrpcServerPack registers all com.atproto.server.* endpoint handlers.
 */
@interface XrpcServerPack : NSObject <XrpcRoutePack>

@end

NS_ASSUME_NONNULL_END
