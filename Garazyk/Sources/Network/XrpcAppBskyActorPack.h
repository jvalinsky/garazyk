// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoXrpcAppBskyActorPack.h

 @abstract XRPC route pack for app.bsky.actor endpoints.
 */

#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"
#import "Network/XrpcRoutePack.h"

@class ATProtoXrpcDispatcher;
@class ATProtoJWTMinter;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Registers app.bsky.actor XRPC handlers.
 */
@interface ATProtoXrpcAppBskyActorPack : NSObject <XrpcRoutePack>

/** Registers PDS-level actor handlers using shared route-pack services. */
+ (void)registerPDSLevelMethodsWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                                     services:(id<XrpcRoutePackServices>)services;

/** Registers AppView actor handlers using shared route-pack services. */
+ (void)registerAppViewMethodsWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                                    services:(id<XrpcRoutePackServices>)services;

/** Registers PDS-level actor handlers using explicit dependencies. */
+ (void)registerPDSLevelMethodsWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                     jwtMinter:(nullable ATProtoJWTMinter *)jwtMinter
                               adminController:(nullable id<PDSAdminController>)adminController;

/** Registers AppView actor handlers using explicit dependencies. */
+ (void)registerAppViewMethodsWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                              appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                    jwtMinter:(nullable ATProtoJWTMinter *)jwtMinter
                              adminController:(nullable id<PDSAdminController>)adminController;

/** Registers all actor handlers supported by this pack. */
+ (void)registerWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                     jwtMinter:(nullable ATProtoJWTMinter *)jwtMinter
               adminController:(nullable id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
