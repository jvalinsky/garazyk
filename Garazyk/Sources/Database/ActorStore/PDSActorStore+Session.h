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
 * @abstract Store refresh token with family tracking.
 * @param token Session token.
 * @param sessionID Session identifier.
 * @param accountDid Actor DID for the request.
 * @param expiresAt Session expiration timestamp.
 * @param familyId Optional family ID for §4.3 reuse detection. Pass nil for
 *   sessions created before the V18 migration; the token will work but
 *   reuse detection will be unavailable for that family.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)storeRefreshToken:(NSString *)token sessionID:(NSString *)sessionID forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt familyId:(nullable NSString *)familyId error:(NSError **)error;
- (BOOL)storeRefreshToken:(NSString *)token sessionID:(NSString *)sessionID forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt error:(NSError **)error;
- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt error:(NSError **)error;

/**
 * @abstract Atomically marks a refresh token as rotated (sets rotated_at).
 * @discussion Returns NO if the token was already rotated (indicating reuse).
 * This is the §4.3 race-free rotation marker. Use instead of delete when
 * rotating; keep revokeRefreshToken: for admin-forced session termination.
 * @param token The refresh token to mark as rotated.
 * @param error Receives database or validation failures.
 * @return YES if the token was marked (first rotation), NO if already rotated.
 */
- (BOOL)rotateRefreshToken:(NSString *)token error:(NSError **)error;

/**
 * @abstract Tombstones an entire refresh-token family, revoking all its tokens.
 * @discussion Called when stale-token reuse is detected. Marks every token in
 * the family as tombstoned, so future lookup and rotation attempts fail.
 * @param familyId The family ID to tombstone.
 * @param error Receives database or validation failures.
 * @return YES when the family is tombstoned.
 */
- (BOOL)tombstoneRefreshTokenFamily:(NSString *)familyId error:(NSError **)error;

/**
 * @abstract Checks whether a refresh-token family has been tombstoned.
 * @param familyId The family ID to check.
 * @param error Receives database or validation failures.
 * @return YES if any token in the family has a tombstoned_at timestamp.
 */
- (BOOL)isRefreshTokenFamilyTombstoned:(NSString *)familyId error:(NSError **)error;

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
