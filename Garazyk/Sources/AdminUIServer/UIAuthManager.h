// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class ATProtoHttpRequest;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Default session TTL in seconds (8 hours).
 */
extern const NSTimeInterval kUIAuthDefaultSessionTTL;

/**
 * @abstract Manages Admin UI authentication tokens and session state.
 */
@interface GZAdminUIAuthManager : NSObject

/**
 * @abstract PDSSession TTL in seconds. Default is 8 hours (28800).
 */
@property (nonatomic, assign) NSTimeInterval sessionTTL;

/**
 * @abstract Identifier distinguishing this UI's cookies from a sibling UI's, or nil.
 */
@property (nonatomic, copy, readonly, nullable) NSString *serviceIdentifier;

/**
 * @abstract Name of the session cookie this manager issues and reads.
 */
@property (nonatomic, copy, readonly) NSString *sessionCookieName;

/**
 * @abstract Name of the CSRF nonce cookie this manager issues and reads.
 */
@property (nonatomic, copy, readonly) NSString *csrfCookieName;

- (instancetype)initWithPassword:(NSString *)password;

/**
 * @abstract Create a manager whose cookies are scoped to one service.
 * @discussion Cookies are not port-scoped, so admin UIs for different services on the same
 * host share a cookie jar. Without distinct names, signing in to one evicts the other's
 * session, and the one-time CSRF nonces overwrite each other on every mutation. Managers
 * built with an identifier use `gz_admin_<identifier>_token` and `gz_admin_<identifier>_nonce`;
 * managers built without one keep the unscoped `ui_admin_token` and `ui_admin_nonce` names.
 * @param password Plaintext admin password for this service's UI.
 * @param serviceIdentifier Short lowercase service name, such as `plc`. Pass nil for the
 * unscoped names.
 */
- (instancetype)initWithPassword:(NSString *)password
               serviceIdentifier:(nullable NSString *)serviceIdentifier;

/**
 * @abstract Validate a password against the stored PBKDF2 hash using constant-time comparison.
 * @param password Plaintext password to verify.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)validatePassword:(NSString *)password;

/**
 * @abstract Create a cryptographically random session token.
 * @discussion The token itself is returned (for the cookie), but only its SHA-256 hash is stored in memory.
 * @return The plaintext session token.
 */
- (NSString *)createSessionToken;

/**
 * @abstract Invalidate a session token by its plaintext value.
 * @param token PDSSession token.
 */
- (void)invalidateSessionToken:(NSString *)token;

/**
 * @abstract Check if a request carries a valid, non-expired session token.
 * @param request The HTTP request to check.
 * @return YES if authorized; otherwise NO.
 */
- (BOOL)isAuthorizedRequest:(ATProtoHttpRequest *)request;

/**
 * @abstract Extract token from Authorization header or ui_admin_token cookie.
 * @param request The HTTP request.
 * @return The extracted token, or nil.
 */
- (nullable NSString *)extractTokenFromRequest:(ATProtoHttpRequest *)request;

/**
 * @abstract Build a Set-Cookie header value for the session token with security attributes.
 * @param token The plaintext session token.
 * @param secure Whether the cookie should use the Secure attribute (should be YES when behind TLS).
 * @return The requested string, or nil when unavailable.
 */
- (NSString *)cookieHeaderValueForToken:(NSString *)token secure:(BOOL)secure;

/**
 * @abstract Validate CSRF nonce.
 * @discussion The X-UI-Admin-Nonce header must match the nonce cookie value. Returns YES if the check passes or if no nonce is present.
 * @param request The HTTP request.
 * @return YES if valid or absent; otherwise NO.
 */
- (BOOL)validateCSRFForRequest:(ATProtoHttpRequest *)request;

/**
 * @abstract Generate a new CSRF nonce and return the Set-Cookie header value.
 * @param secure Whether the cookie should use the Secure attribute.
 * @return The requested string, or nil when unavailable.
 */
- (NSString *)createCSRFNonceCookie:(BOOL)secure;

/**
 * @abstract Generate a new CSRF nonce and return both the raw value and the Set-Cookie header.
 * @param outNonce Pointer to receive the raw nonce.
 * @param outCookie Pointer to receive the Set-Cookie header.
 * @param secure Whether the cookie should use the Secure attribute.
 */
- (void)createCSRFNonce:(NSString * _Nonnull * _Nonnull)outNonce
                 cookie:(NSString * _Nonnull * _Nonnull)outCookie
                 secure:(BOOL)secure;

@end

NS_ASSUME_NONNULL_END
