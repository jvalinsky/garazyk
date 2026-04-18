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
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <Security/Security.h>

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
    if (a == nil && b == nil) {
        return YES;
    }
    if (a == nil || b == nil) {
        return NO;
    }
    
    NSUInteger aLen = a.length;
    NSUInteger bLen = b.length;
    
    if (aLen != bLen) {
        volatile uint8_t dummy = 0;
        const char *bBytes = [b UTF8String];
        for (NSUInteger i = 0; i < bLen; i++) {
            dummy |= (uint8_t)bBytes[i];
        }
        (void)dummy;
        return NO;
    }
    
    const char *aBytes = [a UTF8String];
    const char *bBytes = [b UTF8String];
    volatile uint8_t result = 0;
    
    for (NSUInteger i = 0; i < aLen; i++) {
        result |= (uint8_t)(aBytes[i] ^ bBytes[i]);
    }
    
    return result == 0;
}

+ (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key {
    if (key.length != 32) return nil;
    
    uint8_t ivBytes[kCCBlockSizeAES128];
    if (SecRandomCopyBytes(kSecRandomDefault, kCCBlockSizeAES128, ivBytes) != errSecSuccess) {
        return nil;
    }
    
    size_t bufferSize = data.length + kCCBlockSizeAES128;
    NSMutableData *cipherData = [NSMutableData dataWithLength:bufferSize];
    
    size_t numBytesEncrypted = 0;
    CCCryptorStatus status = CCCrypt(kCCEncrypt,
                                     kCCAlgorithmAES128,
                                     kCCOptionPKCS7Padding,
                                     key.bytes, kCCKeySizeAES256,
                                     ivBytes,
                                     data.bytes, data.length,
                                     cipherData.mutableBytes, bufferSize,
                                     &numBytesEncrypted);
    
    if (status != kCCSuccess) {
        return nil;
    }
    
    cipherData.length = numBytesEncrypted;
    
    NSMutableData *result = [NSMutableData dataWithBytes:ivBytes length:kCCBlockSizeAES128];
    [result appendData:cipherData];
    
    return result;
}

+ (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key {
    if (key.length != 32 || data.length < kCCBlockSizeAES128) return nil;
    
    const uint8_t *iv = data.bytes;
    NSData *ciphertext = [data subdataWithRange:NSMakeRange(kCCBlockSizeAES128, data.length - kCCBlockSizeAES128)];
    
    size_t bufferSize = ciphertext.length + kCCBlockSizeAES128;
    NSMutableData *plainData = [NSMutableData dataWithLength:bufferSize];
    
    size_t numBytesDecrypted = 0;
    CCCryptorStatus status = CCCrypt(kCCDecrypt,
                                     kCCAlgorithmAES128,
                                     kCCOptionPKCS7Padding,
                                     key.bytes, kCCKeySizeAES256,
                                     iv,
                                     ciphertext.bytes, ciphertext.length,
                                     plainData.mutableBytes, bufferSize,
                                     &numBytesDecrypted);
    
    if (status != kCCSuccess) {
        return nil;
    }
    
    plainData.length = numBytesDecrypted;
    return plainData;
}

/*!
 @method deriveKeyFromPassword:salt:

 @abstract Derives a 32-byte encryption key from a password and salt using PBKDF2-HMAC-SHA256.

 @discussion Uses PBKDF2 with the following parameters:
 - Algorithm: HMAC-SHA256
 - Iterations: 100,000 (OWASP 2023 minimum recommendation is 600,000)
 - Output length: 32 bytes (256 bits)

 Note: This method uses 100,000 iterations for encryption key derivation to balance
 security with performance for frequently-executed operations. This is higher than
 legacy recommendations but lower than the current OWASP guideline of 600,000 for
 password hashing. For password hashing (PDSAccountService), 600,000 iterations are used.

 Consider increasing iterations to 600,000 in a future version if performance allows.

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
                                      100000,
                                      derivedKey.mutableBytes, 32);
    
    if (result != kCCSuccess) {
        return nil;
    }
    
    return derivedKey;
}

@end
