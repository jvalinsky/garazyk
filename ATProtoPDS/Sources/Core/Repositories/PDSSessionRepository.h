/*!
 @file PDSSessionRepository.h
 @abstract Protocol for session token management.
 @discussion Handles persistence of refresh tokens and session validity.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PDSSessionRepository <NSObject>

/*! Stores a refresh token associated with an account. */
- (BOOL)storeRefreshToken:(NSString *)refreshToken forAccountDid:(NSString *)did error:(NSError **)error;

/*! Retrieves the account DID associated with a refresh token. */
- (nullable NSString *)accountDidForRefreshToken:(NSString *)refreshToken error:(NSError **)error;

/*! Revokes (deletes) a specific refresh token. */
- (BOOL)revokeRefreshToken:(NSString *)refreshToken error:(NSError **)error;

/*! Revokes all refresh tokens for a specific account. */
- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
