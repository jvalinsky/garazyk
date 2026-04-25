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
@interface XrpcAppBskyMethods : NSObject

/**
 @brief Register all app.bsky.* endpoint handlers with the dispatcher.
 
 @param dispatcher The XRPC dispatcher to register handlers with
 @param serviceDatabases Service-level database access (for appView database)
 @param jwtMinter JWT token minter for optional authentication
 @param adminController Admin operations controller for takedown checks
 @param emailProvider Pluggable email delivery system
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                       jwtMinter:(JWTMinter *)jwtMinter
                 adminController:(id<PDSAdminController>)adminController
                   emailProvider:(nullable id<PDSEmailProvider>)emailProvider;

/**
 @brief Store the RecordLifecycleHandler for the process lifetime.
 
 NSNotificationCenter does not retain observers, so the handler must be
 kept alive by a strong reference to receive PDSRecordDidChangeNotification.
 This method is called internally during registration.
 */
+ (void)setRetainedLifecycleHandler:(nullable RecordLifecycleHandler *)handler;

@end


NS_ASSUME_NONNULL_END
