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
 @brief Register only the PDS-level (non-AppView-dependent) actor methods (preferences).
 */
+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                     jwtMinter:(nullable JWTMinter *)jwtMinter
                               adminController:(nullable id<PDSAdminController>)adminController;

/**
 @brief Register the AppView-level actor methods (profiles, search, etc).
 */
+ (void)registerAppViewMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                              appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                    jwtMinter:(nullable JWTMinter *)jwtMinter
                              adminController:(nullable id<PDSAdminController>)adminController;

/**
 @brief Legacy convenience method that registers all app.bsky.actor.* endpoint handlers.
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                     jwtMinter:(nullable JWTMinter *)jwtMinter
               adminController:(nullable id<PDSAdminController>)adminController;

@end


NS_ASSUME_NONNULL_END
