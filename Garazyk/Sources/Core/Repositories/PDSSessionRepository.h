// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSSessionRepository.h

 @abstract Protocol for session token management.

 @discussion Defines the contract for refresh token persistence operations.
 This repository handles the mapping between refresh tokens and account DIDs,
 enabling token-based session management for OAuth 2.0 flows.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @protocol PDSSessionRepository

 @abstract Protocol for session token management.

 @discussion Implementations provide storage and lookup operations for
 refresh tokens. This enables:

 - Token-based session validation
 - Multi-device session management
 - Token revocation (single or all)

 <b>Thread Safety:</b> Implementations must be thread-safe for concurrent
 access from multiple request handlers.

 <b>Security:</b> Refresh tokens are long-lived credentials. Implementations
 should consider:
 - Encryption at rest
 - Secure deletion on revocation
 - Rate limiting on lookups

 @see PDSAccountService
 @see Session
 */
@protocol PDSSessionRepository <NSObject>

/*!
 @method storeRefreshToken:forAccountDid:error:

 @abstract Stores a refresh token associated with an account.

 @param refreshToken The refresh token string to store.
 @param did The account DID to associate with the token.
 @param error On return, contains an error if the store failed.
 @return YES if stored successfully, NO otherwise.
 */
- (BOOL)storeRefreshToken:(NSString *)refreshToken forAccountDid:(NSString *)did error:(NSError **)error;

/*!
 @method accountDidForRefreshToken:error:

 @abstract Retrieves the account DID associated with a refresh token.

 @param refreshToken The refresh token to look up.
 @param error On return, contains an error if the lookup failed.
 @return The account DID, or nil if the token is not found or invalid.
 */
- (nullable NSString *)accountDidForRefreshToken:(NSString *)refreshToken error:(NSError **)error;

/*!
 @method revokeRefreshToken:error:

 @abstract Revokes (deletes) a specific refresh token.

 @param refreshToken The refresh token to revoke.
 @param error On return, contains an error if the revocation failed.
 @return YES if revoked successfully, NO otherwise.
 */
- (BOOL)revokeRefreshToken:(NSString *)refreshToken error:(NSError **)error;

/*!
 @method revokeAllRefreshTokensForAccountDid:error:

 @abstract Revokes all refresh tokens for a specific account.

 @param did The account DID whose tokens should be revoked.
 @param error On return, contains an error if the revocation failed.
 @return YES if all tokens were revoked successfully, NO otherwise.

 @discussion This is typically called during account deletion or security
 events requiring all sessions to be invalidated.
 */
- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
