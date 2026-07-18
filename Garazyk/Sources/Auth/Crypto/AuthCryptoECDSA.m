// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AuthCryptoECDSA.m

 @abstract ECDSA signature format conversion implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Auth/Crypto/AuthCryptoECDSA.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"

@implementation AuthCryptoECDSA

+ (BOOL)readASN1Length:(const uint8_t *)bytes
                length:(size_t)length
                offset:(size_t *)offset
             outLength:(size_t *)outLength
                 error:(NSError **)error {
    if (*offset >= length) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-10
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ASN.1 length"}];
        }
        return NO;
    }
    uint8_t first = bytes[(*offset)++];
    if ((first & 0x80) == 0) {
        *outLength = first;
        return YES;
    }
    size_t byteCount = first & 0x7F;
    if (byteCount == 0 || byteCount > sizeof(size_t) || *offset + byteCount > length) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-10
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ASN.1 length"}];
        }
        return NO;
    }
    size_t value = 0;
    for (size_t i = 0; i < byteCount; i++) {
        value = (value << 8) | bytes[(*offset)++];
    }
    *outLength = value;
    return YES;
}

+ (nullable NSData *)rawSignatureFromDER:(NSData *)der expectedSize:(size_t)expectedSize error:(NSError **)error {
    const uint8_t *bytes = der.bytes;
    size_t length = der.length;
    size_t offset = 0;
    if (length < 8 || bytes[offset++] != 0x30) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature"}];
        }
        return nil;
    }
    size_t seqLen = 0;
    if (![self readASN1Length:bytes length:length offset:&offset outLength:&seqLen error:error]) {
        return nil;
    }
    if (offset + seqLen > length) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature length"}];
        }
        return nil;
    }
    if (bytes[offset++] != 0x02) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature"}];
        }
        return nil;
    }
    size_t rLen = 0;
    if (![self readASN1Length:bytes length:length offset:&offset outLength:&rLen error:error]) {
        return nil;
    }
    if (offset + rLen > length) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature"}];
        }
        return nil;
    }
    const uint8_t *rBytes = bytes + offset;
    offset += rLen;
    if (offset >= length || bytes[offset++] != 0x02) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature"}];
        }
        return nil;
    }
    size_t sLen = 0;
    if (![self readASN1Length:bytes length:length offset:&offset outLength:&sLen error:error]) {
        return nil;
    }
    if (offset + sLen > length) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature"}];
        }
        return nil;
    }
    const uint8_t *sBytes = bytes + offset;

    while (rLen > 0 && rBytes[0] == 0x00) { rBytes++; rLen--; }
    while (sLen > 0 && sBytes[0] == 0x00) { sBytes++; sLen--; }
    if (rLen > expectedSize || sLen > expectedSize) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA signature size"}];
        }
        return nil;
    }

    NSMutableData *raw = [NSMutableData dataWithLength:expectedSize * 2];
    uint8_t *rawBytes = raw.mutableBytes;
    memcpy(rawBytes + (expectedSize - rLen), rBytes, rLen);
    memcpy(rawBytes + expectedSize + (expectedSize - sLen), sBytes, sLen);
    return raw;
}

+ (nullable NSData *)derSignatureFromRaw:(NSData *)raw error:(NSError **)error {
    if (raw.length % 2 != 0) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-12
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid ECDSA raw signature"}];
        }
        return nil;
    }

    NSUInteger half = raw.length / 2;
    NSData *rData = [raw subdataWithRange:NSMakeRange(0, half)];
    NSData *sData = [raw subdataWithRange:NSMakeRange(half, half)];

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

