// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/CID.h"
#import "Core/Base58.h"
#import "Debug/PDSLogger.h"
#import <CommonCrypto/CommonCrypto.h>

#define b32_debug_log(...) do {} while(0)

/// Base32 alphabet (RFC 4648) - Lowercase for Multibase 'b'
static const char kBase32Alphabet[] = "abcdefghijklmnopqrstuvwxyz234567";

/// CIDv1 multicodec code (0x01)
static const uint64_t kCIDv1Multicodec = 0x01;

/// Maximum varint size (9 bytes for 64-bit values)
static const NSUInteger kMaxVarintSize = 9;

@implementation CID

#pragma mark - Initialization

+ (nullable instancetype)cidWithDigest:(NSData *)digest codec:(NSUInteger)codec {
    if (!digest || digest.length == 0 || codec > UINT32_MAX) {
        return nil;
    }
    
    // Construct full multihash: 0x12 (sha2-256) + 0x20 (length 32) + digest
    NSMutableData *multihash = [NSMutableData dataWithCapacity:2 + digest.length];
    uint8_t header[] = {0x12, (uint8_t)digest.length};
    [multihash appendBytes:header length:2];
    [multihash appendData:digest];
    
    return [self cidWithMultihash:multihash codec:codec];
}

+ (nullable instancetype)cidWithMultihash:(NSData *)multihash codec:(NSUInteger)codec {
    if (!multihash || multihash.length == 0 || codec > UINT32_MAX) {
        return nil;
    }
    
    CID *cid = [[CID alloc] init];
    if (cid) {
        cid->_version = 1;
        cid->_codec = codec;
        cid->_multihash = [multihash copy];
    }
    return cid;
}

+ (nullable instancetype)cidFromString:(NSString *)string {
    if (!string || string.length == 0) {
        return nil;
    }
    if (string.length > 256) {
        return nil;
    }

    unichar multibasePrefix = [string characterAtIndex:0];
    NSString *encodedPart = [string substringFromIndex:1];
    NSData *decodedData = nil;

    switch (multibasePrefix) {
        case 'b': // base32
            decodedData = [self base32Decode:encodedPart];
            break;
        case 'z': // base58btc
            decodedData = [self base58btcDecode:encodedPart];
            break;
        case 'f': // base16 (hex)
            decodedData = [self hexDecode:encodedPart];
            break;
        case 'm': // base64
            decodedData = [self base64Decode:encodedPart];
            break;
        case 'u': // base64url
            decodedData = [self base64urlDecode:encodedPart];
            break;
        case '7': // base8 (Contrived example in fixtures)
            decodedData = [self base8Decode:encodedPart];
            break;
        default:
            return nil;
    }

    if (!decodedData) {
        return nil;
    }

    return [self cidFromBytes:decodedData];
}

+ (nullable NSData *)hexDecode:(NSString *)hex {
    if (hex.length % 2 != 0) return nil;
    NSMutableData *data = [NSMutableData dataWithCapacity:hex.length / 2];
    for (NSUInteger i = 0; i < hex.length; i += 2) {
        unsigned int value;
        NSScanner *scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]];
        if (![scanner scanHexInt:&value]) return nil;
        uint8_t byte = (uint8_t)value;
        [data appendBytes:&byte length:1];
    }
    return data;
}

+ (nullable NSData *)base64urlDecode:(NSString *)string {
    if (!string) return nil;
    NSMutableString *base64 = [string mutableCopy];
    [base64 replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, base64.length)];
    while (base64.length % 4 != 0) {
        [base64 appendString:@"="];
    }
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

