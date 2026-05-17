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
 * @abstract OpenSSL-backed ES256 private key implementation.
 */
@interface PDSOpenSSLES256PrivateKey : NSObject <PDSPrivateKeyProtocol>

/** The algorithm, always ES256. */
@property (nonatomic, copy, readonly) PDSKeyAlgorithm algorithm;

/** Unique key identifier. */
@property (nonatomic, copy, readonly) NSString *keyID;

/** Always YES for private keys. */
@property (nonatomic, assign, readonly) BOOL isPrivateKey;

/**
 * @abstract Creates a private key from an OpenSSL EC_KEY pointer.
 * @discussion The instance takes ownership of the supplied pointer.
 */
- (nullable instancetype)initWithECKey:(nullable void *)ecKey
                                  keyID:(NSString *)keyID
                                  error:(NSError **)error;

/** Creates a private key from a JWK dictionary. */
- (nullable instancetype)initWithJWK:(NSDictionary *)jwk
                              keyID:(NSString *)keyID
                              error:(NSError **)error;

/** Creates a private key from raw scalar key data. */
- (nullable instancetype)initWithPrivateKeyData:(NSData *)data
                                            keyID:(NSString *)keyID
                                            error:(NSError **)error;

/** Generates a new random ES256 key pair. */
+ (nullable instancetype)generateKeyWithKeyID:(NSString *)keyID
                                         error:(NSError **)error;

/** Returns the raw EC_KEY pointer owned by the instance. */
- (void *)ecKey;

@end

/**
 * @abstract OpenSSL-backed ES256 public key implementation.
 */
@interface PDSOpenSSLES256PublicKey : NSObject <PDSPublicKeyProtocol>

/** The algorithm, always ES256. */
@property (nonatomic, copy, readonly) PDSKeyAlgorithm algorithm;

/** Unique key identifier. */
@property (nonatomic, copy, readonly) NSString *keyID;

/** Always NO for public keys. */
@property (nonatomic, assign, readonly) BOOL isPrivateKey;

/** Creates a public key from a JWK dictionary. */
- (nullable instancetype)initWithJWK:(NSDictionary *)jwk
                               keyID:(NSString *)keyID
                               error:(NSError **)error;

/** Creates a public key from a 65-byte uncompressed public point. */
- (nullable instancetype)initWithPublicKeyData:(NSData *)data
                                          keyID:(NSString *)keyID
                                          error:(NSError **)error;

/** Creates a public key from a 33-byte compressed public point. */
- (nullable instancetype)initWithCompressedPublicKeyData:(NSData *)data
                                                    keyID:(NSString *)keyID
                                                    error:(NSError **)error;

/** Returns the raw EC_KEY pointer owned by the instance. */
- (void *)ecKey;

@end

/**
 * @abstract Factory for generating and importing OpenSSL ES256 keys.
 */
@interface PDSOpenSSLES256KeyFactory : NSObject <PDSKeyFactoryProtocol>

@end

NS_ASSUME_NONNULL_END
