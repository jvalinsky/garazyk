// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

NS_ASSUME_NONNULL_BEGIN

@class ATProtoXrpcDispatcher;

@interface ATProtoXrpcAppBskyProxyMethodPack : NSObject <XrpcRoutePack>

/*! Legacy entry point retained for call sites not yet on @c XrpcRoutePackServices. */
+ (void)registerProxyOnlyMethodsWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher;

@end

NS_ASSUME_NONNULL_END
