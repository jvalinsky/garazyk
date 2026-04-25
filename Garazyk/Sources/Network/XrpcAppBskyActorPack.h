//
//  XrpcAppBskyActorPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.actor.* XRPC endpoints.
//  Handles actor profiles, preferences, and search.
//

#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

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
                 appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                       jwtMinter:(JWTMinter *)jwtMinter
                 adminController:(id<PDSAdminController>)adminController;

/**
 @brief Register only the PDS-level (non-AppView-dependent) actor methods.
 
 Registered endpoints:
 - app.bsky.actor.getPreferences / putPreferences
 */
+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                     jwtMinter:(JWTMinter *)jwtMinter
                               adminController:(id<PDSAdminController>)adminController;


@end

NS_ASSUME_NONNULL_END
