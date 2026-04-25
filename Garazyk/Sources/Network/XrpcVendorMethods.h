//
//  XrpcVendorMethods.h
//  ATProtoPDS
//
//  Domain module for tools.garazyk.* vendor XRPC endpoints.
//  Handles vendor-specific extensions to the AT Protocol surface.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class JWTMinter;
@class PDSServiceDatabases;
@class PDSRepositoryService;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

/**
 * XrpcVendorMethods registers all tools.garazyk.* endpoint handlers.
 *
 * Endpoints handled:
 * - tools.garazyk.account.getUsage: Get storage usage for the authenticated account
 * - tools.garazyk.sync.getRepoFiltered: Get a filtered CAR export for selected collections
 *
 * This module uses:
 * - XrpcAuthHelper for authentication
 * - XrpcErrorHelper for error responses
 */
@interface XrpcVendorMethods : NSObject

/**
 * Register all tools.garazyk.* endpoint handlers with the dispatcher.
 *
 * @param dispatcher The XRPC dispatcher to register endpoints with
 * @param serviceDatabases Service-level database access
 * @param jwtMinter JWT token minter for authentication
 * @param adminController Admin controller for takedown checks
 * @param repositoryService Repository service (provides database pool for actor store access)
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
             repositoryService:(PDSRepositoryService *)repositoryService;

@end

NS_ASSUME_NONNULL_END
