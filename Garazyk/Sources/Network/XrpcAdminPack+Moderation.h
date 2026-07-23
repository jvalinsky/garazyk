// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#pragma once

#import "Network/XrpcAdminPack.h"
#import "Network/XrpcRoutePackServices.h"

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAdminPack (Moderation)
+ (void)registerModerationEndpoints:(XrpcDispatcher *)dispatcher
                services:(id<XrpcRoutePackServices>)services;
@end

NS_ASSUME_NONNULL_END
