// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Database operations for WebAuthn credentials.
 */
@interface PDSDatabase (WebAuthn)

- (BOOL)storeWebAuthnCredential:(NSDictionary *)credential
                        forDid:(NSString *)did
                         error:(NSError **)error;
- (NSArray<NSDictionary *> *)getWebAuthnCredentialsForDid:(NSString *)did error:(NSError **)error;
- (BOOL)deleteWebAuthnCredential:(NSData *)credentialId
                       forDid:(NSString *)did
                        error:(NSError **)error;
/**
 * @abstract Update web authn credential sign count.
 * @param credentialId WebAuthn credential identifier.
 * @param did Actor DID for the request.
 * @param signCount WebAuthn signature counter.
 * @param error Receives details when the operation fails.
 * @return YES when the operation succeeds; otherwise NO.
 */
- (BOOL)updateWebAuthnCredentialSignCount:(NSData *)credentialId
                              forDid:(NSString *)did
                           signCount:(uint32_t)signCount
                              error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
