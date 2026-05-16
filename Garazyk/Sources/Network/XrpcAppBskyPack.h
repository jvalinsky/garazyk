// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAppBskyPack.h
//  ATProtoPDS
//
//  Domain module for app.bsky.* XRPC endpoints.
//

#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

NS_ASSUME_NONNULL_BEGIN

@class RecordLifecycleHandler;

/**
 @brief Domain module for app.bsky.* endpoints.
 
 This module registers all Bluesky-specific XRPC endpoints including:
 - app.bsky.actor.*
 - app.bsky.feed.*
 - app.bsky.graph.*
 - app.bsky.notification.*
 
 These endpoints integrate with AppView services and support optional authentication.
 */
@interface XrpcAppBskyPack : NSObject <XrpcRoutePack>

/**
 @brief Register only the PDS-level app.bsky.* methods.
 */
+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                                     services:(id<XrpcRoutePackServices>)services;

/**
 @brief Register all app.bsky.* endpoint handlers (full AppView).
 */
+ (void)registerAppViewMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                                    services:(id<XrpcRoutePackServices>)services;

/**
 @brief Store the RecordLifecycleHandler for the process lifetime.
 */
+ (void)setRetainedLifecycleHandler:(nullable RecordLifecycleHandler *)handler;

@end

NS_ASSUME_NONNULL_END
