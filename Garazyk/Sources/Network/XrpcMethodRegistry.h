// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSApplication;
@class PDSController;
@class JWTMinter;
/**
 * @abstract Defines the PDSAdminController protocol contract.
 */
@protocol PDSAdminController;

/**
 @header XrpcMethodRegistry.h

 @abstract XRPC method registration orchestration.

 @discussion This header defines the XrpcMethodRegistry class which orchestrates
 the registration of all ATProto XRPC methods with a dispatcher by delegating to
 domain-specific modules.
 
 Architecture:
 XrpcMethodRegistry is a thin orchestration layer that:
 1. Extracts services from PDSApplication or PDSController
 2. Delegates endpoint registration to namespace packs using the XrpcRoutePack protocol:
    - XrpcServerPack: com.atproto.server.* endpoints
    - XrpcRepoPack: com.atproto.repo.* endpoints
    - XrpcSyncPack: com.atproto.sync.* endpoints
    - XrpcIdentityPack: com.atproto.identity.* endpoints
    - XrpcAdminPack: com.atproto.admin.* endpoints
    - XrpcLabelPack: com.atproto.label.* and com.atproto.temp.* endpoints
    - XrpcModerationPack: com.atproto.moderation.* endpoints
    - XrpcVendorPack: tools.garazyk.* endpoints
    - XrpcAppBskyPack: app.bsky.* endpoints
 3. Installs proxy interceptor for request forwarding
 
 Domain modules use helper modules for shared functionality:
 - XrpcAuthHelper: JWT and DPoP authentication
 - XrpcIdentityHelper: Handle and DID resolution
 - XrpcErrorHelper: Standardized error responses
 
 Service Dependency Injection:
 All required services are extracted from PDSApplication and passed to domain
 modules as parameters. This explicit dependency injection makes service
 requirements clear and avoids hidden state.
 
 Module Registration Order:
 Domain modules are registered in a specific order to ensure dependencies are
 satisfied. Some endpoints may depend on others being registered first.
 */

/**
 @class XrpcMethodRegistry

 @abstract Orchestrates registration of all ATProto XRPC methods.

 @discussion XrpcMethodRegistry is a thin orchestration layer (~250 lines) that
 delegates endpoint registration to domain-specific modules. It extracts services
 from PDSApplication, passes them to domain modules via dependency injection, and
 ensures modules are registered in the correct order.
 
 The registry maintains backward compatibility with the original monolithic
 implementation while providing a modular architecture for maintainability.
 */
@interface XrpcMethodRegistry : NSObject

/**
 @brief Register the ATProto XRPC method handlers with the dispatcher.

 @param dispatcher Dispatcher to register methods on.
 @param controller Backend controller that implements the handlers.

 @note This method is provided for backward compatibility. For new code,
 prefer registerMethodsWithDispatcher:application: which uses services directly.
 */
+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller;

/**
 @brief Register the ATProto XRPC method handlers using PDSApplication services.

 @param dispatcher Dispatcher to register methods on.
 @param application The PDSApplication providing services.

 @discussion This method registers XRPC handlers that use the application's
 services directly, without depending on PDSController.
 */
+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                          application:(PDSApplication *)application;

@end

NS_ASSUME_NONNULL_END