+ (nullable NSData *)base64Decode:(NSString *)string {
    if (!string) return nil;
    NSData *data = [[NSData alloc] initWithBase64EncodedString:string options:0];
    if (data) return data;
    NSMutableString *base64 = [string mutableCopy];
    while (base64.length % 4 != 0) {
        [base64 appendString:@"="];
    }
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

+ (nullable instancetype)cidFromBytes:(NSData *)data {
    if (!data || data.length < 2 || data.length > 256) {
        return nil;
    }

    NSUInteger consumed = 0;
    CID *cid = [self cidFromBuffer:data.bytes length:data.length consumed:&consumed];
    if (!cid || consumed != data.length) {
        return nil;
    }
    return cid;
}

+ (nullable instancetype)cidFromBuffer:(const uint8_t *)bytes
                                length:(NSUInteger)length
                              consumed:(nullable NSUInteger *)consumed {
    if (!bytes || length < 2) {
        return nil;
    }

    // CIDv0 fast-path: sha2-256 (0x12) + length 32 (0x20) + 32-byte digest.
    if (length >= 34 && bytes[0] == 0x12 && bytes[1] == 0x20) {
        CID *cid = [[CID alloc] init];
        if (cid) {
            cid->_version = 0;
            cid->_codec = 0x70; // dag-pb (standard for CIDv0)
            cid->_multihash = [NSData dataWithBytes:bytes length:34];
        }
        if (consumed) *consumed = 34;
        return cid;
    }

    NSUInteger offset = 0;

    uint64_t versionMulticodec = 0;
    NSUInteger versionSize = [self readVarint:bytes + offset
                                    maxLength:length - offset
                                        value:&versionMulticodec];
    if (versionSize == 0) {
        return nil;
    }
    offset += versionSize;

    // Tolerate legacy encoding where the first varint is 0 and a second
    // varint carries the actual CIDv1 multicodec (0x01).
    if (versionMulticodec == 0) {
        if (offset >= length) {
            return nil;
        }
        NSUInteger innerSize = [self readVarint:bytes + offset
                                      maxLength:length - offset
                                          value:&versionMulticodec];
        if (innerSize == 0) {
            return nil;
        }
        offset += innerSize;
    }

    if (versionMulticodec != kCIDv1Multicodec) {
        return nil;
    }

    uint64_t codec = 0;
    NSUInteger codecSize = [self readVarint:bytes + offset
                                  maxLength:length - offset
                                      value:&codec];
    if (codecSize == 0 || codec > UINT32_MAX) {
        return nil;
    }
    offset += codecSize;

    // Remember where the multihash (code + length + digest) begins so we can
    // slice it out once the digest length is known.
    NSUInteger multihashStart = offset;

    uint64_t mhCode = 0;
    NSUInteger mhCodeSize = [self readVarint:bytes + offset
                                   maxLength:length - offset
                                       value:&mhCode];
    if (mhCodeSize == 0) {
        return nil;
    }
    offset += mhCodeSize;

    uint64_t mhLen = 0;
    NSUInteger mhLenSize = [self readVarint:bytes + offset
                                  maxLength:length - offset
                                      value:&mhLen];
    if (mhLenSize == 0) {
        return nil;
    }
    offset += mhLenSize;

    // ATProto repositories only accept sha2-256 multihashes.
    if (mhCode != 0x12 || mhLen != 32) {
        return nil;
    }

    // Overflow-safe bounds check. 128 is a defense-in-depth cap — real
    // multihashes never exceed 64 bytes and we reject hostile oversized values.
    if (mhLen > 128 || mhLen > (uint64_t)(length - offset)) {
        return nil;
    }

    NSUInteger digestLen = (NSUInteger)mhLen;
    NSUInteger multihashLen = (offset - multihashStart) + digestLen;
    NSData *multihash = [NSData dataWithBytes:(bytes + multihashStart) length:multihashLen];

    CID *cid = [self cidWithMultihash:multihash codec:(NSUInteger)codec];
    if (!cid) {
        return nil;
    }

    if (consumed) *consumed = offset + digestLen;
    return cid;
}

- (NSString *)stringValue {
    NSMutableData *binaryData = [NSMutableData data];
    [binaryData appendData:[CID encodeVarint:kCIDv1Multicodec]];
    [binaryData appendData:[CID encodeVarint:self.codec]];
    [binaryData appendData:self.multihash];
    NSString *base32String = [CID base32Encode:binaryData];
    return [@"b" stringByAppendingString:base32String];
}

- (NSString *)description {
    return self.stringValue ?: @"<CID: nil>";
}

#pragma mark - Comparison and Equality

- (BOOL)isEqualToCID:(CID *)other {
    if (!other) return NO;
    return self.version == other.version &&
           self.codec == other.codec &&
           [self.multihash isEqualToData:other.multihash];
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CID class]]) return NO;
    return [self isEqualToCID:object];
}

- (NSUInteger)hash {
    return self.multihash.hash ^ self.codec;
}

#pragma mark - Data Access

- (NSData *)bytes {
    NSMutableData *data = [NSMutableData data];
    [data appendData:[CID encodeVarint:kCIDv1Multicodec]];
    [data appendData:[CID encodeVarint:self.codec]];
    [data appendData:self.multihash];
    return [data copy];
}

#pragma mark - Varint Encoding/Decoding

+ (NSData *)encodeVarint:(uint64_t)value {
    NSMutableData *data = [NSMutableData dataWithCapacity:kMaxVarintSize];
    uint64_t v = value;
    do {
        uint8_t byte = v & 0x7F;
        v >>= 7;
        if (v != 0) {
            byte |= 0x80;
        }
        [data appendBytes:&byte length:1];
    } while (v != 0);
    return [data copy];
}

