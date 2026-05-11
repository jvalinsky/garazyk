// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file OAuthProviderProtocols.h

 @abstract Protocols defining the interface between OAuthProvider and its host application.

 @discussion These protocols define the seams between the reusable OAuthProvider
 authorization server engine and PDS-specific implementations. The OAuthProvider
 itself has no dependencies on PDS database types, allowing it to be reused
 by both PDS and eventually AppView servers.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* Forward declarations */
@class OAuthProviderTokenResponse;
@class OAuthProviderPAR;
@class OAuthProviderAuthCode;
@class OAuthProviderRefreshToken;

/*!
 @protocol OAuthProviderStorage
 
 @abstract Storage interface for OAuth Provider state.
 
 @discussion Implementations must handle persistence across process restarts
 for production use. The in-memory default is only suitable for testing.
 */
@protocol OAuthProviderStorage <NSObject>

@required

#pragma mark - PAR (Pushed Authorization Request)

/*!
 @brief Stores a PAR request URI and its associated data.
 @param par The PAR data dictionary containing request parameters.
 @param requestURI The opaque request URI (urn:ietf:params:oauth:request_uri:xxx).
 @param expiresAt When this PAR expires and should be rejected.
 @param error Set on failure.
 @return YES on success.
 */
- (BOOL)storePAR:(NSDictionary *)par
    forRequestURI:(NSString *)requestURI
        expiresAt:(NSDate *)expiresAt
            error:(NSError **)error;

/*!
 @brief Retrieves PAR data for a request URI.
 @param requestURI The opaque request URI to look up.
 @param error Set on failure.
 @return PAR data dictionary, or nil if not found/expired.
 */
- (nullable NSDictionary *)loadPARForRequestURI:(NSString *)requestURI
                                         error:(NSError **)error;

/*!
 @brief Removes a PAR after it has been used.
 @param requestURI The request URI to delete.
 @param error Set on failure.
 @return YES on success.
 */
- (BOOL)deletePARForRequestURI:(NSString *)requestURI
                         error:(NSError **)error;

#pragma mark - Authorization Codes

/*!
 @brief Stores an authorization code.
 @param code The authorization code string.
 @param data The code data including client_id, redirect_uri, etc.
 @param expiresAt When this code expires.
 @param error Set on failure.
 @return YES on success.
 */
- (BOOL)storeAuthCode:(NSString *)code
                 data:(NSDictionary *)data
            expiresAt:(NSDate *)expiresAt
                error:(NSError **)error;

/*!
 @brief Retrieves and consumes an authorization code (one-time use).
 @param code The authorization code to consume.
 @param error Set on failure (including if not found/expired).
 @return Code data dictionary, or nil if invalid/expired.
 */
- (nullable NSDictionary *)consumeAuthCode:(NSString *)code
                                     error:(NSError **)error;

#pragma mark - Refresh Tokens

/*!
 @brief Stores a refresh token.
 @param tokenID Unique identifier for the token.
 @param data Token data including client_id, user DID, scopes, etc.
 @param error Set on failure.
 @return YES on success.
 */
- (BOOL)storeRefreshToken:(NSString *)tokenID
                     data:(NSDictionary *)data
                    error:(NSError **)error;

/*!
 @brief Retrieves refresh token data.
 @param tokenID The token ID to look up.
 @param error Set on failure.
 @return Token data dictionary, or nil if not found/revoked.
 */
- (nullable NSDictionary *)loadRefreshToken:(NSString *)tokenID
                                     error:(NSError **)error;

/*!
 @brief Rotates a refresh token (invalidates old, creates new).
 @param oldTokenID The current token ID.
 @param newTokenID The new token ID.
 @param newData Updated token data for the new token.
 @param error Set on failure.
 @return YES on success.
 */
- (BOOL)rotateRefreshToken:(NSString *)oldTokenID
                toNewToken:(NSString *)newTokenID
                   withData:(NSDictionary *)newData
                      error:(NSError **)error;

/*!
 @brief Revokes a refresh token.
 @param tokenID The token ID to revoke.
 @param error Set on failure.
 @return YES on success.
 */
- (BOOL)revokeRefreshToken:(NSString *)tokenID
                      error:(NSError **)error;

#pragma mark - Grants/Consent

/*!
 @brief Checks if user has previously granted consent for a client.
 @param accountDID The user's DID.
 @param clientID The client identifier.
 @param scope The requested scope.
 @param error Set on failure.
 @return YES if consent exists and is valid.
 */
- (BOOL)hasConsentForAccountDID:(NSString *)accountDID
                       clientID:(NSString *)clientID
                          scope:(NSString *)scope
                          error:(NSError **)error;

