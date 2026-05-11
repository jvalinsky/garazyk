// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAppBskyNotificationPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.notification.* XRPC endpoints.
//

#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

@class XrpcDispatcher;
@class JWTMinter;
@class PDSDatabase;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

/**
 @brief Namespace pack for app.bsky.notification.* endpoints.
 */
@interface XrpcAppBskyNotificationPack : NSObject

/**
 @brief Register only the PDS-level notification methods (push registration).
 */
+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                     jwtMinter:(nullable JWTMinter *)jwtMinter
                               adminController:(nullable id<PDSAdminController>)adminController;

/**
 @brief Register the AppView-level notification methods (list notifications, unread count).
 */
+ (void)registerAppViewMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                              appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                    jwtMinter:(nullable JWTMinter *)jwtMinter
                              adminController:(nullable id<PDSAdminController>)adminController;

/**
 @brief Legacy convenience method that registers all app.bsky.notification.* endpoint handlers.
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                     jwtMinter:(nullable JWTMinter *)jwtMinter
               adminController:(nullable id<PDSAdminController>)adminController;

@end


NS_ASSUME_NONNULL_END
