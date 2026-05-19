// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Database operations for account sessions.
 */
@interface PDSDatabase (Sessions)

- (NSArray<NSDictionary *> *)listSessionsForDid:(NSString *)did error:(NSError **)error;
- (BOOL)storeRefreshToken:(NSString *)token sessionID:(NSString *)sessionID forAccountDid:(NSString *)did expiresAt:(NSDate *)expiresAt error:(NSError **)error;
- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)did expiresAt:(NSDate *)expiresAt error:(NSError **)error;
- (nullable NSDictionary *)sessionInfoForRefreshToken:(NSString *)token error:(NSError **)error;
- (nullable NSString *)accountDidForRefreshToken:(NSString *)token error:(NSError **)error;
- (BOOL)isSessionActive:(NSString *)sessionID forAccountDid:(NSString *)did error:(NSError **)error;
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
