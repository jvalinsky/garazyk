/*!
 @file CID.m

 @abstract CID (Content Identifier) implementation for content addressing.

 @discussion This file implements CIDv1 per the IPFS specification, used
 throughout ATProto for content-addressable record storage. CIDs combine
 multicodec identification with multihash digests (SHA-256 by default)
 encoded in Base32 (multibase 'b').

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import "Core/CID.h"
#import "Core/Base58.h"
#import "Debug/PDSLogger.h"
#import <CommonCrypto/CommonCrypto.h>

#define b32_debug_log(...) do {} while(0)

/// Base32 alphabet (RFC 4648) - Lowercase for Multibase 'b'
static const char kBase32Alphabet[] = "abcdefghijklmnopqrstuvwxyz234567";
static const char kBase58Alphabet[] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

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
    b32_debug_log(stderr, "cidFromString: %s\n", [string UTF8String]);
    if (!string || string.length == 0) {
        return nil;
    }
    if (string.length > 256) {
        return nil;
    }

    // For now, assume base32 encoding (most common for ATProto)
    if ([string characterAtIndex:0] != 'b') {
        return nil;
    }

    NSString *encodedPart = [string substringFromIndex:1];
    NSData *decodedData = [self base32Decode:encodedPart];
    if (!decodedData || decodedData.length < 2) {
        return nil;
    }

    return [self cidFromBytes:decodedData];
}

+ (nullable instancetype)cidFromBytes:(NSData *)data {
    if (!data || data.length < 2) {
        return nil;
    }
    if (data.length > 256) {
        return nil;
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;

    // Read version multicodec
    uint64_t versionMulticodec;
    NSUInteger versionSize = [self readVarint:bytes + offset
                                     maxLength:data.length - offset
                                       value:&versionMulticodec];
    if (versionSize == 0) {
        return nil;
    }

    // Handle legacy CID format where version byte is 0x00
    // In this case, skip the version byte and parse remaining as CIDv1
    if (versionMulticodec == 0) {
        offset += versionSize;
        // Re-parse assuming the remaining bytes are CIDv1
        if (offset >= data.length) {
            return nil;
        }
        versionSize = [self readVarint:bytes + offset
                              maxLength:data.length - offset
                                value:&versionMulticodec];
        if (versionSize == 0 || versionMulticodec != kCIDv1Multicodec) {
            return nil;
        }
    } else if (versionMulticodec != kCIDv1Multicodec) {
        return nil; // Not a valid CIDv1
    }
    offset += versionSize;

    // Read content type codec
    uint64_t codec;
    NSUInteger codecSize = [self readVarint:bytes + offset
                                    maxLength:data.length - offset
                                      value:&codec];
    if (codecSize == 0 || codec > UINT32_MAX) {
        return nil;
    }
    offset += codecSize;

    // Remaining bytes are the multihash
    if (offset >= data.length) {
        return nil;
    }

    NSUInteger multihashLength = data.length - offset;
    NSData *multihash = [data subdataWithRange:NSMakeRange(offset, multihashLength)];

    return [self cidWithMultihash:multihash codec:(NSUInteger)codec];
}

- (NSString *)stringValue {
    // Create CIDv1 binary format
    NSMutableData *binaryData = [NSMutableData data];
    
    // Write version multicodec (CIDv1 = 0x01)
    [binaryData appendData:[CID encodeVarint:kCIDv1Multicodec]];
    
    // Write content type codec
    [binaryData appendData:[CID encodeVarint:self.codec]];
    
    // Write multihash
    [binaryData appendData:self.multihash];
    
    // Encode as base32 with 'b' prefix
    NSString *base32String = [CID base32Encode:binaryData];
    return [@"b" stringByAppendingString:base32String];
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
    
    // Version multicodec
    [data appendData:[CID encodeVarint:kCIDv1Multicodec]];
    
    // Content codec
    [data appendData:[CID encodeVarint:self.codec]];
    
    // Multihash
    [data appendData:self.multihash];
    
    return [data copy];
}

#pragma mark - NSCopying

- (id)copyWithZone:(nullable NSZone *)zone {
    // CID is immutable
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
        
        // Prevent overflow
        if (shift >= 64) {
            return 0;
        }
    }
    
    return 0; // Incomplete varint
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
    b32_debug_log(stderr, "base32Decode started: %s\n", [string UTF8String]);
    if (!string || string.length == 0) {
        return [NSData data];
    }

    // Remove padding characters (=)
    NSString *cleanString = [string stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];

    NSUInteger length = cleanString.length;
    NSMutableData *result = [NSMutableData dataWithCapacity:((length * 5) + 7) / 8];

    uint64_t buffer = 0;
    NSUInteger bitsLeft = 0;

    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [cleanString characterAtIndex:i];
        if (c >= 'A' && c <= 'Z') c = c - 'A' + 'a'; // Convert to lowercase

        b32_debug_log(stderr, "char: %c\n", (char)c);
        const char *ptr = strchr(kBase32Alphabet, (char)c);
        if (!ptr) {
            PDS_LOG_DEBUG_C(PDSLogComponentCore, @"Invalid character: %c", (char)c);
            return nil; // Invalid character
        }

        uint8_t value = (uint8_t)(ptr - kBase32Alphabet);

        buffer = (buffer << 5) | value;
        bitsLeft += 5;

        while (bitsLeft >= 8) {
            b32_debug_log(stderr, "bitsLeft: %lu\n", (unsigned long)bitsLeft);
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
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}

@end
