// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSApplication;
@class PDSController;
@class ATProtoJWTMinter;
/**
 * @abstract Defines the PDSAdminController protocol contract.
 */
@protocol PDSAdminController;

/**
 @header ATProtoXrpcMethodRegistry.h

 @abstract XRPC method registration orchestration.

 @discussion This header defines the ATProtoXrpcMethodRegistry class which orchestrates
 the registration of all ATProto XRPC methods with a dispatcher by delegating to
 domain-specific modules.
 
 Architecture:
 ATProtoXrpcMethodRegistry is a thin orchestration layer that:
 1. Extracts services from PDSApplication or PDSController
 2. Delegates endpoint registration to namespace packs using the XrpcRoutePack protocol:
    - ATProtoXrpcServerPack: com.atproto.server.* endpoints
    - ATProtoXrpcRepoPack: com.atproto.repo.* endpoints
    - ATProtoXrpcSyncPack: com.atproto.sync.* endpoints
    - ATProtoXrpcIdentityPack: com.atproto.identity.* endpoints
    - ATProtoXrpcAdminPack: com.atproto.admin.* endpoints
    - ATProtoXrpcLabelPack: com.atproto.label.* and com.atproto.temp.* endpoints
    - ATProtoXrpcModerationPack: com.atproto.moderation.* endpoints
    - ATProtoXrpcVendorPack: tools.garazyk.* endpoints
    - ATProtoXrpcAppBskyPack: app.bsky.* endpoints
 3. Installs proxy interceptor for request forwarding
 
 Domain modules use helper modules for shared functionality:
 - ATProtoXrpcAuthHelper: ATProtoJWT and DPoP authentication
 - ATProtoXrpcIdentityHelper: Handle and DID resolution
 - ATProtoXrpcErrorHelper: Standardized error responses
 
 Service Dependency Injection:
 All required services are extracted from PDSApplication and passed to domain
 modules as parameters. This explicit dependency injection makes service
 requirements clear and avoids hidden state.
 
 Module Registration Order:
 Domain modules are registered in a specific order to ensure dependencies are
 satisfied. Some endpoints may depend on others being registered first.
 */

/**
 @class ATProtoXrpcMethodRegistry

 @abstract Orchestrates registration of all ATProto XRPC methods.

 @discussion ATProtoXrpcMethodRegistry is a thin orchestration layer (~250 lines) that
 delegates endpoint registration to domain-specific modules. It extracts services
 from PDSApplication, passes them to domain modules via dependency injection, and
 ensures modules are registered in the correct order.
 
 The registry maintains backward compatibility with the original monolithic
 implementation while providing a modular architecture for maintainability.
 */
@interface ATProtoXrpcMethodRegistry : NSObject

/**
 @brief Register the ATProto XRPC method handlers with the dispatcher.

 @param dispatcher Dispatcher to register methods on.
 @param controller Backend controller that implements the handlers.

 @note This method is provided for backward compatibility. For new code,
 prefer registerMethodsWithDispatcher:application: which uses services directly.
 */
+ (void)registerMethodsWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller;

/**
 @brief Register the ATProto XRPC method handlers using PDSApplication services.

 @param dispatcher Dispatcher to register methods on.
 @param application The PDSApplication providing services.

 @discussion This method registers XRPC handlers that use the application's
 services directly, without depending on PDSController.
 */
+ (void)registerMethodsWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                          application:(PDSApplication *)application;

@end

NS_ASSUME_NONNULL_END
