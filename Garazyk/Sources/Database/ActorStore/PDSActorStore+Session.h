// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/ActorStore/ActorStore.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Actor store operations for session records.
 */
@interface PDSActorStore (Session)

#pragma mark - Session Operations (Reader)

- (nullable NSString *)accountDidForRefreshToken:(NSString *)token error:(NSError **)error;

#pragma mark - Session Operations (Transactor)

/**
 * @abstract Store refresh token.
 * @param token Session token.
 * @param accountDid Actor DID for the request.
 * @param expiresAt Session expiration timestamp.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt error:(NSError **)error;
- (BOOL)revokeRefreshToken:(NSString *)token error:(NSError **)error;
- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)accountDid error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