/*!
 @brief Records user consent for a client.
 @param accountDID The user's DID.
 @param clientID The client identifier.
 @param scope The granted scope.
 @param error Set on failure.
 @return YES on success.
 */
- (BOOL)recordConsentForAccountDID:(NSString *)accountDID
                          clientID:(NSString *)clientID
                             scope:(NSString *)scope
                             error:(NSError **)error;

@end


/*!
 @protocol OAuthProviderClientRegistry
 
 @abstract Interface for OAuth client lookup and validation.
 
 @discussion Supports both static client registration (database) and
 dynamic client registration via client_metadata.
 */
@protocol OAuthProviderClientRegistry <NSObject>

@required

/*!
 @brief Looks up a client by ID.
 @param clientID The client identifier.
 @param error Set on failure.
 @return Client data dictionary with keys: client_id, redirect_uris, token_endpoint_auth_method, jwks, jwks_uri, etc. Returns nil if not found.
 */
- (nullable NSDictionary *)getClientByID:(NSString *)clientID
                                  error:(NSError **)error;

/*!
 @brief Validates a redirect URI for a client.
 @param redirectURI The redirect URI to validate.
 @param client The client data from getClientByID:.
 @param error Set on failure.
 @return YES if the redirect URI is allowed for this client.
 */
- (BOOL)validateRedirectURI:(NSString *)redirectURI
                  forClient:(NSDictionary *)client
                      error:(NSError **)error;

@optional

/*!
 @brief Checks if client uses a certain authentication method.
 @param clientID The client identifier.
 @param method The token_endpoint_auth_method to check (e.g., "none", "client_secret_post", "client_secret_basic", "private_key_jwt").
 @return YES if the client supports this method.
 */
- (BOOL)client:(NSString *)clientID
    supportsAuthMethod:(NSString *)method;

/*!
 @brief Gets client ID for a given JWT assertion.
 @param assertion The client JWT assertion (private_key_jwt).
 @param error Set on failure.
 @return The client ID that the assertion claims, or nil if invalid.
 */
- (nullable NSString *)clientIDFromJWTAssertion:(NSString *)assertion
                                          error:(NSError **)error;

@end


/*!
 @protocol OAuthProviderTokenSigner
 
 @abstract Interface for JWT signing and JWKS management.
 */
@protocol OAuthProviderTokenSigner <NSObject>

@required

/*!
 @brief Returns the issuer identifier for tokens.
 */
@property (nonatomic, copy, readonly) NSString *issuer;

/*!
 @brief Returns the JWKS (JSON Web Key Set) for token verification.
 */
@property (nonatomic, copy, readonly) NSDictionary *jwks;

/*!
 @brief Mints a new access token.
 @param claims Token claims (sub, aud, scope, etc.). The implementation adds iat, exp.
 @param error Set on failure.
 @return Signed JWT string, or nil on error.
 */
- (nullable NSString *)mintAccessTokenWithClaims:(NSDictionary *)claims
                                           error:(NSError **)error;

/*!
 @brief Mints a new refresh token.
 @param claims Token claims (sub, aud, scope, client_id, etc.). The implementation adds iat.
 @param error Set on failure.
 @return Signed JWT string, or nil on error.
 */
- (nullable NSString *)mintRefreshTokenWithClaims:(NSDictionary *)claims
                                            error:(NSError **)error;

/*!
 @brief Verifies an access token.
 @param token The JWT string to verify.
 @param audience The expected audience (resource server identifier).
 @param error Set on failure.
 @return Claims dictionary if valid, or nil if invalid/expired.
 */
- (nullable NSDictionary *)verifyAccessToken:(NSString *)token
                                   forAudience:(NSString *)audience
                                       error:(NSError **)error;

/*!
 @brief Verifies a refresh token.
 @param token The JWT string to verify.
 @param error Set on failure.
 @return Claims dictionary if valid, or nil if invalid/expired.
 */
- (nullable NSDictionary *)verifyRefreshToken:(NSString *)token
                                       error:(NSError **)error;

@end


/*!
 @protocol OAuthProviderUserAuthenticator
 
 @abstract Interface for user authentication.
 
 @discussion Used by the authorization server to verify user credentials
 during the authorization flow.
 */
@protocol OAuthProviderUserAuthenticator <NSObject>

@required

/*!
 @brief Authenticates a user with password.
 @param login User login (handle or DID).
 @param password The user's password.
 @param tfaCode Optional TOTP/2FA code if required.
 @param error Set on failure.
 @return The authenticated user's DID, or nil if authentication failed.
 */