+ (BOOL)isLowS:(NSData *)rawSignature error:(NSError **)error {
    if (rawSignature.length != 64) return NO;
    
    // Extract s (last 32 bytes)
    const uint8_t *s = (const uint8_t *)rawSignature.bytes + 32;
    
    // P-256 curve order n divided by 2 (n/2). NB: this is the group ORDER n,
    // not the field prime p. A prior version used p/2 here, which misclassified
    // signatures with s in (n/2, p/2] and corrupted low-S normalization.
    // n   = FFFFFFFF 00000000 FFFFFFFF FFFFFFFF BCE6FAAD A7179E84 F3B9CAC2 FC632551
    // n/2 = 7FFFFFFF 80000000 7FFFFFFF FFFFFFFF DE737D56 D38BCF42 79DCE561 7E3192A8
    static const uint8_t p256HalfN[32] = {
        0x7F, 0xFF, 0xFF, 0xFF, 0x80, 0x00, 0x00, 0x00,
        0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xDE, 0x73, 0x7D, 0x56, 0xD3, 0x8B, 0xCF, 0x42,
        0x79, 0xDC, 0xE5, 0x61, 0x7E, 0x31, 0x92, 0xA8
    };
    
    for (int i = 0; i < 32; i++) {
        if (s[i] < p256HalfN[i]) return YES;
        if (s[i] > p256HalfN[i]) return NO;
    }
    
    return YES; // Equal to N/2 is also low-S
}

+ (nullable NSData *)normalizeLowS:(NSData *)rawSignature error:(NSError **)error {
    if (rawSignature.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-13
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signature must be 64 bytes for P-256 low-S normalization"}];
        }
        return nil;
    }

    // If already low-S, return as-is
    if ([self isLowS:rawSignature error:nil]) {
        return rawSignature;
    }

    // P-256 curve order n (the group ORDER, not the field prime p):
    // FFFFFFFF 00000000 FFFFFFFF FFFFFFFF BCE6FAAD A7179E84 F3B9CAC2 FC632551
    static const uint8_t p256N[32] = {
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xBC, 0xE6, 0xFA, 0xAD, 0xA7, 0x17, 0x9E, 0x84,
        0xF3, 0xB9, 0xCA, 0xC2, 0xFC, 0x63, 0x25, 0x51
    };

    const uint8_t *s = (const uint8_t *)rawSignature.bytes + 32;

    // Compute N - s using big-endian subtraction with borrow
    uint8_t normalizedS[32];
    int borrow = 0;
    for (int i = 31; i >= 0; i--) {
        int diff = (int)p256N[i] - (int)s[i] - borrow;
        if (diff < 0) {
            diff += 256;
            borrow = 1;
        } else {
            borrow = 0;
        }
        normalizedS[i] = (uint8_t)diff;
    }

    // Build new signature: r (unchanged) + normalized s
    NSMutableData *result = [rawSignature mutableCopy];
    memcpy(((uint8_t *)result.mutableBytes) + 32, normalizedS, 32);
    return result;
}

+ (nullable NSData *)denormalizeLowS:(NSData *)rawSignature error:(NSError **)error {
    if (rawSignature.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:AuthCryptoErrorDomain
                                         code:-14
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signature must be 64 bytes for P-256 denormalization"}];
        }
        return nil;
    }

    // Only denormalize if currently low-S
    if (![self isLowS:rawSignature error:nil]) {
        // Already high-S, return as-is
        return rawSignature;
    }

    // P-256 curve order n (the group ORDER, not the field prime p):
    // FFFFFFFF 00000000 FFFFFFFF FFFFFFFF BCE6FAAD A7179E84 F3B9CAC2 FC632551
    static const uint8_t p256N[32] = {
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xBC, 0xE6, 0xFA, 0xAD, 0xA7, 0x17, 0x9E, 0x84,
        0xF3, 0xB9, 0xCA, 0xC2, 0xFC, 0x63, 0x25, 0x51
    };

    const uint8_t *s = (const uint8_t *)rawSignature.bytes + 32;

    // Compute N - s using big-endian subtraction with borrow
    uint8_t highS[32];
    int borrow = 0;
    for (int i = 31; i >= 0; i--) {
        int diff = (int)p256N[i] - (int)s[i] - borrow;
        if (diff < 0) {
            diff += 256;
            borrow = 1;
        } else {
            borrow = 0;
        }
        highS[i] = (uint8_t)diff;
    }

    // Build new signature: r (unchanged) + high s
    NSMutableData *result = [rawSignature mutableCopy];
    memcpy(((uint8_t *)result.mutableBytes) + 32, highS, 32);
    return result;
}

@end
