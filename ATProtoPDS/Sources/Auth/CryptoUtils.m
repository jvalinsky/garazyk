/*!
 @file CryptoUtils.m

 @abstract Cryptographic utility functions for the PDS.

 @discussion This file provides common cryptographic operations including
 HMAC signing, SHA hashing, random byte generation, and hex encoding.
 These utilities are used throughout the authentication and security layers.

 @copyright Copyright (c) 2024 Jack Myers
 */

#import "Auth/CryptoUtils.h"
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

@implementation CryptoUtils

/*!
 @method hmacSHA1WithKey:data:

 @abstract Computes HMAC-SHA1 digest for data authentication.

 @discussion HMAC-SHA1 is provided for legacy compatibility. For new
 implementations, prefer hmacSHA256WithKey:data: which uses SHA-256.

 @param key The secret key for HMAC computation (nonnull).
 @param data The data to authenticate (nonnull).
 @return The HMAC-SHA1 digest, or nil if key or data is nil.
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
+ (NSString *)hexStringFromData:(NSData *)data {
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (int i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return [NSString stringWithString:hex];
}

@end
