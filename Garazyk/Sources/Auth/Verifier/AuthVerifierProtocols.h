// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AuthVerifierProtocols.h

 @abstract Protocols defining the interface between AuthVerifier and its host application.

 @discussion These protocols define the seams between the reusable AuthVerifier
 token-verification engine and PDS-specific implementations. AuthVerifier itself
 has no dependencies on PDS database types, allowing it to be reused by both PDS
 and eventually AppView servers.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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