+ (NSUInteger)readVarint:(const uint8_t *)bytes 
               maxLength:(NSUInteger)maxLength 
                   value:(uint64_t *)value {
    if (maxLength == 0) {
        return 0;
    }
    uint64_t result = 0;
    NSUInteger shift = 0;
    NSUInteger offset = 0;
    while (offset < maxLength) {
        uint8_t byte = bytes[offset++];
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        shift += 7;
        if ((byte & 0x80) == 0) {
            *value = result;
            return offset;
        }
        if (shift >= 64) {
            return 0;
        }
    }
    return 0;
}

#pragma mark - Base32 Encoding/Decoding

+ (NSString *)base32Encode:(NSData *)data {
    if (!data || data.length == 0) {
        return @"";
    }
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSMutableString *result = [NSMutableString stringWithCapacity:((length * 8) + 4) / 5];
    uint64_t buffer = 0;
    int bitsLeft = 0;
    for (NSUInteger i = 0; i < length; i++) {
        buffer = (buffer << 8) | bytes[i];
        bitsLeft += 8;
        while (bitsLeft >= 5) {
            int shift = bitsLeft - 5;
            [result appendFormat:@"%c", kBase32Alphabet[(buffer >> shift) & 0x1F]];
            bitsLeft -= 5;
        }
        buffer &= ((1ULL << bitsLeft) - 1);
    }
    if (bitsLeft > 0) {
        [result appendFormat:@"%c", kBase32Alphabet[(buffer << (5 - bitsLeft)) & 0x1F]];
    }
    return [result copy];
}

+ (NSData *)base32Decode:(NSString *)string {
    if (!string || string.length == 0) {
        return [NSData data];
    }
    NSString *cleanString = [string stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
    NSUInteger length = cleanString.length;
    NSMutableData *result = [NSMutableData dataWithCapacity:((length * 5) + 7) / 8];
    uint64_t buffer = 0;
    NSUInteger bitsLeft = 0;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [cleanString characterAtIndex:i];
        if (c >= 'A' && c <= 'Z') c = c - 'A' + 'a';
        const char *ptr = strchr(kBase32Alphabet, (char)c);
        if (!ptr) {
            PDS_LOG_DEBUG_C(PDSLogComponentCore, @"Invalid character: %c", (char)c);
            return nil;
        }
        uint8_t value = (uint8_t)(ptr - kBase32Alphabet);
        buffer = (buffer << 5) | value;
        bitsLeft += 5;
        while (bitsLeft >= 8) {
            NSUInteger byteShift = bitsLeft - 8;
            uint8_t byte = (buffer >> byteShift) & 0xFF;
            [result appendBytes:&byte length:1];
            uint64_t mask = (1ULL << byteShift) - 1;
            buffer &= mask;
            bitsLeft = byteShift;
        }
    }
    return [result copy];
}

+ (nullable NSData *)base58btcDecode:(NSString *)string {
    return [Base58 decode:string];
}

+ (NSString *)base58btcEncode:(NSData *)data {
    return [Base58 encode:data];
}

+ (nullable NSData *)base8Decode:(NSString *)string {
    NSUInteger length = string.length;
    NSMutableData *result = [NSMutableData dataWithCapacity:(length * 3 + 7) / 8];
    uint64_t buffer = 0;
    int bitsLeft = 0;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [string characterAtIndex:i];
        if (c < '0' || c > '7') return nil;
        uint8_t value = c - '0';
        buffer = (buffer << 3) | value;
        bitsLeft += 3;
        while (bitsLeft >= 8) {
            uint8_t byte = (buffer >> (bitsLeft - 8)) & 0xFF;
            [result appendBytes:&byte length:1];
            bitsLeft -= 8;
        }
    }
    return result;
}

#pragma mark - Hashing

+ (CID *)sha256:(NSData *)data {
    NSData *digest = [self sha256Digest:data];
    return [self cidWithDigest:digest codec:0x55];
}

+ (NSData *)sha256Digest:(NSData *)data {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}

+ (NSData *)rawSha256:(NSData *)data {
    return [self sha256Digest:data];
}

#pragma mark - NSCopying

- (id)copyWithZone:(nullable NSZone *)zone {
    return self;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.version forKey:@"version"];
    [coder encodeInteger:self.codec forKey:@"codec"];
    [coder encodeObject:self.multihash forKey:@"multihash"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSUInteger version = [coder decodeIntegerForKey:@"version"];
    NSUInteger codec = [coder decodeIntegerForKey:@"codec"];
    NSData *multihash = [coder decodeObjectOfClass:[NSData class] forKey:@"multihash"];
    
    if (!multihash) {
        return nil;
    }
    
    self = [CID cidWithMultihash:multihash codec:codec];
    if (self) {
        // Version is implicit in v1 format
    }
    return self;
}

@end
