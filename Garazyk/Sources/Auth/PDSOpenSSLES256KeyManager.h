// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  PDSOpenSSLES256KeyManager.h
//  ATProtoPDS
//
//  OpenSSL-based ES256 (ECDSA P-256) key manager for GNUstep/Linux.
//  Uses OpenSSL's EC module for elliptic curve operations.
//
//  Copyright (c) 2026 Jack Valinsky. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Auth/PDSKeyProtocol.h"

NS_ASSUME_NONNULL_BEGIN

/// Error domain for OpenSSL ES256 key errors.
extern NSString * const PDSOpenSSLES256KeyErrorDomain;

/**
 * OpenSSL-based ES256 key pair implementation.
 * Uses EC_KEY internally for P-256 operations.
 */
@interface PDSOpenSSLES256PrivateKey : NSObject <PDSPrivateKeyProtocol>

/// The algorithm (always "ES256").
@property (nonatomic, copy, readonly) PDSKeyAlgorithm algorithm;

/// Unique key identifier.
@property (nonatomic, copy, readonly) NSString *keyID;

/// Always YES.
@property (nonatomic, assign, readonly) BOOL isPrivateKey;

/// Creates from raw EC key (takes ownership).
- (nullable instancetype)initWithECKey:(nullable void *)ecKey
                                  keyID:(NSString *)keyID
                                  error:(NSError **)error;

/// Creates from JWK dictionary.
- (nullable instancetype)initWithJWK:(NSDictionary *)jwk
                              keyID:(NSString *)keyID
                              error:(NSError **)error;

/// Creates from raw private key data (32-byte scalar or 65-byte uncompressed point + 32-byte scalar).
- (nullable instancetype)initWithPrivateKeyData:(NSData *)data
                                            keyID:(NSString *)keyID
                                            error:(NSError **)error;

/// Generates a new random key pair.
+ (nullable instancetype)generateKeyWithKeyID:(NSString *)keyID
                                         error:(NSError **)error;

/// Returns the raw EC_KEY pointer (for internal use). Do not free.
- (void *)ecKey;

@end

/**
 * OpenSSL-based ES256 public key implementation.
 */
@interface PDSOpenSSLES256PublicKey : NSObject <PDSPublicKeyProtocol>

/// The algorithm (always "ES256").
@property (nonatomic, copy, readonly) PDSKeyAlgorithm algorithm;

/// Unique key identifier.
@property (nonatomic, copy, readonly) NSString *keyID;

/// Always NO.
@property (nonatomic, assign, readonly) BOOL isPrivateKey;

/// Creates from JWK dictionary.
- (nullable instancetype)initWithJWK:(NSDictionary *)jwk
                               keyID:(NSString *)keyID
                               error:(NSError **)error;

/// Creates from raw public key data (65-byte uncompressed point starting with 0x04).
- (nullable instancetype)initWithPublicKeyData:(NSData *)data
                                          keyID:(NSString *)keyID
                                          error:(NSError **)error;

/// Creates from compressed public key data (33-byte starting with 0x02 or 0x03).
- (nullable instancetype)initWithCompressedPublicKeyData:(NSData *)data
                                                    keyID:(NSString *)keyID
                                                    error:(NSError **)error;

/// Returns the raw EC_KEY pointer (for internal use). Do not free.
- (void *)ecKey;

@end

/**
 * Factory for creating OpenSSL ES256 keys.
 * Implements PDSKeyFactoryProtocol for ES256 only.
 */
@interface PDSOpenSSLES256KeyFactory : NSObject <PDSKeyFactoryProtocol>

@end

NS_ASSUME_NONNULL_END
