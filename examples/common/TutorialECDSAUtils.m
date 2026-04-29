/*!
 @file TutorialECDSAUtils.m

 @abstract Cross-platform ECDSA P-256 key generation, signing, and verification.

 @discussion macOS implementation uses Apple Security framework (SecKey).
 GNUstep/Linux implementation uses OpenSSL (EC_KEY, ECDSA_sign, ECDSA_verify).

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "TutorialECDSAUtils.h"
#import "TutorialBase64URL.h"

#if defined(__APPLE__) && !defined(GNUSTEP)
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#else
#import <openssl/ec.h>
#import <openssl/evp.h>
#import <openssl/sha.h>
#import <openssl/pem.h>
#import <openssl/err.h>
#endif

NSString * const TutorialECDSAErrorDomain = @"com.atproto.tutorial.ecdsa";

#pragma mark - TutorialECDSAKeyPair

@implementation TutorialECDSAKeyPair

- (instancetype)initWithKeyID:(NSString *)keyID
                publicKeyData:(NSData *)publicKeyData
                    publicJWK:(NSDictionary *)publicJWK
                   privateJWK:(NSDictionary *)privateJWK
                  thumbprint:(NSString *)thumbprint {
    self = [super init];
    if (self) {
        _keyID = [keyID copy];
        _publicKeyData = [publicKeyData copy];
        _publicJWK = [publicJWK copy];
        _privateJWK = [privateJWK copy];
        _thumbprint = [thumbprint copy];
    }
    return self;
}

@end

#pragma mark - DER ↔ Raw Conversion

@implementation TutorialECDSAUtils

+ (nullable NSData *)rawSignatureFromDER:(NSData *)der
                            expectedSize:(size_t)expectedSize
                                   error:(NSError **)error {
    const uint8_t *bytes = der.bytes;
    size_t length = der.length;
    size_t offset = 0;

    if (length < 8 || bytes[offset++] != 0x30) {
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorInvalidSignature
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid DER sequence tag"}];
        return nil;
    }

    // Read SEQUENCE length
    size_t seqLen = 0;
    if (offset < length) {
        uint8_t first = bytes[offset++];
        if ((first & 0x80) == 0) {
            seqLen = first;
        } else {
            size_t byteCount = first & 0x7F;
            for (size_t i = 0; i < byteCount && offset < length; i++) {
                seqLen = (seqLen << 8) | bytes[offset++];
            }
        }
    }

    // Read INTEGER r
    if (offset >= length || bytes[offset++] != 0x02) {
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorInvalidSignature
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid DER integer tag for r"}];
        return nil;
    }
    size_t rLen = bytes[offset++];
    const uint8_t *rBytes = bytes + offset;
    offset += rLen;

    // Read INTEGER s
    if (offset >= length || bytes[offset++] != 0x02) {
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorInvalidSignature
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid DER integer tag for s"}];
        return nil;
    }
    size_t sLen = bytes[offset++];
    const uint8_t *sBytes = bytes + offset;

    // Strip leading zeros
    while (rLen > 0 && rBytes[0] == 0x00) { rBytes++; rLen--; }
    while (sLen > 0 && sBytes[0] == 0x00) { sBytes++; sLen--; }

    if (rLen > expectedSize || sLen > expectedSize) {
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorInvalidSignature
                                            userInfo:@{NSLocalizedDescriptionKey: @"Signature component too large"}];
        return nil;
    }

    // Pad to expectedSize and concatenate
    NSMutableData *raw = [NSMutableData dataWithLength:expectedSize * 2];
    uint8_t *rawBytes = raw.mutableBytes;
    memcpy(rawBytes + (expectedSize - rLen), rBytes, rLen);
    memcpy(rawBytes + expectedSize + (expectedSize - sLen), sBytes, sLen);
    return raw;
}

+ (nullable NSData *)derSignatureFromRaw:(NSData *)raw
                                    error:(NSError **)error {
    if (raw.length % 2 != 0 || raw.length == 0) {
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorInvalidSignature
                                            userInfo:@{NSLocalizedDescriptionKey: @"Raw signature must have even length"}];
        return nil;
    }

    NSUInteger half = raw.length / 2;
    NSData *rData = [raw subdataWithRange:NSMakeRange(0, half)];
    NSData *sData = [raw subdataWithRange:NSMakeRange(half, half)];

    // Strip leading zeros, then add 0x00 prefix if high bit set
    NSMutableData *r = [rData mutableCopy];
    while (r.length > 0 && ((const uint8_t *)r.bytes)[0] == 0x00) {
        [r replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
    }
    if (r.length == 0 || (((const uint8_t *)r.bytes)[0] & 0x80)) {
        uint8_t zero = 0x00;
        [r replaceBytesInRange:NSMakeRange(0, 0) withBytes:&zero length:1];
    }

    NSMutableData *s = [sData mutableCopy];
    while (s.length > 0 && ((const uint8_t *)s.bytes)[0] == 0x00) {
        [s replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
    }
    if (s.length == 0 || (((const uint8_t *)s.bytes)[0] & 0x80)) {
        uint8_t zero = 0x00;
        [s replaceBytesInRange:NSMakeRange(0, 0) withBytes:&zero length:1];
    }

    // Build DER: SEQUENCE { INTEGER r, INTEGER s }
    NSMutableData *content = [NSMutableData data];
    uint8_t intTag = 0x02;
    [content appendBytes:&intTag length:1];
    uint8_t rLen = (uint8_t)r.length;
    [content appendBytes:&rLen length:1];
    [content appendData:r];
    [content appendBytes:&intTag length:1];
    uint8_t sLen = (uint8_t)s.length;
    [content appendBytes:&sLen length:1];
    [content appendData:s];

    NSMutableData *sequence = [NSMutableData data];
    uint8_t seqTag = 0x30;
    [sequence appendBytes:&seqTag length:1];
    uint8_t seqLength = (uint8_t)content.length;
    [sequence appendBytes:&seqLength length:1];
    [sequence appendData:content];
    return sequence;
}

+ (nullable NSString *)thumbprintForJWK:(NSDictionary *)jwk
                                   error:(NSError **)error {
    // RFC 7638: canonical form is sorted keys, no whitespace
    // Required keys for EC: crv, kty, x, y (alphabetical order)
    NSDictionary *canonical = @{
        @"crv": jwk[@"crv"] ?: @"",
        @"kty": jwk[@"kty"] ?: @"",
        @"x": jwk[@"x"] ?: @"",
        @"y": jwk[@"y"] ?: @""
    };

    NSData *json = [NSJSONSerialization dataWithJSONObject:canonical
                                                   options:NSJSONWritingSortedKeys
                                                     error:error];
    if (!json) return nil;

    // SHA-256 hash
#if defined(__APPLE__) && !defined(GNUSTEP)
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(json.bytes, (CC_LONG)json.length, digest);
#else
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256(json.bytes, json.length, digest);
#endif

    NSData *digestData = [NSData dataWithBytes:digest length:32];
    return [TutorialBase64URL encode:digestData];
}

#pragma mark - macOS Implementation (Security.framework)

#if defined(__APPLE__) && !defined(GNUSTEP)

+ (nullable TutorialECDSAKeyPair *)generateKeyPairWithError:(NSError **)error {
    // Generate EC P-256 key pair using Security framework (SecKeyCreateRandomKey)
    NSDictionary *attrs = @{
        (id)kSecAttrKeyType: (id)kSecAttrKeyTypeEC,
        (id)kSecAttrKeySizeInBits: @256,
        (id)kSecPrivateKeyAttrs: @{
            (id)kSecAttrIsPermanent: @NO
        }
    };

    CFErrorRef createError = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attrs, &createError);

    if (!privateKey) {
        if (error) {
            NSString *desc = createError
                ? [NSString stringWithFormat:@"Key generation failed: %@", (__bridge NSString *)CFErrorCopyDescription(createError)]
                : @"Key generation failed: unknown error";
            *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                         code:TutorialECDSAErrorKeyGenerationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: desc}];
        }
        if (createError) CFRelease(createError);
        return nil;
    }

    // Derive public key from private key
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    if (!publicKey) {
        CFRelease(privateKey);
        if (error) {
            *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                         code:TutorialECDSAErrorKeyGenerationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to derive public key"}];
        }
        return nil;
    }

    // Extract public key data (uncompressed point: 0x04 || x || y)
    CFDataRef publicKeyDataRef = SecKeyCopyExternalRepresentation(publicKey, NULL);
    NSData *publicKeyData = (__bridge_transfer NSData *)publicKeyDataRef;

    // Extract private key data (for JWK export)
    CFDataRef privateKeyDataRef = SecKeyCopyExternalRepresentation(privateKey, NULL);
    NSData *privateKeyFullData = (__bridge_transfer NSData *)privateKeyDataRef;

    // Build JWK
    NSString *keyID = [[NSUUID UUID] UUIDString];
    NSData *xData = [publicKeyData subdataWithRange:NSMakeRange(1, 32)];
    NSData *yData = [publicKeyData subdataWithRange:NSMakeRange(33, 32)];
    NSString *x = [TutorialBase64URL encode:xData];
    NSString *y = [TutorialBase64URL encode:yData];

    NSDictionary *publicJWK = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": x,
        @"y": y
    };

    // Private key data is: 0x04 || x || y || 0x?? || d (last 32 bytes after the public key)
    // SecKeyCopyExternalRepresentation for EC returns: 0x04 || x(32) || y(32) || d(32)
    NSData *dData = nil;
    if (privateKeyFullData.length == 97) {
        // Format: 0x04 || x(32) || y(32) || d(32)
        dData = [privateKeyFullData subdataWithRange:NSMakeRange(65, 32)];
    } else if (privateKeyFullData.length == 32) {
        // Some implementations return just the private scalar
        dData = privateKeyFullData;
    }

    NSString *d = dData ? [TutorialBase64URL encode:dData] : @"";
    NSDictionary *privateJWK = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": x,
        @"y": y,
        @"d": d
    };

    NSString *thumbprint = [self thumbprintForJWK:publicJWK error:nil];

    CFRelease(privateKey);
    CFRelease(publicKey);

    return [[TutorialECDSAKeyPair alloc] initWithKeyID:keyID
                                          publicKeyData:publicKeyData
                                              publicJWK:publicJWK
                                             privateJWK:privateJWK
                                            thumbprint:thumbprint];
}

+ (nullable NSData *)signData:(NSData *)data
                withPrivateKey:(NSDictionary *)privateKeyJWK
                         error:(NSError **)error {
    // Create SecKeyRef from private JWK
    NSData *xData = [TutorialBase64URL decode:privateKeyJWK[@"x"]];
    NSData *yData = [TutorialBase64URL decode:privateKeyJWK[@"y"]];
    NSData *dData = [TutorialBase64URL decode:privateKeyJWK[@"d"]];

    if (!xData || !yData || !dData) {
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorInvalidJWK
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid JWK: missing x, y, or d"}];
        return nil;
    }

    // Build uncompressed point + private scalar: 0x04 || x || y || d
    NSMutableData *keyData = [NSMutableData dataWithCapacity:97];
    uint8_t prefix = 0x04;
    [keyData appendBytes:&prefix length:1];
    [keyData appendData:xData];
    [keyData appendData:yData];
    [keyData appendData:dData];

    NSDictionary *attrs = @{
        (id)kSecAttrKeyType: (id)kSecAttrKeyTypeEC,
        (id)kSecAttrKeyClass: (id)kSecAttrKeyClassPrivate,
        (id)kSecAttrKeySizeInBits: @256
    };

    SecKeyRef privateKey = SecKeyCreateWithData((__bridge CFDataRef)keyData,
                                                (__bridge CFDictionaryRef)attrs, NULL);
    if (!privateKey) {
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorInvalidKeyData
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to create SecKeyRef from JWK"}];
        return nil;
    }

    // Sign with ES256
    CFErrorRef signError = NULL;
    CFDataRef signatureRef = SecKeyCreateSignature(privateKey,
                                                   kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                   (__bridge CFDataRef)data,
                                                   &signError);
    CFRelease(privateKey);

    if (!signatureRef) {
        if (error) {
            NSError *nsError = (__bridge_transfer NSError *)signError;
            *error = nsError ?: [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                    code:TutorialECDSAErrorSigningFailed
                                                userInfo:@{NSLocalizedDescriptionKey: @"ES256 signing failed"}];
        }
        if (signError) CFRelease(signError);
        return nil;
    }

    NSData *derSignature = (__bridge_transfer NSData *)signatureRef;

    // Convert DER → raw (r||s) for JWT format
    NSData *rawSignature = [self rawSignatureFromDER:derSignature expectedSize:32 error:error];
    return rawSignature;
}

+ (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
          withPublicKey:(NSDictionary *)publicKeyJWK
                  error:(NSError **)error {
    // Create SecKeyRef from public JWK
    NSData *xData = [TutorialBase64URL decode:publicKeyJWK[@"x"]];
    NSData *yData = [TutorialBase64URL decode:publicKeyJWK[@"y"]];

    if (!xData || !yData) {
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorInvalidJWK
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid JWK: missing x or y"}];
        return NO;
    }

    // Build uncompressed point: 0x04 || x || y
    NSMutableData *keyData = [NSMutableData dataWithCapacity:65];
    uint8_t prefix = 0x04;
    [keyData appendBytes:&prefix length:1];
    [keyData appendData:xData];
    [keyData appendData:yData];

    NSDictionary *attrs = @{
        (id)kSecAttrKeyType: (id)kSecAttrKeyTypeEC,
        (id)kSecAttrKeyClass: (id)kSecAttrKeyClassPublic,
        (id)kSecAttrKeySizeInBits: @256
    };

    SecKeyRef publicKey = SecKeyCreateWithData((__bridge CFDataRef)keyData,
                                               (__bridge CFDictionaryRef)attrs, NULL);
    if (!publicKey) {
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorInvalidKeyData
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to create SecKeyRef from JWK"}];
        return NO;
    }

    // Convert raw (r||s) → DER for Security framework
    NSData *derSignature = [self derSignatureFromRaw:signature error:error];
    if (!derSignature) {
        CFRelease(publicKey);
        return NO;
    }

    // Verify
    CFErrorRef verifyError = NULL;
    BOOL result = SecKeyVerifySignature(publicKey,
                                         kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                         (__bridge CFDataRef)data,
                                         (__bridge CFDataRef)derSignature,
                                         &verifyError);
    CFRelease(publicKey);

    if (!result && error) {
        NSError *nsError = (__bridge_transfer NSError *)verifyError;
        *error = nsError ?: [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorVerificationFailed
                                            userInfo:@{NSLocalizedDescriptionKey: @"ES256 verification failed"}];
    }
    if (verifyError && !*error) CFRelease(verifyError);

    return result;
}

#else // GNUstep / Linux (OpenSSL)

+ (nullable TutorialECDSAKeyPair *)generateKeyPairWithError:(NSError **)error {
    EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
    if (!ecKey) {
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorKeyGenerationFailed
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC_KEY"}];
        return nil;
    }

    if (!EC_KEY_generate_key(ecKey)) {
        EC_KEY_free(ecKey);
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorKeyGenerationFailed
                                            userInfo:@{NSLocalizedDescriptionKey: @"EC_KEY_generate_key failed"}];
        return nil;
    }

    // Extract public key (uncompressed point)
    const EC_POINT *pubPoint = EC_KEY_get0_public_key(ecKey);
    const EC_GROUP *group = EC_KEY_get0_group(ecKey);
    size_t pubLen = EC_POINT_point2oct(group, pubPoint, POINT_CONVERSION_UNCOMPRESSED, NULL, 0, NULL);
    NSMutableData *publicKeyData = [NSMutableData dataWithLength:pubLen];
    EC_POINT_point2oct(group, pubPoint, POINT_CONVERSION_UNCOMPRESSED,
                       (uint8_t *)publicKeyData.mutableBytes, pubLen, NULL);

    // Extract private key scalar
    const BIGNUM *privBN = EC_KEY_get0_private_key(ecKey);
    NSMutableData *dData = [NSMutableData dataWithLength:32];
    BN_bn2binpad(privBN, (uint8_t *)dData.mutableBytes, 32);

    // Build JWK
    NSData *xData = [publicKeyData subdataWithRange:NSMakeRange(1, 32)];
    NSData *yData = [publicKeyData subdataWithRange:NSMakeRange(33, 32)];
    NSString *x = [TutorialBase64URL encode:xData];
    NSString *y = [TutorialBase64URL encode:yData];
    NSString *d = [TutorialBase64URL encode:dData];

    NSString *keyID = [[NSUUID UUID] UUIDString];

    NSDictionary *publicJWK = @{@"kty": @"EC", @"crv": @"P-256", @"x": x, @"y": y};
    NSDictionary *privateJWK = @{@"kty": @"EC", @"crv": @"P-256", @"x": x, @"y": y, @"d": d};
    NSString *thumbprint = [self thumbprintForJWK:publicJWK error:nil];

    EC_KEY_free(ecKey);

    return [[TutorialECDSAKeyPair alloc] initWithKeyID:keyID
                                          publicKeyData:publicKeyData
                                              publicJWK:publicJWK
                                             privateJWK:privateJWK
                                            thumbprint:thumbprint];
}

+ (nullable NSData *)signData:(NSData *)data
                withPrivateKey:(NSDictionary *)privateKeyJWK
                         error:(NSError **)error {
    EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
    if (!ecKey) {
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorInvalidKeyData
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC_KEY"}];
        return nil;
    }

    // Set private key from JWK
    NSData *dData = [TutorialBase64URL decode:privateKeyJWK[@"d"]];
    BIGNUM *privBN = BN_bin2bn(dData.bytes, (int)dData.length, NULL);
    EC_KEY_set_private_key(ecKey, privBN);
    BN_free(privBN);

    // Derive public key from private key
    const EC_GROUP *group = EC_KEY_get0_group(ecKey);
    EC_POINT *pubPoint = EC_POINT_new(group);
    EC_POINT_mul(group, pubPoint, EC_KEY_get0_private_key(ecKey), NULL, NULL, NULL);
    EC_KEY_set_public_key(ecKey, pubPoint);
    EC_POINT_free(pubPoint);

    // Sign
    unsigned char derBuf[256];
    unsigned int derLen = 0;
    if (!ECDSA_sign(0, data.bytes, (int)data.length, derBuf, &derLen, ecKey)) {
        EC_KEY_free(ecKey);
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorSigningFailed
                                            userInfo:@{NSLocalizedDescriptionKey: @"ECDSA_sign failed"}];
        return nil;
    }

    EC_KEY_free(ecKey);

    NSData *derSignature = [NSData dataWithBytes:derBuf length:derLen];
    return [self rawSignatureFromDER:derSignature expectedSize:32 error:error];
}

+ (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
          withPublicKey:(NSDictionary *)publicKeyJWK
                  error:(NSError **)error {
    EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
    if (!ecKey) {
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorInvalidKeyData
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC_KEY"}];
        return NO;
    }

    // Set public key from JWK
    NSData *xData = [TutorialBase64URL decode:publicKeyJWK[@"x"]];
    NSData *yData = [TutorialBase64URL decode:publicKeyJWK[@"y"]];

    NSMutableData *pubPointData = [NSMutableData dataWithCapacity:65];
    uint8_t prefix = 0x04;
    [pubPointData appendBytes:&prefix length:1];
    [pubPointData appendData:xData];
    [pubPointData appendData:yData];

    const EC_GROUP *group = EC_KEY_get0_group(ecKey);
    EC_POINT *pubPoint = EC_POINT_new(group);
    if (!EC_POINT_oct2point(group, pubPoint, pubPointData.bytes, pubPointData.length, NULL)) {
        EC_POINT_free(pubPoint);
        EC_KEY_free(ecKey);
        if (error) *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                                code:TutorialECDSAErrorInvalidKeyData
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to set public key point"}];
        return NO;
    }
    EC_KEY_set_public_key(ecKey, pubPoint);
    EC_POINT_free(pubPoint);

    // Convert raw → DER for OpenSSL
    NSData *derSignature = [self derSignatureFromRaw:signature error:error];
    if (!derSignature) {
        EC_KEY_free(ecKey);
        return NO;
    }

    // Verify
    int result = ECDSA_verify(0, data.bytes, (int)data.length,
                              derSignature.bytes, (int)derSignature.length, ecKey);
    EC_KEY_free(ecKey);

    if (result != 1 && error) {
        *error = [NSError errorWithDomain:TutorialECDSAErrorDomain
                                     code:TutorialECDSAErrorVerificationFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"ES256 verification failed"}];
    }

    return result == 1;
}

#endif // Platform check

@end
