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
 *
 * Authentication Flow:
 * 1. Parse Authorization header (Bearer or DPoP)
 * 2. For DPoP: Verify DPoP proof and extract thumbprint
 * 3. Parse and verify JWT signature
 * 4. Validate DPoP binding (if applicable)
 * 5. Check account takedown status
 * 6. Return authenticated DID or nil on failure
 *
 * DPoP Nonce Challenge:
 * When DPoP verification fails due to missing nonce, the helper sets:
 * - HTTP 401 status
 * - DPoP-Nonce header with generated nonce
 * - WWW-Authenticate header with "use_dpop_nonce" error
 * - JSON error body
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

/**
 * Extract and validate DID from Authorization header with response object.
 *
 * This variant allows setting error responses (e.g., DPoP nonce challenge).
 *
 * @param authHeader Authorization header value (Bearer or DPoP)
 * @param jwtMinter JWT minter for signature verification
 * @param adminController Admin controller for takedown checks
 * @param request HTTP request for DPoP URL construction
 * @param response HTTP response for setting error details (optional)
 * @return Authenticated DID or nil on failure
 */
+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                      jwtMinter:(JWTMinter *)jwtMinter
                                adminController:(id<PDSAdminController>)adminController
                                        request:(HttpRequest *)request
                                       response:(nullable HttpResponse *)response;

/**
 * Extract and validate DID from Authorization header using PDSController.
 *
 * Convenience method that extracts jwtMinter and adminController from controller.
 *
 * @param authHeader Authorization header value (Bearer or DPoP)
 * @param controller PDS controller containing jwtMinter and adminController
 * @param request HTTP request for DPoP URL construction
 * @param response HTTP response for setting error details (optional)
 * @return Authenticated DID or nil on failure
 */
+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                     controller:(PDSController *)controller
                                        request:(HttpRequest *)request
                                       response:(nullable HttpResponse *)response;

/**
 * Authorize admin request by validating authentication and admin privileges.
 *
 * This method:
 * 1. Extracts and validates DID from Authorization header
 * 2. Checks admin authentication via PDSAdminAuth
 * 3. Sets appropriate error response on failure
 *
 * @param request HTTP request containing Authorization header
 * @param response HTTP response for setting error details
 * @param serviceDatabases Service databases for account lookups
 * @param jwtMinter JWT minter for signature verification
 * @param adminController Admin controller for takedown checks
 * @return YES if authorized, NO if authentication or authorization failed
 */
+ (BOOL)authorizeAdminRequest:(HttpRequest *)request
                      response:(HttpResponse *)response
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
