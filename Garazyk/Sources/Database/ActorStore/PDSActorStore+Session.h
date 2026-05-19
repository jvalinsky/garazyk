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
- (BOOL)revokeRefreshToken:(NSString *)token error:(NSError **)error;
- (BOOL)revokeSession:(NSString *)sessionID error:(NSError **)error;
- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)accountDid error:(NSError **)error;
- (BOOL)revokeAllSessionsForDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
