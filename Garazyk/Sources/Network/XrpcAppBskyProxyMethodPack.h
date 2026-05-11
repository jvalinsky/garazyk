// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class XrpcDispatcher;

@interface XrpcAppBskyProxyMethodPack : NSObject

+ (void)registerProxyOnlyMethodsWithDispatcher:(XrpcDispatcher *)dispatcher;

@end

NS_ASSUME_NONNULL_END

