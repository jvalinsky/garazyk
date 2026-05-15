// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcRoutePack.h

 @abstract Contract for XRPC method registration modules.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class XrpcDispatcher;
@protocol XrpcRoutePackServices;

/*!
 @protocol XrpcRoutePack

 @abstract Registers a cohesive set of XRPC NSIDs on a dispatcher.

 @discussion Route packs receive shared dependencies through
 @c XrpcRoutePackServices instead of long per-pack parameter lists.
 New and legacy registration APIs may coexist during migration.
 */
@protocol XrpcRoutePack <NSObject>

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services;

@optional

/*! Stable identifier used for logging and future discovery. */
+ (NSString *)routePackIdentifier;

@end

NS_ASSUME_NONNULL_END
