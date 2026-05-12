// SPDX-FileCopyrightText: 2024-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file CryptoUtils.m

 @abstract Cryptographic utility functions for the PDS.

 @discussion This file provides common cryptographic operations including
 HMAC signing, SHA hashing, random byte generation, and hex encoding.
 These utilities are used throughout the authentication and security layers.

 @copyright Copyright (c) 2024-2026 Jack Valinsky
 */

#import "Auth/CryptoUtils.h"
#import "Security/PDSSecurityCompare.h"
#import "Security/PDSKeyEnvelope.h"
#if !TARGET_OS_LINUX
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <Security/Security.h>
#endif

@implementation CryptoUtils

/*!
 @method hmacSHA1WithKey:data:

 @abstract Computes HMAC-SHA1 digest for data authentication.

 @discussion HMAC-SHA1 is retained for RFC 6238 TOTP (Time-based One-Time Password)
 compatibility. SHA-1 is the standard algorithm specified by RFC 6238 for TOTP.

 NOTE: SHA-1 is cryptographically broken and should not be used for new cryptographic
 operations. This method should only be used for TOTP generation. For all other use
 cases, prefer hmacSHA256WithKey:data: instead.

 @param key The secret key for HMAC computation (nonnull).
 @param data The data to authenticate (nonnull).
 @return The HMAC-SHA1 digest (20 bytes), or nil if key or data is nil.
 */
+ (nullable NSData *)hmacSHA1WithKey:(NSData *)key data:(NSData *)data {
    if (!key || !data) return nil;

    unsigned char cHMAC[CC_SHA1_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA1, key.bytes, key.length, data.bytes, data.length, cHMAC);

    return [NSData dataWithBytes:cHMAC length:CC_SHA1_DIGEST_LENGTH];
}

/*!
 @method hmacSHA256WithKey:data:

 @abstract Computes HMAC-SHA256 digest for authenticated data.

 @discussion HMAC-SHA256 provides stronger security than HMAC-SHA1,
 offering better resistance against collision attacks. Use this for
 cryptographic operations requiring strong integrity guarantees.

 @param key The secret key for HMAC computation (nonnull).
 @param data The data to authenticate (nonnull).
 @return The HMAC-SHA256 digest, or nil if key or data is nil.
 */
+ (nullable NSData *)hmacSHA256WithKey:(NSData *)key data:(NSData *)data {
    if (!key || !data) return nil;

    unsigned char hmac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, hmac);
    return [NSData dataWithBytes:hmac length:CC_SHA256_DIGEST_LENGTH];
}

/*!
 @method sha256:

 @abstract Computes SHA-256 cryptographic hash.

 @discussion SHA-256 produces a fixed 32-byte digest suitable for
 content addressing and integrity verification. Used throughout
 the repository layer for Merkle Search Tree operations.

 @param data The data to hash (nonnull).
 @return The SHA-256 digest, or nil on failure.
 */
+ (nullable NSData *)sha256:(NSData *)data {
    if (!data) return nil;
    
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    if (!CC_SHA256(data.bytes, (CC_LONG)data.length, hash)) {
        return nil;
    }
    
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}

/*!
 @method randomBytes:

 @abstract Generates cryptographically secure random bytes.

 @discussion Uses SecRandomCopyBytes for secure random generation.
 The returned bytes are suitable for cryptographic keys, nonces,
 and other security-sensitive operations.

 @param length The number of random bytes to generate.
 @return Random bytes, or nil on failure.
 */
+ (nullable NSData *)randomBytes:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes) != errSecSuccess) {
        return nil;
    }
    return data;
}

/*!
 @method hexStringFromData:

 @abstract Converts binary data to lowercase hexadecimal string.

 @discussion Useful for debugging and displaying digest values.
 Each byte is represented as two hex characters (00-FF).

 @param data The binary data to convert (nonnull).
 @return Lowercase hex string representation.
 */
+ (NSString *)base64URLEncode:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    while ([base64 hasSuffix:@"="]) {
        base64 = [base64 substringToIndex:base64.length - 1];
    }
    return base64;
}

+ (nullable NSData *)base64URLDecode:(NSString *)string {
    NSMutableString *base64 = [string mutableCopy];
    NSUInteger remainder = base64.length % 4;
    if (remainder > 0) {
        [base64 appendString:[@"====" substringToIndex:(4 - remainder)]];
    }
    NSString *standardBase64 = [base64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    standardBase64 = [standardBase64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    return [[NSData alloc] initWithBase64EncodedString:standardBase64 options:0];
}

+ (NSString *)hexStringFromData:(NSData *)data {
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (int i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return [NSString stringWithString:hex];
}

+ (BOOL)constantTimeCompare:(NSString *)a to:(NSString *)b {
    return [PDSSecurityCompare constantTimeEqualString:a string:b];
}

+ (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key {
    return [PDSKeyEnvelope seal:data withKey:key error:nil];
}

+ (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key {
    return [PDSKeyEnvelope openEnvelope:data withKey:key error:nil];
}

/*!
 @method deriveKeyFromPassword:salt:

 @abstract Derives a 32-byte encryption key from a password and salt using PBKDF2-HMAC-SHA256.

 @discussion Uses PBKDF2 with the following parameters:
 - Algorithm: HMAC-SHA256
 - Iterations: 600,000 (OWASP 2023 minimum recommendation)
 - Output length: 32 bytes (256 bits)

 Note: This method uses 600,000 iterations for encryption key derivation to align
 with the current OWASP guideline for password hashing and sensitive key derivation.

 @param password The password string (nonnull, converted to UTF-8).
 @param salt The salt data (nonnull, typically 16+ bytes).
 @return A 32-byte derived key, or nil on failure.
 */
+ (nullable NSData *)deriveKeyFromPassword:(NSString *)password salt:(NSData *)salt {
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *derivedKey = [NSMutableData dataWithLength:32];
    
    int result = CCKeyDerivationPBKDF(kCCPBKDF2,
                                      passwordData.bytes, passwordData.length,
                                      salt.bytes, salt.length,
                                      kCCPRFHmacAlgSHA256,
                                      600000,
                                      derivedKey.mutableBytes, 32);
    
    if (result != kCCSuccess) {
        return nil;
    }
    
    return derivedKey;
}

@end
