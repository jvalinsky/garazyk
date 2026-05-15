// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcRoutePackRegistrar.h

 @abstract Registers conforming XRPC route packs on a dispatcher.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class XrpcDispatcher;
@protocol XrpcRoutePack;
@protocol XrpcRoutePackServices;

@interface XrpcRoutePackRegistrar : NSObject

+ (void)registerRoutePacks:(NSArray<Class> *)routePackClasses
                dispatcher:(XrpcDispatcher *)dispatcher
                  services:(id<XrpcRoutePackServices>)services;

@end

NS_ASSUME_NONNULL_END
