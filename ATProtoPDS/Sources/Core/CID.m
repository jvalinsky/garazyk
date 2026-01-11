#import "Core/CID.h"
#import <CommonCrypto/CommonCrypto.h>

/// Base32 alphabet (RFC 4648) - Lowercase for Multibase 'b'
static const char kBase32Alphabet[] = "abcdefghijklmnopqrstuvwxyz234567";

/// CIDv1 multicodec code (0x01)
static const uint64_t kCIDv1Multicodec = 0x01;

/// Maximum varint size (9 bytes for 64-bit values)
static const NSUInteger kMaxVarintSize = 9;

@implementation CID

#pragma mark - Initialization

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

    // Parse CIDv1 binary format
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;

    // Read version multicodec (should be 0x01 for CIDv1)
    uint64_t versionMulticodec;
    NSUInteger versionSize = [self readVarint:bytes + offset
                                     maxLength:data.length - offset
                                       value:&versionMulticodec];
    if (versionSize == 0 || versionMulticodec != kCIDv1Multicodec) {
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

    NSUInteger i = 0;
    uint64_t shiftBuffer = 0;
    NSUInteger bitsInBuffer = 0;

    while (i < length) {
        if (bitsInBuffer < 8) {
            shiftBuffer = (shiftBuffer << 8) | bytes[i++];
            bitsInBuffer += 8;
        }

        while (bitsInBuffer >= 5) {
            NSUInteger index = (shiftBuffer >> (bitsInBuffer - 5)) & 0x1F;
            [result appendFormat:@"%c", kBase32Alphabet[index]];
            bitsInBuffer -= 5;
        }
    }

    // Pad remaining bits to complete final 5-bit group
    if (bitsInBuffer > 0) {
        shiftBuffer <<= (5 - bitsInBuffer);
        bitsInBuffer = 5;
        NSUInteger index = (shiftBuffer >> 0) & 0x1F;
        [result appendFormat:@"%c", kBase32Alphabet[index]];
    }

    return [result copy];
}

+ (NSData *)base32Decode:(NSString *)string {
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

        const char *ptr = strchr(kBase32Alphabet, (char)c);
        if (!ptr) {
            return nil; // Invalid character
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

#pragma mark - Hashing

+ (CID *)sha256:(NSData *)data {
    NSData *digest = [self sha256Digest:data];
    return [self cidWithMultihash:digest codec:0x55];
}

+ (NSData *)sha256Digest:(NSData *)data {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);

    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}

@end