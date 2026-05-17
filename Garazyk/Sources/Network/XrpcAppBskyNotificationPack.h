// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcAppBskyNotificationPack.h

 @abstract XRPC route pack for app.bsky.notification endpoints.
 */

#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"
#import "Network/XrpcRoutePack.h"

@class XrpcDispatcher;
@class JWTMinter;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Registers app.bsky.notification XRPC handlers.
 */
@interface XrpcAppBskyNotificationPack : NSObject <XrpcRoutePack>

/** Registers PDS-level notification handlers using shared route-pack services. */
+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                                     services:(id<XrpcRoutePackServices>)services;

/** Registers AppView notification handlers using shared route-pack services. */
+ (void)registerAppViewMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                                    services:(id<XrpcRoutePackServices>)services;

/** Registers PDS-level notification handlers using explicit dependencies. */
+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                     jwtMinter:(nullable JWTMinter *)jwtMinter
                               adminController:(nullable id<PDSAdminController>)adminController;

/** Registers AppView notification handlers using explicit dependencies. */
+ (void)registerAppViewMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                              appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                    jwtMinter:(nullable JWTMinter *)jwtMinter
                              adminController:(nullable id<PDSAdminController>)adminController;

/** Registers all notification handlers supported by this pack. */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                     jwtMinter:(nullable JWTMinter *)jwtMinter
               adminController:(nullable id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
