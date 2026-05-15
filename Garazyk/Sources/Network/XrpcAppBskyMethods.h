// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAppBskyMethods.h
//  ATProtoPDS
//
//  Domain module for app.bsky.* XRPC endpoints.
//  Handles Bluesky-specific functionality including actor profiles, feeds,
//  social graph, and notifications.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class JWTMinter;
@class PDSServiceDatabases;
@class RecordLifecycleHandler;
@protocol PDSAdminController;
@protocol PDSEmailProvider;
@protocol XrpcRoutePackServices;

NS_ASSUME_NONNULL_BEGIN

/**
 @brief Domain module for app.bsky.* endpoints.
 
 This module registers all Bluesky-specific XRPC endpoints including:
 - app.bsky.actor.getProfile, getProfiles, searchActors, searchActorsTypeahead
 - app.bsky.feed.getAuthorFeed, getTimeline, getActorLikes, getPostThread, getPosts
 - app.bsky.graph.getFollowers, getFollows
 - app.bsky.notification.listNotifications, getUnreadCount, updateSeen
 
 These endpoints integrate with AppView services (ActorService, FeedService, NotificationService)
 and support optional authentication for personalized results.
 */
@class PDSRecordService;

@interface XrpcAppBskyMethods : NSObject

/**
 @brief Register only the PDS-level app.bsky.* methods.
 */
+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                             serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                recordService:(nullable PDSRecordService *)recordService
                                    jwtMinter:(nullable JWTMinter *)jwtMinter
                              adminController:(nullable id<PDSAdminController>)adminController
                                emailProvider:(nullable id<PDSEmailProvider>)emailProvider
                            routePackServices:(nullable id<XrpcRoutePackServices>)routePackServices;

/**
 @brief Register all app.bsky.* endpoint handlers.
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                 recordService:(nullable PDSRecordService *)recordService
                     jwtMinter:(nullable JWTMinter *)jwtMinter
               adminController:(nullable id<PDSAdminController>)adminController
                 emailProvider:(nullable id<PDSEmailProvider>)emailProvider
             routePackServices:(nullable id<XrpcRoutePackServices>)routePackServices;

/**
 @brief Store the RecordLifecycleHandler for the process lifetime.
 
 NSNotificationCenter does not retain observers, so the handler must be
 kept alive by a strong reference to receive PDSRecordDidChangeNotification.
 This method is called internally during registration.
 */
+ (void)setRetainedLifecycleHandler:(nullable RecordLifecycleHandler *)handler;

@end


NS_ASSUME_NONNULL_END
