// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Database operations for account sessions.
 */
@interface PDSDatabase (Sessions)

/**
 * @abstract Lists active sessions for a given DID.
 * @param did The actor DID whose sessions to retrieve.
 * @param error Receives database or validation failures.
 * @return An array of session info dictionaries, or nil on error.
 */
- (NSArray<NSDictionary *> *)listSessionsForDid:(NSString *)did error:(NSError **)error;

/**
 * @abstract Stores a new refresh token linked to a session ID.
 * @param token The refresh token to store.
 * @param sessionID The session identifier.
 * @param did The actor DID for the session.
 * @param expiresAt The date when the token expires.
 * @param error Receives details when the database write fails.
 * @return YES on success; otherwise NO.
 */
- (BOOL)storeRefreshToken:(NSString *)token sessionID:(NSString *)sessionID forAccountDid:(NSString *)did expiresAt:(NSDate *)expiresAt error:(NSError **)error;

/**
 * @abstract Stores a new refresh token for a given actor DID.
 * @param token The refresh token to store.
 * @param did The actor DID.
 * @param expiresAt The date when the token expires.
 * @param error Receives details when the database write fails.
 * @return YES on success; otherwise NO.
 */
- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)did expiresAt:(NSDate *)expiresAt error:(NSError **)error;

/**
 * @abstract Retrieves session details for a specific refresh token.
 * @discussion The "next_token" entry, when present, is the successor this
 * token was already rotated to (an in-grace-period replay).
 * @param token The refresh token to lookup.
 * @param error Receives details when the database read fails.
 * @return A dictionary containing session details, or nil if not found or on error.
 */
- (nullable NSDictionary *)sessionInfoForRefreshToken:(NSString *)token error:(NSError **)error;

/**
 * @abstract Resolves the actor DID only when this is still the current
 * (non-superseded) refresh token — i.e. next_token IS NULL.
 * @param token The refresh token to lookup.
 * @param error Receives details when the database read fails.
 * @return The actor DID, or nil if not found, superseded, or on error.
 */
- (nullable NSString *)accountDidForRefreshToken:(NSString *)token error:(NSError **)error;

/**
 * @abstract Checks whether a session identifier is active for an actor DID.
 * @param sessionID The session identifier.
 * @param did The actor DID.
 * @param error Receives details when the database read fails.
 * @return YES if active; otherwise NO.
 */
- (BOOL)isSessionActive:(NSString *)sessionID forAccountDid:(NSString *)did error:(NSError **)error;

/**
 * @abstract Marks a refresh token as rotated to a successor, shortening its
 * own expiry to a grace period rather than deleting it outright.
 * @param token The refresh token being rotated away.
 * @param nextToken The refresh token it was rotated to.
 * @param graceExpiresAt The shortened expiry for the old token.
 * @param error Receives details when the database write fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)markRefreshTokenRotated:(NSString *)token nextToken:(NSString *)nextToken graceExpiresAt:(NSDate *)graceExpiresAt error:(NSError **)error;

/**
 * @abstract Revokes a refresh token, invalidating it.
 * @param token The refresh token to revoke.
 * @param error Receives details when the database write fails.
 * @return YES on success; otherwise NO.
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
 * @abstract Revokes all sessions for a given DID.
 * @param did The DID whose sessions should be revoked.
 * @param error Receives database or validation failures.
 * @return YES when all sessions are revoked.
 */
- (BOOL)revokeAllSessionsForDid:(NSString *)did error:(NSError **)error;

/**
 * @abstract Lists active app passwords for a given DID.
 * @param did The DID whose app passwords to list.
 * @param error Receives database or validation failures.
 * @return An array of app password dictionaries, or nil on error.
 */
- (NSArray<NSDictionary *> *)listAppPasswordsForDid:(NSString *)did error:(NSError **)error;
/**
 * @abstract Revoke app password.
 * @param passwordId Application password identifier.
 * @param did Actor DID for the request.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)revokeAppPassword:(NSString *)passwordId forDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
