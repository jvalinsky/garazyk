// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Database operations for account sessions.
 */
@interface PDSDatabase (Sessions)

- (NSArray<NSDictionary *> *)listSessionsForDid:(NSString *)did error:(NSError **)error;
- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)did expiresAt:(NSDate *)expiresAt error:(NSError **)error;
- (nullable NSString *)accountDidForRefreshToken:(NSString *)token error:(NSError **)error;
- (BOOL)revokeSession:(NSString *)token error:(NSError **)error;
- (BOOL)revokeAllSessionsForDid:(NSString *)did error:(NSError **)error;
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