- (nullable NSString *)authenticateLogin:(NSString *)login
                               password:(NSString *)password
                                tfaCode:(nullable NSString *)tfaCode
                                  error:(NSError **)error;

/*!
 @brief Looks up a user by DID to get their handle.
 @param did The user's DID.
 @param error Set on failure.
 @return The user's handle, or nil if not found.
 */
- (nullable NSString *)handleForDID:(NSString *)did
                              error:(NSError **)error;

@optional

/*!
 @brief Checks if a user has 2FA enabled.
 @param did The user's DID.
 @return YES if the user has 2FA configured.
 */
- (BOOL)has2FAForDID:(NSString *)did;

/*!
 @brief Validates a TOTP code.
 @param did The user's DID.
 @param code The TOTP code to validate.
 @return YES if the code is valid.
 */
- (BOOL)validateTOTPCode:(NSString *)code forDID:(NSString *)did;

@end


/*!
 @protocol OAuthProviderDIDResolver
 
 @abstract Interface for DID resolution.
 
 @discussion Used to resolve DIDs to documents for verification.
 */
@protocol OAuthProviderDIDResolver <NSObject>

@required

/*!
 @brief Resolves a DID to its document.
 @param did The DID to resolve.
 @param error Set on failure.
 @return The DID document JSON, or nil if not found.
 */
- (nullable NSDictionary *)resolveDID:(NSString *)did
                                error:(NSError **)error;

@end


/*!
 @protocol OAuthProviderHandleResolver
 
 @abstract Interface for handle resolution.
 
 @discussion Used to resolve handles to DIDs during login hint processing.
 */
@protocol OAuthProviderHandleResolver <NSObject>

@required

/*!
 @brief Resolves a handle to a DID.
 @param handle The handle to resolve (e.g., "user.bsky.social").
 @param error Set on failure.
 @return The resolved DID, or nil if resolution failed.
 */
- (nullable NSString *)resolveHandle:(NSString *)handle
                               error:(NSError **)error;

@end


/*!
 @protocol DPoPNonceStore
 
 @abstract Interface for DPoP nonce management.
 
 @discussion Required for DPoP proof verification when nonces are enforced.
 */
@protocol DPoPNonceStore <NSObject>

@required

/*!
 @brief Issues a new nonce for a DPoP key.
 @param jkt The JWK thumbprint identifying the key.
 @param error Set on failure.
 @return A new nonce string, or nil on error.
 */
- (nullable NSString *)issueNonceForJWKThumbprint:(NSString *)jkt
                                            error:(NSError **)error;

/*!
 @brief Consumes a nonce, ensuring it is used only once.
 @param nonce The nonce to consume.
 @param jkt The JWK thumbprint the nonce was issued for.
 @param error Set on failure.
 @return YES if the nonce was valid and consumed. NO if invalid/already used.
 */
- (BOOL)consumeNonce:(NSString *)nonce
     forJWKThumbprint:(NSString *)jkt
                error:(NSError **)error;

@end


/*!
 @protocol AccountPolicy
 
 @abstract Policy interface for resource server access control.
 
 @discussion Used by AuthVerifier to check account status.
 */
@protocol AccountPolicy <NSObject>

@required

/*!
 @brief Checks if an account is allowed to access resources.
 @param did The account DID.
 @param error Set on failure.
 @return YES if the account is allowed. NO if takedown/deactivation.
 */
- (BOOL)isAccountAllowed:(NSString *)did
                   error:(NSError **)error;

/*!
 @brief Checks if an account has admin privileges.
 @param did The account DID.
 @param error Set on failure.
 @return YES if the account is an admin.
 */
- (BOOL)isAdmin:(NSString *)did
           error:(NSError **)error;

@end


/*!
 @protocol TokenKeyResolver
 
 @abstract Interface for remote JWKS resolution.
 
 @discussion Used by AuthVerifier to fetch JWKS from other servers.
 */
@protocol TokenKeyResolver <NSObject>

@required

/*!
 @brief Fetches JWKS for a given issuer.
 @param issuer The token issuer URL.
 @param error Set on failure.
 @return JWKS dictionary, or nil if resolution failed.
 */
- (nullable NSDictionary *)jwksForIssuer:(NSString *)issuer
                                   error:(NSError **)error;

/*!
 @brief Checks if an issuer is trusted.
 @param issuer The issuer URL.
 @return YES if tokens from this issuer should be accepted.
 */
- (BOOL)isIssuerAllowed:(NSString *)issuer;

@end

NS_ASSUME_NONNULL_END
