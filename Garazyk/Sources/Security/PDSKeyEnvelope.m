// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Security/PDSKeyEnvelope.h"
#import "Security/PDSSecurityCompare.h"
#import "Compat/PDSTypes.h"

#if PDS_PLATFORM_APPLE
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#import <Security/Security.h>
#else
#import "CommonCrypto/CommonCryptor.h"
#import "CommonCrypto/CommonDigest.h"
#import "CommonCrypto/CommonHMAC.h"
#import "Security/Security.h"
#endif

static const uint8_t kPDSKeyEnvelopeMagic[] = {
    'P', 'D', 'S', 'K', 'E', 'Y', '1', 0
};
static const NSUInteger kPDSKeyEnvelopeMagicLength = sizeof(kPDSKeyEnvelopeMagic);
static const NSUInteger kPDSKeyEnvelopeIVLength = kCCBlockSizeAES128;
static const NSUInteger kPDSKeyEnvelopeMACLength = CC_SHA256_DIGEST_LENGTH;

@implementation PDSKeyEnvelope

+ (NSData *)macKeyForKey:(NSData *)key {
    static const uint8_t context[] = "pds-key-envelope-mac-v1";
    NSMutableData *input = [NSMutableData dataWithData:key];
    [input appendBytes:context length:sizeof(context) - 1];

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(input.bytes, (CC_LONG)input.length, digest);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

+ (NSData *)hmacForData:(NSData *)data key:(NSData *)key {
    uint8_t mac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, mac);
    return [NSData dataWithBytes:mac length:sizeof(mac)];
}

+ (nullable NSData *)seal:(NSData *)data
                  withKey:(NSData *)key
                    error:(NSError **)error {
    if (key.length != kCCKeySizeAES256) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSKeyEnvelope" code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid key size (must be 32 bytes)"}];
        }
        return nil;
    }
    if (!data) return nil;

    uint8_t iv[kPDSKeyEnvelopeIVLength];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(iv), iv) != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSKeyEnvelope" code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate random IV"}];
        }
        return nil;
    }

    size_t bufferSize = data.length + kCCBlockSizeAES128;
    NSMutableData *ciphertext = [NSMutableData dataWithLength:bufferSize];
    size_t encryptedBytes = 0;
    CCCryptorStatus status = CCCrypt(kCCEncrypt,
                                     kCCAlgorithmAES128,
                                     kCCOptionPKCS7Padding,
                                     key.bytes,
                                     kCCKeySizeAES256,
                                     iv,
                                     data.bytes,
                                     data.length,
                                     ciphertext.mutableBytes,
                                     bufferSize,
                                     &encryptedBytes);
    if (status != kCCSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSKeyEnvelope" code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Encryption failed"}];
        }
        return nil;
    }
    ciphertext.length = encryptedBytes;

    NSMutableData *envelope = [NSMutableData dataWithBytes:kPDSKeyEnvelopeMagic
                                                    length:kPDSKeyEnvelopeMagicLength];
    [envelope appendBytes:iv length:sizeof(iv)];
    [envelope appendData:ciphertext];

    NSData *mac = [self hmacForData:envelope key:[self macKeyForKey:key]];
    [envelope appendData:mac];
    return envelope;
}

+ (nullable NSData *)openEnvelope:(NSData *)envelope
                         withKey:(NSData *)key
                           error:(NSError **)error {
    if (key.length != kCCKeySizeAES256) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSKeyEnvelope" code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid key size"}];
        }
        return nil;
    }
    if (![self isVersionedEnvelope:envelope]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSKeyEnvelope" code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid envelope magic or version"}];
        }
        return nil;
    }
    if (envelope.length < kPDSKeyEnvelopeMagicLength + kPDSKeyEnvelopeIVLength + kPDSKeyEnvelopeMACLength) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSKeyEnvelope" code:-5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Envelope too short"}];
        }
        return nil;
    }

    NSUInteger authenticatedLength = envelope.length - kPDSKeyEnvelopeMACLength;
    NSData *authenticated = [envelope subdataWithRange:NSMakeRange(0, authenticatedLength)];
    NSData *expectedMAC = [self hmacForData:authenticated key:[self macKeyForKey:key]];
    NSData *actualMAC = [envelope subdataWithRange:NSMakeRange(authenticatedLength, kPDSKeyEnvelopeMACLength)];
    if (![PDSSecurityCompare constantTimeEqualData:expectedMAC data:actualMAC]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSKeyEnvelope" code:-6
                                     userInfo:@{NSLocalizedDescriptionKey: @"MAC verification failed"}];
        }
        return nil;
    }

    NSRange ivRange = NSMakeRange(kPDSKeyEnvelopeMagicLength, kPDSKeyEnvelopeIVLength);
    NSData *iv = [envelope subdataWithRange:ivRange];
    NSUInteger cipherOffset = NSMaxRange(ivRange);
    NSData *ciphertext = [envelope subdataWithRange:NSMakeRange(cipherOffset, authenticatedLength - cipherOffset)];

    size_t bufferSize = ciphertext.length + kCCBlockSizeAES128;
    NSMutableData *plaintext = [NSMutableData dataWithLength:bufferSize];
    size_t decryptedBytes = 0;
    CCCryptorStatus status = CCCrypt(kCCDecrypt,
                                     kCCAlgorithmAES128,
                                     kCCOptionPKCS7Padding,
                                     key.bytes,
                                     kCCKeySizeAES256,
                                     iv.bytes,
                                     ciphertext.bytes,
                                     ciphertext.length,
                                     plaintext.mutableBytes,
                                     bufferSize,
                                     &decryptedBytes);
    if (status != kCCSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSKeyEnvelope" code:-7
                                     userInfo:@{NSLocalizedDescriptionKey: @"Decryption failed"}];
        }
        return nil;
    }
    plaintext.length = decryptedBytes;
    return plaintext;
}

+ (BOOL)isVersionedEnvelope:(NSData *)data {
    if (data.length < kPDSKeyEnvelopeMagicLength) {
        return NO;
    }
    return memcmp(data.bytes, kPDSKeyEnvelopeMagic, kPDSKeyEnvelopeMagicLength) == 0;
}

@end
