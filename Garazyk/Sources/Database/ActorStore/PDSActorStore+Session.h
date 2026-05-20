// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/ActorStore/ActorStore.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Actor store operations for session records.
 */
@interface PDSActorStore (Session)

#pragma mark - Session Operations (Reader)

- (nullable NSDictionary *)sessionInfoForRefreshToken:(NSString *)token error:(NSError **)error;
- (nullable NSString *)accountDidForRefreshToken:(NSString *)token error:(NSError **)error;
- (BOOL)isSessionActive:(NSString *)sessionID forAccountDid:(NSString *)did error:(NSError **)error;

#pragma mark - Session Operations (Transactor)

/**
 * @abstract Store refresh token.
 * @param token Session token.
 * @param sessionID Session identifier.
 * @param accountDid Actor DID for the request.
 * @param expiresAt Session expiration timestamp.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)storeRefreshToken:(NSString *)token sessionID:(NSString *)sessionID forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt error:(NSError **)error;
- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt error:(NSError **)error;

/**
 * @abstract Revokes a refresh token, invalidating it for future use.
 * @param token The refresh token to revoke.
 * @param error Receives database or validation failures.
 * @return YES when the token is revoked.
 */
- (BOOL)revokeRefreshToken:(NSString *)token error:(NSError **)error;

/**
 * @abstract Revokes a session, invalidating all its tokens.
 * @param sessionID The session identifier to revoke.
 * @param error Receives database or validation failures.
 * @return YES when the session is revoked.
 */
- (BOOL)revokeSession:(NSString *)sessionID error:(NSError **)error;

/**
 * @abstract Revokes all refresh tokens for a given account.
 * @param accountDid The DID whose tokens should be revoked.
 * @param error Receives database or validation failures.
 * @return YES when all tokens are revoked.
 */
- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)accountDid error:(NSError **)error;

/**
 * @abstract Revokes all sessions for a given DID.
 * @param did The DID whose sessions should be revoked.
 * @param error Receives database or validation failures.
 * @return YES when all sessions are revoked.
 */
- (BOOL)revokeAllSessionsForDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
