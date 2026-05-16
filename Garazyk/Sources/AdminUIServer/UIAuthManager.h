// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class HttpRequest;

NS_ASSUME_NONNULL_BEGIN

/// Default session TTL in seconds (8 hours)
extern const NSTimeInterval kUIAuthDefaultSessionTTL;

/**
 * @abstract Manages Admin UI authentication tokens and session state.
 */
@interface UIAuthManager : NSObject

/// Session TTL in seconds. Default is 8 hours (28800).
@property (nonatomic, assign) NSTimeInterval sessionTTL;

- (instancetype)initWithPassword:(NSString *)password;

/// Validate a password against the stored PBKDF2 hash. Uses constant-time comparison.
/**
 * @abstract Validate password.
 * @param password Plaintext password to verify.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)validatePassword:(NSString *)password;

/// Create a cryptographically random session token. The token itself is returned
/// (for the cookie), but only its SHA-256 hash is stored in memory.
- (NSString *)createSessionToken;

/// Invalidate a session token by its plaintext value.
/**
 * @abstract Invalidate session token.
 * @param token Session token.
 */
- (void)invalidateSessionToken:(NSString *)token;

/// Check if a request carries a valid, non-expired session token.
- (BOOL)isAuthorizedRequest:(HttpRequest *)request;

/// Extract token from Authorization header or ui_admin_token cookie.
- (nullable NSString *)extractTokenFromRequest:(HttpRequest *)request;

/// Build a Set-Cookie header value for the session token with security attributes.
/// @param token The plaintext session token
/// @param secure Whether to set the Secure flag (should be YES when behind TLS)
/**
 * @abstract Cookie header value for token.
 * @param token Session token.
 * @param secure Whether the cookie should use the Secure attribute.
 * @return The requested string, or nil when unavailable.
 */
- (NSString *)cookieHeaderValueForToken:(NSString *)token secure:(BOOL)secure;

/// Validate CSRF nonce: the X-UI-Admin-Nonce header must match the nonce
/// cookie value. Returns YES if the check passes or if no nonce is present.
- (BOOL)validateCSRFForRequest:(HttpRequest *)request;

/// Generate a new CSRF nonce and return the Set-Cookie header value.
/**
 * @abstract Create csrfnonce cookie.
 * @param secure Whether the cookie should use the Secure attribute.
 * @return The requested string, or nil when unavailable.
 */
- (NSString *)createCSRFNonceCookie:(BOOL)secure;

/// Generate a new CSRF nonce and return both the raw value and the Set-Cookie header.
- (void)createCSRFNonce:(NSString * _Nonnull * _Nonnull)outNonce
                 cookie:(NSString * _Nonnull * _Nonnull)outCookie
                 secure:(BOOL)secure;

@end

NS_ASSUME_NONNULL_END
