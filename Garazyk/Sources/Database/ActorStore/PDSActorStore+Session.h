// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/ActorStore/ActorStore.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Actor store operations for session records.
 */
@interface PDSActorStore (PDSSession)

#pragma mark - PDSSession Operations (Reader)

/**
 * @abstract Retrieves session details for a specific refresh token.
 * @discussion The returned dictionary's "next_token" entry, when present, is
 * the successor this token was already rotated to; a caller that receives a
 * populated next_token should treat the request as an in-grace-period replay
 * and reissue that same successor rather than minting a new one.
 */
- (nullable NSDictionary *)sessionInfoForRefreshToken:(NSString *)token error:(NSError **)error;
/**
 * @abstract Resolves the account DID only when this is still the current
 * (non-superseded) token for its session — i.e. next_token IS NULL.
 */
- (nullable NSString *)accountDidForRefreshToken:(NSString *)token error:(NSError **)error;
- (BOOL)isSessionActive:(NSString *)sessionID forAccountDid:(NSString *)did error:(NSError **)error;

#pragma mark - PDSSession Operations (Transactor)

- (BOOL)storeRefreshToken:(NSString *)token sessionID:(NSString *)sessionID forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt error:(NSError **)error;
- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)accountDid expiresAt:(NSDate *)expiresAt error:(NSError **)error;

/**
 * @abstract Marks a refresh token as rotated to a successor, shortening its
 * own expiry to a grace period rather than deleting it outright.
 * @discussion §4.3 reuse handling: within the grace window, replaying this
 * token resolves (via sessionInfoForRefreshToken:) to the same nextToken,
 * so a client racing a dropped response can complete the refresh
 * idempotently. Past graceExpiresAt, the row simply expires like any other.
 * @param token The refresh token being rotated away.
 * @param nextToken The refresh token it was rotated to.
 * @param graceExpiresAt The shortened expiry for the old token.
 * @param error Receives database or validation failures.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)markRefreshTokenRotated:(NSString *)token nextToken:(NSString *)nextToken graceExpiresAt:(NSDate *)graceExpiresAt error:(NSError **)error;

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
