//
//  XrpcIdentityMethods.h
//  ATProtoPDS
//
//  Domain module for com.atproto.identity.* XRPC endpoints.
//  Handles identity resolution, handle updates, and PLC operations.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class JWTMinter;
@class PDSServiceDatabases;
@class PDSDatabasePool;
@class PDSConfiguration;
@protocol PDSAdminController;
@protocol PDSEmailProvider;

NS_ASSUME_NONNULL_BEGIN

/**
 * XrpcIdentityMethods registers all com.atproto.identity.* endpoint handlers.
 *
 * Endpoints handled:
 * - com.atproto.identity.resolveHandle: Resolve handle to DID
 * - com.atproto.identity.updateHandle: Update account handle (requires auth)
 * - com.atproto.identity.getRecommendedDidCredentials: Get recommended DID credentials
 * - com.atproto.identity.requestPlcOperationSignature: Request PLC operation token (requires auth)
 * - com.atproto.identity.signPlcOperation: Sign PLC operation (requires auth)
 * - com.atproto.identity.submitPlcOperation: Submit PLC operation to directory (requires auth)
 * - com.atproto.identity.resolveDid: Resolve DID document
 * - com.atproto.identity.resolveIdentity: Resolve identifier to identity info
 * - com.atproto.identity.refreshIdentity: Refresh identity info
 *
 * This module uses:
 * - XrpcAuthHelper for authentication
 * - XrpcIdentityHelper for handle resolution
 * - XrpcErrorHelper for error responses
 */
@interface XrpcIdentityMethods : NSObject

/**
 * Register all com.atproto.identity.* endpoint handlers with the dispatcher.
 *
 * @param dispatcher The XRPC dispatcher to register endpoints with
 * @param jwtMinter JWT token minter for authentication
 * @param adminController Admin controller for takedown checks
 * @param serviceDatabases Service-level database access
 * @param userDatabasePool User-level database pool
 * @param configuration Server configuration
 * @param emailProvider Email provider for PLC operation tokens
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
              userDatabasePool:(PDSDatabasePool *)userDatabasePool
                 configuration:(PDSConfiguration *)configuration
                 emailProvider:(nullable id<PDSEmailProvider>)emailProvider;

@end

NS_ASSUME_NONNULL_END
