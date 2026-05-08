#import "Auth/PDSKeyEnvelope.h"
#import "Security/PDSSecurityCompare.h"

#if !TARGET_OS_LINUX
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#import <Security/Security.h>
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

+ (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key {
    if (key.length != kCCKeySizeAES256 || !data) {
        return nil;
    }

    uint8_t iv[kPDSKeyEnvelopeIVLength];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(iv), iv) != errSecSuccess) {
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

+ (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key {
    if (key.length != kCCKeySizeAES256 || ![self isVersionedEnvelope:data]) {
        return nil;
    }
    if (data.length < kPDSKeyEnvelopeMagicLength + kPDSKeyEnvelopeIVLength + kPDSKeyEnvelopeMACLength) {
        return nil;
    }

    NSUInteger authenticatedLength = data.length - kPDSKeyEnvelopeMACLength;
    NSData *authenticated = [data subdataWithRange:NSMakeRange(0, authenticatedLength)];
    NSData *expectedMAC = [self hmacForData:authenticated key:[self macKeyForKey:key]];
    NSData *actualMAC = [data subdataWithRange:NSMakeRange(authenticatedLength, kPDSKeyEnvelopeMACLength)];
    if (![PDSSecurityCompare constantTimeEqualData:expectedMAC data:actualMAC]) {
        return nil;
    }

    NSRange ivRange = NSMakeRange(kPDSKeyEnvelopeMagicLength, kPDSKeyEnvelopeIVLength);
    NSData *iv = [data subdataWithRange:ivRange];
    NSUInteger cipherOffset = NSMaxRange(ivRange);
    NSData *ciphertext = [data subdataWithRange:NSMakeRange(cipherOffset, authenticatedLength - cipherOffset)];

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
