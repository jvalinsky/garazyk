// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAuthHelper.h
//  ATProtoPDS
//
//  Authentication helper for XRPC endpoints.
//  Centralizes JWT and DPoP authentication logic for extracting and validating DIDs
//  from Authorization headers.
//

#import <Foundation/Foundation.h>

@class HttpRequest;
@class HttpResponse;
@class JWTMinter;
@class PDSController;
@class PDSServiceDatabases;
@protocol PDSAdminController;
@protocol PDSSessionRepository;
@protocol XrpcRoutePackServices;

NS_ASSUME_NONNULL_BEGIN

/**
 * XrpcAuthHelper provides centralized authentication logic for XRPC endpoints.
 *
 * Responsibilities:
 * - Extract and validate DIDs from Authorization headers
 * - Support Bearer tokens (JWT) and DPoP tokens
 * - Verify JWT signatures with algorithm selection
 * - Validate DPoP proofs and thumbprint binding
 * - Handle DPoP nonce challenges
 * - Reject takedown accounts
 * - Enforce admin authorization
 */
@interface XrpcAuthHelper : NSObject

/**
 * Extract and validate DID from Authorization header.
 *
 * @param authHeader Authorization header value (Bearer or DPoP)
 * @param jwtMinter JWT minter for signature verification
 * @param adminController Admin controller for takedown checks
 * @param request HTTP request for DPoP URL construction
 * @return Authenticated DID or nil on failure
 */
+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                       jwtMinter:(JWTMinter *)jwtMinter
                                 adminController:(id<PDSAdminController>)adminController
                                         request:(HttpRequest *)request;

+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                       jwtMinter:(JWTMinter *)jwtMinter
                                 adminController:(nullable id<PDSAdminController>)adminController
                                         request:(HttpRequest *)request
                                        response:(nullable HttpResponse *)response;

/**
 * Extract and validate DID from Authorization header with response object and session repository.
 */
+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                      jwtMinter:(JWTMinter *)jwtMinter
                                adminController:(nullable id<PDSAdminController>)adminController
                              sessionRepository:(nullable id<PDSSessionRepository>)sessionRepository
                                        request:(HttpRequest *)request
                                       response:(nullable HttpResponse *)response;

/**
 * Extract and validate DID from Authorization header using XrpcRoutePackServices.
 */
+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                       services:(id<XrpcRoutePackServices>)services
                                        request:(HttpRequest *)request
                                       response:(nullable HttpResponse *)response;

/**
 * Extract and validate DID from Authorization header using PDSController.
 */
+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                     controller:(PDSController *)controller
                                        request:(HttpRequest *)request
                                       response:(nullable HttpResponse *)response;

/**
 * Authorize admin request by validating authentication and admin privileges.
 */
+ (BOOL)authorizeAdminRequest:(HttpRequest *)request
                      response:(HttpResponse *)response
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
