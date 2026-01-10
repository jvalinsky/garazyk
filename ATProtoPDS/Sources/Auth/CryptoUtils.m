#import "Auth/CryptoUtils.h"
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

@implementation CryptoUtils

+ (nullable NSData *)hmacSHA1WithKey:(NSData *)key data:(NSData *)data {
    if (!key || !data) return nil;

    unsigned char cHMAC[CC_SHA1_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA1, key.bytes, key.length, data.bytes, data.length, cHMAC);

    return [NSData dataWithBytes:cHMAC length:CC_SHA1_DIGEST_LENGTH];
}

/**
 * Computes HMAC-SHA256 for the given data using the specified key.
 *
 * This method provides enhanced security compared to HMAC-SHA1 by using SHA-256,
 * which offers better resistance against collision attacks and is recommended
 * for cryptographic operations requiring strong integrity guarantees.
 *
 * @param key The secret key for HMAC computation. Must not be nil.
 * @param data The data to authenticate. Must not be nil.
 * @return The HMAC-SHA256 digest as NSData, or nil if key or data is nil.
 */
+ (nullable NSData *)hmacSHA256WithKey:(NSData *)key data:(NSData *)data {
    if (!key || !data) return nil;

    unsigned char hmac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, hmac);
    return [NSData dataWithBytes:hmac length:CC_SHA256_DIGEST_LENGTH];
}

+ (nullable NSData *)sha256:(NSData *)data {
    if (!data) return nil;
    
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    if (!CC_SHA256(data.bytes, (CC_LONG)data.length, hash)) {
        return nil;
    }
    
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}

+ (nullable NSData *)randomBytes:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes) != errSecSuccess) {
        return nil;
    }
    return data;
}

+ (NSString *)hexStringFromData:(NSData *)data {
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (int i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return [NSString stringWithString:hex];
}

@end
