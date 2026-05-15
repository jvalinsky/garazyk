// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSDatabase (WebAuthn)

- (BOOL)storeWebAuthnCredential:(NSDictionary *)credential
                        forDid:(NSString *)did
                         error:(NSError **)error;
- (NSArray<NSDictionary *> *)getWebAuthnCredentialsForDid:(NSString *)did error:(NSError **)error;
- (BOOL)deleteWebAuthnCredential:(NSData *)credentialId
                       forDid:(NSString *)did
                        error:(NSError **)error;
- (BOOL)updateWebAuthnCredentialSignCount:(NSData *)credentialId
                              forDid:(NSString *)did
                           signCount:(uint32_t)signCount
                              error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
