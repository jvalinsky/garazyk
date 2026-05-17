// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * XrpcIdentityPack registers all com.atproto.identity.* endpoint handlers.
 */
/**
 * @abstract Declares the XrpcIdentityPack public API.
 */
@interface XrpcIdentityPack : NSObject <XrpcRoutePack>

@end

NS_ASSUME_NONNULL_END
