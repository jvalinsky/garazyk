// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSActorKeyManagerProtocol.h

 @abstract Actor signing key management contract.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @protocol PDSActorKeyManager

 @abstract Stores and uses actor secp256k1 signing keys.

 @discussion Keys are secp256k1 private keys (32 bytes). Implementations choose
 platform-appropriate storage (for example Keychain on macOS).
 */
@protocol PDSActorKeyManager <NSObject>

/*!
 @method generateSigningKeyWithError:

 @abstract Generates and persists a new signing key.

 @param error On failure, set to the key-generation error.
 @result YES on success, otherwise NO.
 */
- (BOOL)generateSigningKeyWithError:(NSError **)error;

/*!
 @method importSigningKey:error:

 @abstract Imports and persists a caller-provided private key.

 @param privateKey Raw 32-byte secp256k1 private key material.
 @param error On failure, set to the import error.
 @result YES on success, otherwise NO.
 */
- (BOOL)importSigningKey:(NSData *)privateKey error:(NSError **)error;

/*!
 @method signData:error:

 @abstract Signs input data using the persisted actor signing key.

 @param data Payload to sign.
 @param error On failure, set to the signing error.
 @result Signature bytes, or nil on failure.
 */
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;

/*!
 @method publicSigningKeyWithError:

 @abstract Returns the public key that corresponds to the persisted private key.

 @param error On failure, set to the lookup/derivation error.
 @result Public key bytes, or nil on failure.
 */
- (nullable NSData *)publicSigningKeyWithError:(NSError **)error;

/*!
 @method didKeyStringWithError:

 @abstract Returns the multibase `did:key` string for the current public key.

 @param error On failure, set to the derivation/encoding error.
 @result `did:key` string, or nil on failure.
 */
- (nullable NSString *)didKeyStringWithError:(NSError **)error;

/*!
 @method exportPrivateKeyWithError:

 @abstract Returns the raw 32-byte secp256k1 private key.

 @param error On failure, set to the export error.
 @result Private key bytes, or nil on failure.
 */
- (nullable NSData *)exportPrivateKeyWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
