// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcErrorHelper.h
//  ATProtoPDS
//
//  Error response helper for XRPC endpoints.
//  Standardizes XRPC error response construction for consistent error formats.
//

#import <Foundation/Foundation.h>
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * XrpcErrorHelper provides standardized error response construction for XRPC endpoints.
 *
 * Responsibilities:
 * - Construct standard XRPC error responses with consistent JSON format
 * - Set appropriate HTTP status codes
 * - Provide convenience methods for common error scenarios
 *
 * Standard Error Format:
 * {
 *   "error": "<ErrorCode>",
 *   "message": "<Human-readable description>"
 * }
 *
 * Standard Error Codes:
 * - AuthRequired: Authentication required but not provided (401)
 * - Forbidden: Authenticated but not authorized (403)
 * - InvalidRequest: Request validation failed (400)
 * - NotFound: Requested resource not found (404)
 * - InternalServerError: Server-side error (500)
 * - MethodNotAllowed: HTTP method not allowed (405)
 */
/**
 * @abstract Declares the XrpcErrorHelper public API.
 */
@interface XrpcErrorHelper : NSObject

#pragma mark - Standard Error Responses

/**
 * Set authentication error response (401 Unauthorized).
 *
 * @param response HTTP response to modify
 * @param message Error message (defaults to "Authentication required")
 */
+ (void)setAuthenticationError:(HttpResponse *)response
                       message:(nullable NSString *)message;

/**
 * Set authorization error response (403 Forbidden).
 *
 * @param response HTTP response to modify
 * @param message Error message (defaults to "Forbidden")
 */
+ (void)setAuthorizationError:(HttpResponse *)response
                      message:(nullable NSString *)message;

/**
 * Set validation error response (400 Bad Request).
 *
 * @param response HTTP response to modify
 * @param message Error message (defaults to "Invalid request")
 */
+ (void)setValidationError:(HttpResponse *)response
                   message:(nullable NSString *)message;

/**
 * Set not found error response (404 Not Found).
 *
 * @param response HTTP response to modify
 * @param message Error message (defaults to "Not found")
 */
+ (void)setNotFoundError:(HttpResponse *)response
                 message:(nullable NSString *)message;

/**
 * Set internal server error response (500 Internal Server Error).
 *
 * @param response HTTP response to modify
 * @param message Error message (defaults to "Internal server error")
 */
+ (void)setInternalServerError:(HttpResponse *)response
                       message:(nullable NSString *)message;

/**
 * Set method not allowed error response (405 Method Not Allowed).
 *
 * @param response HTTP response to modify
 * @param allowedMethod Allowed HTTP method (e.g., "GET", "POST")
 * @param message Error message (defaults to "Method not allowed")
 */
+ (void)setMethodNotAllowedError:(HttpResponse *)response
                   allowedMethod:(NSString *)allowedMethod
                         message:(nullable NSString *)message;

#pragma mark - Custom Error Response

/**
 * Set custom error response with specific status code and error code.
 *
 * @param response HTTP response to modify
 * @param statusCode HTTP status code
 * @param errorCode XRPC error code
 * @param message Error message
 */
+ (void)setError:(HttpResponse *)response
      statusCode:(HttpStatusCode)statusCode
       errorCode:(NSString *)errorCode
         message:(NSString *)message;

#pragma mark - Convenience Methods

/**
 * Set invalid request error (400 Bad Request with InvalidRequest code).
 *
 * @param response HTTP response to modify
 * @param message Error message
 */
+ (void)setInvalidRequestError:(HttpResponse *)response
                       message:(NSString *)message;

/**
 * Set account not found error (404 Not Found with AccountNotFound code).
 *
 * @param response HTTP response to modify
 * @param identifier Account identifier (DID or handle)
 */
+ (void)setAccountNotFoundError:(HttpResponse *)response
                     identifier:(NSString *)identifier;

/**
 * Set lexicon not found error (404 Not Found with LexiconNotFound code).
 *
 * @param response HTTP response to modify
 * @param nsid Lexicon NSID
 */
+ (void)setLexiconNotFoundError:(HttpResponse *)response
                           nsid:(NSString *)nsid;

@end

NS_ASSUME_NONNULL_END
