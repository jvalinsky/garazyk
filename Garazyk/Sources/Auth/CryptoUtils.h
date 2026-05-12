// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file CryptoUtils.h

 @abstract Cryptographic utility functions for ATProto operations.

 @discussion Provides common cryptographic primitives including HMAC, SHA-256,
 secure random generation, and hex encoding. Used throughout the PDS for
 hashing, signing, and token generation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class CryptoUtils

 @abstract Collection of cryptographic utility methods.
 */
@interface CryptoUtils : NSObject

/*! Computes HMAC-SHA1 of data with key.
    Retained for TOTP (RFC 6238) compatibility. SHA1 is specified by RFC 6238
    as the standard HMAC algorithm for TOTP. Do not use for new cryptographic
    operations - prefer hmacSHA256WithKey:data: instead.
    @param key The HMAC key (nonnull).
    @param data The data to authenticate (nonnull).
    @return The HMAC-SHA1 digest (20 bytes), or nil if key or data is nil. */
+ (nullable NSData *)hmacSHA1WithKey:(NSData *)key data:(NSData *)data;

/*! Computes HMAC-SHA256 of data with key. Preferred for new code.
    @param key The HMAC key (nonnull).
    @param data The data to authenticate (nonnull).
    @return The HMAC-SHA256 digest (32 bytes), or nil if key or data is nil. */
+ (nullable NSData *)hmacSHA256WithKey:(NSData *)key data:(NSData *)data;

/*! Computes SHA-256 hash of data. */
+ (nullable NSData *)sha256:(NSData *)data;

/*! Generates cryptographically secure random bytes. */
+ (nullable NSData *)randomBytes:(NSUInteger)length;

/*! Converts binary data to lowercase hex string. */
+ (NSString *)hexStringFromData:(NSData *)data;

/*! Base64URL encodes data (no padding). */
+ (NSString *)base64URLEncode:(NSData *)data;

/*! Base64URL decodes string. */
+ (nullable NSData *)base64URLDecode:(NSString *)string;

/*! Constant-time string comparison. Resistant to timing attacks.
    Compares strings byte-by-byte with constant time regardless of where
    the first difference occurs. Use for comparing secrets like tokens,
    thumbprints, and cryptographic values.
    @param a First string to compare (may be nil).
    @param b Second string to compare (may be nil).
    @return YES if strings are equal (including both nil), NO otherwise. */
+ (BOOL)constantTimeCompare:(nullable NSString *)a to:(nullable NSString *)b;

/*! Encrypts data with a key using AES-256-CBC with PKCS7 padding.
    The IV is prepended to the returned ciphertext.
    @param data Data to encrypt.
    @param key 32-byte encryption key.
    @return Encrypted data with prepended IV, or nil on failure. */
+ (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key;

/*! Decrypts data with a key using AES-256-CBC with PKCS7 padding.
    Expects the IV to be prepended to the ciphertext.
    @param data Encrypted data with prepended IV.
    @param key 32-byte encryption key.
    @return Decrypted data, or nil on failure. */
+ (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key;

/*! Derives a key from a password and salt using PBKDF2-SHA256.
    Uses 600,000 iterations and produces a 32-byte key.
    Note: Uses 600,000 iterations for encryption key derivation to align with
    OWASP 2023 recommendations.
    @param password The password/secret string (nonnull).
    @param salt The salt data, typically 16+ bytes (nonnull).
    @return Derived 32-byte key, or nil on failure. */
+ (nullable NSData *)deriveKeyFromPassword:(NSString *)password salt:(NSData *)salt;

@end

NS_ASSUME_NONNULL_END
