// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file Secp256k1.h

 @abstract Secp256k1 elliptic curve cryptography for ATProto signing.

 @discussion Provides key generation, signing, and verification using the
 secp256k1 curve. Used for repository commit signatures and DID key operations.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "secp256k1_wrapper_c.h"

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for secp256k1 operations. */
extern NSString * const Secp256k1ErrorDomain;

/*!
 @class Secp256k1KeyPair

 @abstract Represents a secp256k1 public/private key pair.

 @discussion Provides signing and verification methods for ECDSA signatures.
 */
@interface Secp256k1KeyPair : NSObject

/*! The 32-byte private key. */
@property (nonatomic, strong, readonly) NSData *privateKey;

/*! The 65-byte uncompressed public key. */
@property (nonatomic, strong, readonly) NSData *publicKey;

/*! The 33-byte compressed public key. */
@property (nonatomic, strong, readonly) NSData *compressedPublicKey;

/*! Returns the DID key string (did:key:z...). */
- (NSString *)didKeyString;

/*! Generates a new random key pair. */
+ (nullable instancetype)generateKeyPair:(NSError **)error;

/*! Creates a key pair from existing private key bytes. */
+ (nullable instancetype)keyPairWithPrivateKey:(NSData *)privateKey error:(NSError **)error;

/*! Signs a 32-byte hash and returns the DER-encoded signature. */
- (nullable NSData *)signHash:(NSData *)hash error:(NSError **)error;

/*! Verifies a signature against a hash. */
- (BOOL)verifySignature:(NSData *)signature forHash:(NSData *)hash error:(NSError **)error;

@end

/*!
 @class Secp256k1

 @abstract Singleton interface for secp256k1 operations.

 @discussion Provides a shared context for key generation and cryptographic operations.
 */
@interface Secp256k1 : NSObject

/*! Returns the shared secp256k1 instance. */
+ (instancetype)shared;

/*! Generates a new key pair using the shared context. */
- (nullable Secp256k1KeyPair *)generateKeyPairWithError:(NSError **)error;

/*! Creates a key pair from private key bytes. */
- (nullable Secp256k1KeyPair *)keyPairFromPrivateKey:(NSData *)privateKey error:(NSError **)error;

/*! Signs a hash with a private key. */
- (nullable NSData *)signHash:(NSData *)hash withPrivateKey:(NSData *)privateKey error:(NSError **)error;

/*! Verifies a signature with a public key. */
- (BOOL)verifySignature:(NSData *)signature forHash:(NSData *)hash withPublicKey:(NSData *)publicKey error:(NSError **)error;

/*! Normalizes a public key to 65-byte uncompressed form. */
- (nullable NSData *)normalizedPublicKey:(NSData *)publicKey error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
