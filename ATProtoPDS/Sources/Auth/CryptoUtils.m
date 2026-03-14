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
 @method base64URLEncode:

 @abstract Base64URL-encodes data without padding characters.

 @discussion Produces a URL-safe base64 string by substituting '+' with '-'
 and '/' with '_', and stripping trailing '=' padding. Used throughout the
 authentication layer for JWT and JWK encoding.

 @param data The binary data to encode (nonnull).
 @return Base64URL-encoded string.
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

/*!
 @method hexStringFromData:

 @abstract Converts binary data to a lowercase hexadecimal string.

 @discussion Each byte is represented as two lowercase hex characters (00–ff).
 Useful for logging and displaying digest values.

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

// ---------------------------------------------------------------------------
// AES-256-GCM (authenticated encryption)
//
// Ciphertext format (version 0x02):
//   version(1) || nonce(12) || tag(16) || ciphertext(N)
//
// Legacy format (version 0x01, decrypt-only):
//   version(1) || IV(16) || CBC-ciphertext(N)    [CBC+PKCS7, no auth tag]
//
// Blobs produced before the GCM upgrade have no version byte; they begin
// directly with the 16-byte IV.  They are detected by the absence of a
// leading 0x01 or 0x02 byte and handled by the legacy path for compatibility.
// ---------------------------------------------------------------------------

#define PDS_AES_GCM_VERSION  ((uint8_t)0x02)
#define PDS_AES_CBC_VERSION  ((uint8_t)0x01)
#define PDS_AES_GCM_NONCE_LEN  12
#define PDS_AES_GCM_TAG_LEN    16

// Secure random helper: Apple uses SecRandomCopyBytes; GNUstep reads /dev/urandom.
static BOOL PDSSecureRandomBytes(void *buf, size_t len) {
#if defined(__APPLE__)
    return SecRandomCopyBytes(kSecRandomDefault, len, buf) == errSecSuccess;
#else
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) return NO;
    ssize_t n = read(fd, buf, len);
    close(fd);
    return (size_t)n == len;
#endif
}

// GCM encrypt — platform-conditional implementation.
static NSData *PDSAESGCMEncrypt(const void *plaintext, size_t ptLen,
                                 const void *key,       size_t keyLen,
                                 const void *nonce,     size_t nonceLen,
                                 void       *tagOut,    size_t tagLen) {
#if defined(__APPLE__)
    // CommonCrypto multi-step GCM API (public, available macOS 10.9+).
    CCCryptorRef cref = NULL;
    CCCryptorStatus cs = CCCryptorCreateWithMode(
        kCCEncrypt, kCCModeGCM, kCCAlgorithmAES,
        ccNoPadding, NULL, key, keyLen,
        NULL, 0, 0, 0, &cref);
    if (cs != kCCSuccess || !cref) return nil;

    cs = CCCryptorGCMAddIV(cref, nonce, nonceLen);
    if (cs != kCCSuccess) { CCCryptorRelease(cref); return nil; }

    NSMutableData *ct = [NSMutableData dataWithLength:ptLen];
    size_t moved = 0;
    cs = CCCryptorGCMEncrypt(cref, plaintext, ptLen, ct.mutableBytes, &moved);
    if (cs != kCCSuccess) { CCCryptorRelease(cref); return nil; }

    cs = CCCryptorGCMFinal(cref, tagOut, &tagLen);
    CCCryptorRelease(cref);
    if (cs != kCCSuccess) return nil;

    return ct;
#else
    // OpenSSL EVP AES-256-GCM (linked via PDSOpenSSLSessionKeyManager dependency).
    #include <openssl/evp.h>
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return nil;

    int ok = EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL);
    ok = ok && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int)nonceLen, NULL);
    ok = ok && EVP_EncryptInit_ex(ctx, NULL, NULL, (const unsigned char *)key,
                                  (const unsigned char *)nonce);
    if (!ok) { EVP_CIPHER_CTX_free(ctx); return nil; }

    NSMutableData *ct = [NSMutableData dataWithLength:ptLen];
    int len = 0;
    ok = EVP_EncryptUpdate(ctx, ct.mutableBytes, &len,
                           (const unsigned char *)plaintext, (int)ptLen);
    int totalLen = len;
    ok = ok && EVP_EncryptFinal_ex(ctx, (unsigned char *)ct.mutableBytes + totalLen, &len);
    totalLen += len;
    ok = ok && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, (int)tagLen, tagOut);
    EVP_CIPHER_CTX_free(ctx);

    if (!ok) return nil;
    ct.length = totalLen;
    return ct;
#endif
}

// GCM decrypt — platform-conditional implementation.
static NSData *PDSAESGCMDecrypt(const void *ciphertext, size_t ctLen,
                                 const void *key,        size_t keyLen,
                                 const void *nonce,      size_t nonceLen,
                                 const void *tag,        size_t tagLen) {
#if defined(__APPLE__)
    CCCryptorRef cref = NULL;
    CCCryptorStatus cs = CCCryptorCreateWithMode(
        kCCDecrypt, kCCModeGCM, kCCAlgorithmAES,
        ccNoPadding, NULL, key, keyLen,
        NULL, 0, 0, 0, &cref);
    if (cs != kCCSuccess || !cref) return nil;

    cs = CCCryptorGCMAddIV(cref, nonce, nonceLen);
    if (cs != kCCSuccess) { CCCryptorRelease(cref); return nil; }

    NSMutableData *pt = [NSMutableData dataWithLength:ctLen];
    size_t moved = 0;
    cs = CCCryptorGCMDecrypt(cref, ciphertext, ctLen, pt.mutableBytes, &moved);
    if (cs != kCCSuccess) { CCCryptorRelease(cref); return nil; }

    // Verify the authentication tag.
    size_t actualTagLen = tagLen;
    uint8_t computedTag[PDS_AES_GCM_TAG_LEN];
    cs = CCCryptorGCMFinal(cref, computedTag, &actualTagLen);
    CCCryptorRelease(cref);
    if (cs != kCCSuccess) return nil;
    if (actualTagLen != tagLen || memcmp(computedTag, tag, tagLen) != 0) return nil;

    return pt;
#else
    #include <openssl/evp.h>
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return nil;

    int ok = EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL);
    ok = ok && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int)nonceLen, NULL);
    ok = ok && EVP_DecryptInit_ex(ctx, NULL, NULL, (const unsigned char *)key,
                                  (const unsigned char *)nonce);
    if (!ok) { EVP_CIPHER_CTX_free(ctx); return nil; }

    NSMutableData *pt = [NSMutableData dataWithLength:ctLen];
    int len = 0;
    ok = EVP_DecryptUpdate(ctx, pt.mutableBytes, &len,
                           (const unsigned char *)ciphertext, (int)ctLen);
    // Set expected tag before calling Final.
    ok = ok && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, (int)tagLen,
                                   (void *)tag);
    int finalLen = 0;
    // A non-positive return from Final means tag verification failed.
    int finalResult = EVP_DecryptFinal_ex(ctx, (unsigned char *)pt.mutableBytes + len, &finalLen);
    EVP_CIPHER_CTX_free(ctx);
    if (!ok || finalResult <= 0) return nil;

    pt.length = len + finalLen;
    return pt;
#endif
}

// Legacy CBC decrypt — kept for reading pre-GCM data.
// Input format: IV(16) || ciphertext — no version byte.
static NSData *PDSAESCBCDecrypt(const void *iv, const void *ciphertext, size_t ctLen,
                                  const void *key, size_t keyLen) {
    size_t bufferSize = ctLen + kCCBlockSizeAES128;
    NSMutableData *plainData = [NSMutableData dataWithLength:bufferSize];
    size_t numBytesDecrypted = 0;
    CCCryptorStatus status = CCCrypt(kCCDecrypt,
                                     kCCAlgorithmAES128,
                                     kCCOptionPKCS7Padding,
                                     key, keyLen,
                                     iv,
                                     ciphertext, ctLen,
                                     plainData.mutableBytes, bufferSize,
                                     &numBytesDecrypted);
    if (status != kCCSuccess) return nil;
    plainData.length = numBytesDecrypted;
    return plainData;
}

+ (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key {
    if (key.length != 32 || !data) return nil;

    uint8_t nonce[PDS_AES_GCM_NONCE_LEN];
    if (!PDSSecureRandomBytes(nonce, sizeof(nonce))) return nil;

    uint8_t tag[PDS_AES_GCM_TAG_LEN];
    NSData *ciphertext = PDSAESGCMEncrypt(data.bytes, data.length,
                                           key.bytes, key.length,
                                           nonce, sizeof(nonce),
                                           tag, sizeof(tag));
    if (!ciphertext) return nil;

    // Layout: version(1) || nonce(12) || tag(16) || ciphertext
    NSMutableData *result = [NSMutableData dataWithCapacity:1 + sizeof(nonce) + sizeof(tag) + ciphertext.length];
    uint8_t version = PDS_AES_GCM_VERSION;
    [result appendBytes:&version        length:1];
    [result appendBytes:nonce           length:sizeof(nonce)];
    [result appendBytes:tag             length:sizeof(tag)];
    [result appendData:ciphertext];
    return result;
}

+ (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key {
    if (key.length != 32 || data.length < 1) return nil;

    const uint8_t *bytes = data.bytes;
    uint8_t version = bytes[0];

    if (version == PDS_AES_GCM_VERSION) {
        // GCM format: version(1) || nonce(12) || tag(16) || ciphertext
        const size_t overhead = 1 + PDS_AES_GCM_NONCE_LEN + PDS_AES_GCM_TAG_LEN;
        if (data.length < overhead) return nil;
        const uint8_t *nonce = bytes + 1;
        const uint8_t *tag   = bytes + 1 + PDS_AES_GCM_NONCE_LEN;
        const uint8_t *ct    = bytes + overhead;
        size_t         ctLen = data.length - overhead;
        return PDSAESGCMDecrypt(ct, ctLen,
                                key.bytes, key.length,
                                nonce, PDS_AES_GCM_NONCE_LEN,
                                tag,   PDS_AES_GCM_TAG_LEN);
    }

    if (version == PDS_AES_CBC_VERSION) {
        // Versioned legacy CBC: version(1) || IV(16) || ciphertext
        if (data.length < 1 + kCCBlockSizeAES128) return nil;
        const uint8_t *iv = bytes + 1;
        const uint8_t *ct = bytes + 1 + kCCBlockSizeAES128;
        size_t ctLen = data.length - 1 - kCCBlockSizeAES128;
        return PDSAESCBCDecrypt(iv, ct, ctLen, key.bytes, key.length);
    }

    // Unversioned legacy format: raw IV(16) || ciphertext (pre-GCM blobs).
    if (data.length < kCCBlockSizeAES128) return nil;
    const uint8_t *iv = bytes;
    const uint8_t *ct = bytes + kCCBlockSizeAES128;
    size_t ctLen = data.length - kCCBlockSizeAES128;
    return PDSAESCBCDecrypt(iv, ct, ctLen, key.bytes, key.length);
}

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
