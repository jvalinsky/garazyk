// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAppBskyGraphPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.graph.* XRPC endpoints.
//

#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

NS_ASSUME_NONNULL_BEGIN

/**
 @brief Namespace pack for app.bsky.graph.* endpoints.
 */
/**
 * @abstract Declares the XrpcAppBskyGraphPack public API.
 */
@interface XrpcAppBskyGraphPack : NSObject <XrpcRoutePack>

@end

NS_ASSUME_NONNULL_END
