//
//  PDSKeyProtocol.h
//  ATProtoPDS
//
//  Abstract key interfaces for cross-platform crypto operations.
//  macOS: Uses Apple Security framework (SecKey)
//  GNUstep: Uses OpenSSL (EC_KEY, RSA)
//
//  Copyright (c) 2026 Jack Valinsky. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Error Domain

extern NSString * const PDSKeyErrorDomain;

typedef NS_ENUM(NSInteger, PDSKeyErrorCode) {
    PDSKeyErrorCodeInvalidKeyData = 1,
    PDSKeyErrorCodeInvalidSignature = 2,
    PDSKeyErrorCodeSigningFailed = 3,
    PDSKeyErrorCodeVerificationFailed = 4,
    PDSKeyErrorCodeKeyGenerationFailed = 5,
    PDSKeyErrorCodeUnsupportedAlgorithm = 6,
    PDSKeyErrorCodeInvalidJWK = 7,
};

#pragma mark - Key Algorithms

// Typed string constants for key algorithms
// NS_TYPED_ENUM is not available on GNUstep, so we use typedef directly
#if defined(__APPLE__) && !defined(GNUSTEP)
typedef NSString * PDSKeyAlgorithm NS_TYPED_ENUM;
#else
typedef NSString * PDSKeyAlgorithm;
#endif

extern PDSKeyAlgorithm const PDSKeyAlgorithmES256;  // ECDSA P-256
extern PDSKeyAlgorithm const PDSKeyAlgorithmRS256;  // RSA SHA-256

#pragma mark - Base Protocol

/**
 * Base protocol for all cryptographic keys.
 */
@protocol PDSKeyProtocol <NSObject, NSCopying>

/// Unique identifier for this key.
@property (nonatomic, copy, readonly) NSString *keyID;

/// Algorithm identifier (e.g., "ES256", "RS256").
@property (nonatomic, copy, readonly) PDSKeyAlgorithm algorithm;

/// Indicates if this is a private key (can sign).
@property (nonatomic, assign, readonly) BOOL isPrivateKey;

/// The raw public key data.
/// For ES256: Uncompressed point (0x04 || x || y), 65 bytes.
/// For RS256: DER-encoded SubjectPublicKeyInfo.
- (nullable NSData *)publicKeyData;

/// JWK representation of the public key.
- (nullable NSDictionary *)publicKeyJWK;

/// RFC 7638 JWK thumbprint (SHA-256, base64url).
- (nullable NSString *)thumbprint;

@end

#pragma mark - Public Key Protocol

/**
 * Protocol for public key operations (verification only).
 */
@protocol PDSPublicKeyProtocol <PDSKeyProtocol>

/**
 * Verifies a signature against the given data.
 *
 * @param signature The signature bytes.
 *                 For ES256: Raw r||s format, 64 bytes.
 *                 For RS256: PKCS#1 v1.5 signature.
 * @param data The original data that was signed.
 * @param error On failure, contains error details.
 * @return YES if signature is valid, NO otherwise.
 */
- (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
                  error:(NSError **)error;

/**
 * Verifies a signature against a pre-computed hash digest.
 *
 * Use this when the hash has already been computed externally
 * (e.g., PLC operations, WebAuthn assertions).
 *
 * @param signature The signature bytes.
 *                 For ES256: Raw r||s format, 64 bytes.
 *                 For RS256: PKCS#1 v1.5 signature.
 * @param digest The pre-computed hash digest (SHA-256 for ES256).
 *               For ES256: 32-byte SHA-256 hash.
 *               For RS256: SHA-256 hash of the message.
 * @param error On failure, contains error details.
 * @return YES if signature is valid, NO otherwise.
 */
- (BOOL)verifyDigestSignature:(NSData *)signature
                      forHash:(NSData *)digest
                        error:(NSError **)error;

@end

#pragma mark - Private Key Protocol

/**
 * Protocol for private key operations (signing).
 */
@protocol PDSPrivateKeyProtocol <PDSKeyProtocol>

/**
 * Signs data with this private key.
 *
 * @param data The data to sign (will be hashed internally).
 * @param error On failure, contains error details.
 * @return The signature bytes.
 *         For ES256: Raw r||s format, 64 bytes (low-S normalized).
 *         For RS256: PKCS#1 v1.5 signature.
 */
- (nullable NSData *)signData:(NSData *)data
                        error:(NSError **)error;

/// The corresponding public key.
- (nullable id<PDSPublicKeyProtocol>)publicKey;

/// Full JWK representation including private key material (if exportable).
- (nullable NSDictionary *)privateKeyJWK;

@end

#pragma mark - Key Factory Protocol

/**
 * Protocol for key generation.
 */
@protocol PDSKeyFactoryProtocol <NSObject>

/**
 * Generates a new key pair.
 *
 * @param algorithm The algorithm (ES256 or RS256).
 * @param keyID Optional key identifier (will generate UUID if nil).
 * @param error On failure, contains error details.
 * @return The private key object.
 */
- (nullable id<PDSPrivateKeyProtocol>)generateKeyPairWithAlgorithm:(PDSKeyAlgorithm)algorithm
                                                              keyID:(nullable NSString *)keyID
                                                              error:(NSError **)error;

/**
 * Imports a private key from JWK format.
 *
 * @param jwk JWK dictionary with 'kty', 'crv' (for EC), and private key material.
 * @param keyID Optional key identifier.
 * @param error On failure, contains error details.
 * @return The private key object.
 */
- (nullable id<PDSPrivateKeyProtocol>)importPrivateKeyFromJWK:(NSDictionary *)jwk
                                                         keyID:(nullable NSString *)keyID
                                                         error:(NSError **)error;

/**
 * Imports a public key from JWK format.
 *
 * @param jwk JWK dictionary with 'kty', 'crv' (for EC), and public key coordinates.
 * @param keyID Optional key identifier.
 * @param error On failure, contains error details.
 * @return The public key object.
 */
- (nullable id<PDSPublicKeyProtocol>)importPublicKeyFromJWK:(NSDictionary *)jwk
                                                       keyID:(nullable NSString *)keyID
                                                       error:(NSError **)error;

/**
 * Imports a public key from raw data.
 *
 * @param data The raw public key data.
 * @param algorithm The algorithm.
 * @param keyID Optional key identifier.
 * @param error On failure, contains error details.
 * @return The public key object.
 */
- (nullable id<PDSPublicKeyProtocol>)importPublicKeyFromData:(NSData *)data
                                                   algorithm:(PDSKeyAlgorithm)algorithm
                                                        keyID:(nullable NSString *)keyID
                                                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
