#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class JWTMinter;
@class PDSServiceDatabases;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

/**
 * XrpcModerationMethods registers all com.atproto.moderation.* endpoint handlers.
 *
 * This module handles moderation operations including:
 * - Reporting: createReport
 */
@interface XrpcModerationMethods : NSObject

/**
 * Register all com.atproto.moderation.* endpoint handlers with the dispatcher.
 *
 * @param dispatcher The XRPC dispatcher to register handlers with
 * @param jwtMinter JWT token minter for authentication
 * @param adminController Admin controller for authorization checks
 * @param serviceDatabases Service-level database access
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases;

@end

NS_ASSUME_NONNULL_END
