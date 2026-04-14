//
//  XrpcAppBskyActorPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.actor.* XRPC endpoints.
//  Handles actor profiles, preferences, and search.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class JWTMinter;
@class PDSDatabase;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

/**
 @brief Namespace pack for app.bsky.actor.* endpoints.
 
 Registers actor-related endpoints:
 - app.bsky.actor.getPreferences / putPreferences
 - app.bsky.actor.getProfile / getProfiles
 - app.bsky.actor.searchActors / searchActorsTypeahead
 - app.bsky.actor.getSuggestions
 */
@interface XrpcAppBskyActorPack : NSObject

/**
 @brief Register all app.bsky.actor.* endpoint handlers.
 
 @param dispatcher The XRPC dispatcher to register handlers with
 @param appViewDatabase AppView database for profile/preferences storage
 @param jwtMinter JWT token minter for authentication
 @param adminController Admin controller for takedown checks
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 appViewDatabase:(PDSDatabase *)appViewDatabase
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
