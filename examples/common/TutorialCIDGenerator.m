/*!
 @file TutorialCIDGenerator.m

 @abstract CIDv1 generation implementation.

 @discussion Encodes CIDv1 using varint encoding for version, codec, and
 multihash components, then base32-lower encodes the result.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "TutorialCIDGenerator.h"
#import "TutorialBase64URL.h"

#if defined(__APPLE__) && !defined(GNUSTEP)
#import <CommonCrypto/CommonDigest.h>
#else
#import <openssl/sha.h>
#endif

@implementation TutorialCIDGenerator

+ (NSString *)generateCIDForData:(NSData *)data {
    // Step 1: SHA-256 hash
    unsigned char digest[32];
#if defined(__APPLE__) && !defined(GNUSTEP)
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
#else
    SHA256(data.bytes, data.length, digest);
#endif
    NSData *digestData = [NSData dataWithBytes:digest length:32];

    // Step 2: Build CIDv1 binary
    // Format: <varint version><varint codec><multihash>
    // Multihash: <varint hash-code><varint digest-size><digest>
    NSMutableData *cidBytes = [NSMutableData data];

    // Version: 1
    [cidBytes appendData:[self encodeVarint:1]];

    // Codec: 0x71 (dag-cbor, 113 decimal)
    [cidBytes appendData:[self encodeVarint:0x71]];

    // Multihash code: 0x12 (sha2-256)
    [cidBytes appendData:[self encodeVarint:0x12]];

    // Digest size: 32
    [cidBytes appendData:[self encodeVarint:32]];

    // Digest bytes
    [cidBytes appendData:digestData];

    // Step 3: Base32-lower encode with multibase prefix (RFC 4648 §7)
    // Multibase prefix 'b' indicates base32-lower encoding
    return [NSString stringWithFormat:@"b%@", [self base32LowerEncode:cidBytes]];
}

+ (NSString *)generateCIDForJSON:(NSDictionary *)json {
    NSData *data = [NSJSONSerialization dataWithJSONObject:json
                                                   options:NSJSONWritingSortedKeys
                                                     error:nil];
    return [self generateCIDForData:data];
}

#pragma mark - Varint Encoding

+ (NSData *)encodeVarint:(uint64_t)value {
    // LEB128 unsigned varint encoding
    NSMutableData *result = [NSMutableData data];
    uint64_t v = value;
    do {
        uint8_t byte = v & 0x7F;
        v >>= 7;
        if (v > 0) byte |= 0x80;
        [result appendBytes:&byte length:1];
    } while (v > 0);
    return result;
}

#pragma mark - Base32-Lower Encoding

+ (NSString *)base32LowerEncode:(NSData *)data {
    static const char alphabet[] = "abcdefghijklmnopqrstuvwxyz234567";
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;

    NSMutableString *result = [NSMutableString string];
    NSUInteger i = 0;
    uint64_t buffer = 0;
    int bits = 0;

    while (i < length || bits >= 5) {
        if (bits < 5 && i < length) {
            buffer = (buffer << 8) | bytes[i++];
            bits += 8;
        }
        if (bits >= 5) {
            int shift = bits - 5;
            int index = (int)((buffer >> shift) & 0x1F);
            [result appendFormat:@"%c", alphabet[index]];
            bits -= 5;
        }
    }

    // Add padding
    while (result.length % 8 != 0) {
        [result appendString:@"="];
    }

    return result;
}

@end
