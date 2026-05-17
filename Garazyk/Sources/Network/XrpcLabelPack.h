// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * XrpcLabelPack registers all com.atproto.label.* and com.atproto.temp.* endpoint handlers.
 */
/**
 * @abstract Declares the XrpcLabelPack public API.
 */
@interface XrpcLabelPack : NSObject <XrpcRoutePack>

@end

NS_ASSUME_NONNULL_END
