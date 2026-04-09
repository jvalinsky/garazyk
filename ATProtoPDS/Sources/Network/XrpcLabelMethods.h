#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class PDSServiceDatabases;
@class JWTMinter;
@protocol PDSAdminController;
@class PDSConfiguration;

/**
 * XrpcLabelMethods registers all com.atproto.label.* and com.atproto.temp.* endpoint handlers.
 *
 * This module handles:
 * - com.atproto.label.queryLabels: Query labels with filtering
 * - com.atproto.label.createLabel: Create moderation labels (admin only)
 * - com.atproto.label.getLabels: Get labels by URI patterns (admin only)
 * - com.atproto.label.subscribeLabels: WebSocket label subscription (upgrade-required handler)
 * - com.atproto.temp.fetchLabels: Deprecated label fetching (includes sunset headers)
 * - com.atproto.temp.requestPhoneVerification: Phone verification requests
 */
@interface XrpcLabelMethods : NSObject

/**
 * Register all label and temp endpoint handlers with the dispatcher.
 *
 * @param dispatcher The XRPC dispatcher to register endpoints with
 * @param serviceDatabases Service-level database access
 * @param jwtMinter JWT token minter for authentication
 * @param adminController Admin operations controller
 * @param configuration Server configuration
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
                 configuration:(PDSConfiguration *)configuration;

@end
