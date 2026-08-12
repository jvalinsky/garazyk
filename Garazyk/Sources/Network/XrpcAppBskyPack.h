// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  ATProtoXrpcAppBskyPack.h
//  ATProtoPDS
//
//  Domain module for app.bsky.* XRPC endpoints.
//

#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSRecordLifecycleHandler;

/**
 @brief Domain module for app.bsky.* endpoints.
 
 This module registers all Bluesky-specific XRPC endpoints including:
 - app.bsky.actor.*
 - app.bsky.feed.*
 - app.bsky.graph.*
 - app.bsky.notification.*
 
 These endpoints integrate with AppView services and support optional authentication.
 */
/**
 * @abstract Declares the ATProtoXrpcAppBskyPack public API.
 */
@interface ATProtoXrpcAppBskyPack : NSObject <XrpcRoutePack>

/**
 @brief Register only the PDS-level app.bsky.* methods.
 */
+ (void)registerPDSLevelMethodsWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                                     services:(id<XrpcRoutePackServices>)services;

/**
 @brief Register all app.bsky.* endpoint handlers (full AppView).
 */
+ (void)registerAppViewMethodsWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                                    services:(id<XrpcRoutePackServices>)services;

/**
 @brief Store the PDSRecordLifecycleHandler for the process lifetime.
 */
+ (void)setRetainedLifecycleHandler:(nullable PDSRecordLifecycleHandler *)handler;

@end

NS_ASSUME_NONNULL_END
