// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"
#import "Debug/GZLogger.h"
#import <CommonCrypto/CommonDigest.h>
#import <math.h>
#import <string.h>

NSString * const ATProtoDagCBORErrorDomain = @"com.atproto.dagcbor";

static const NSUInteger kMaxDecodeDepth = 64;

@implementation ATProtoDRISLFloat

+ (instancetype)floatWithValue:(double)value {
    return [[self alloc] initWithValue:value];
}

- (instancetype)initWithValue:(double)value {
    self = [super init];
    if (self) {
        _value = value;
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    return self;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[ATProtoDRISLFloat class]]) return NO;
    // Bit-comparison, not ==, so that -0.0 and 0.0 stay distinguishable: they
    // encode to different bytes and therefore to different CIDs.
    double other = ((ATProtoDRISLFloat *)object).value;
    uint64_t a = 0, b = 0;
    memcpy(&a, &_value, sizeof(a));
    memcpy(&b, &other, sizeof(b));
    return a == b;
}

- (NSUInteger)hash {
    uint64_t bits = 0;
    memcpy(&bits, &_value, sizeof(bits));
    return (NSUInteger)(bits ^ (bits >> 32));
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%g", _value];
}

@end

// Compare two CBOR-encoded map keys per DAG-CBOR canonical sort order:
// shorter encoded length sorts first; for equal lengths, byte-wise memcmp.
// Mirrors the comparison used by the encoder in _canonicallySortedKeys: so
// the round-trip is identity-preserving for canonical encodings.
static NSInteger _dagCBORCompareEncodedKeys(const uint8_t *a, NSUInteger aLen,
                                            const uint8_t *b, NSUInteger bLen) {
    if (aLen < bLen) return -1;
    if (aLen > bLen) return 1;
    int cmp = memcmp(a, b, aLen);
    if (cmp < 0) return -1;
    if (cmp > 0) return 1;
    return 0;
}

@implementation ATProtoDagCBOR

#pragma mark - Public API

+ (nullable NSData *)encodeObject:(id)object error:(NSError **)error {
    return [self encodeObject:object profile:ATProtoDRISLProfileATProto error:error];
}

+ (nullable NSData *)encodeObject:(id)object
                          profile:(ATProtoDRISLProfile)profile
                            error:(NSError **)error {
    NSMutableData *result = [NSMutableData data];
    if (![self _encodeValue:object profile:profile toData:result error:error]) {
        return nil;
    }
    return result;
}

+ (nullable id)decodeData:(NSData *)data error:(NSError **)error {
    return [self decodeData:data profile:ATProtoDRISLProfileATProto error:error];
}

+ (nullable id)decodeOneFromData:(NSData *)data
                         profile:(ATProtoDRISLProfile)profile
                 consumedLength:(NSUInteger *)consumedLength
                           error:(NSError **)error {
    if (consumedLength) {
        *consumedLength = 0;
    }
    if (data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty CBOR data"}];
        }
        return nil;
    }

    NSUInteger index = 0;
    id result = [self _decodeFromBytes:data.bytes
                                length:data.length
                                 index:&index
                                 depth:0
                               profile:profile
                                 error:error];
    if (result && consumedLength) {
        *consumedLength = index;
    }
    return result;
}

+ (nullable id)decodeData:(NSData *)data
                  profile:(ATProtoDRISLProfile)profile
                    error:(NSError **)error {
    if (data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty CBOR data"}];
        }
        return nil;
    }

    NSUInteger index = 0;
    id result = [self _decodeFromBytes:data.bytes
                                length:data.length
                                 index:&index
                                 depth:0
                               profile:profile
                                 error:error];
    if (result && index != data.length) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Trailing data after complete CBOR item"}];
        }
        return nil;
    }
    return result;
}

+ (nullable NSData *)encodeJSONObject:(id)jsonObject error:(NSError **)error {
    id converted = [self _convertJSONToCBOR:jsonObject error:error];
    if (!converted) {
        return nil;
    }
    return [self encodeObject:converted error:error];
}

+ (nullable id)decodeDataAsJSON:(NSData *)data error:(NSError **)error {
    id decoded = [self decodeData:data error:error];
    if (!decoded) {
        return nil;
    }
    return [self _convertCBORToJSON:decoded];
}

#pragma mark - JSON Conversion

+ (nullable id)_convertJSONToCBOR:(id)json error:(NSError **)error {
    if ([json isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)json;
        
        // Check for $link wrapper
        if (dict.count == 1 && dict[@"$link"]) {
            NSString *cidString = dict[@"$link"];
            if (![cidString isKindOfClass:[NSString class]]) {
                if (error) {
                    *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                                 code:ATProtoDagCBORErrorCodeInvalidType
                                             userInfo:@{NSLocalizedDescriptionKey: @"$link value must be a string"}];
                }
                return nil;
            }
            CID *cid = [CID cidFromString:cidString];
            if (!cid) {
                if (error) {
                    *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                                 code:ATProtoDagCBORErrorCodeInvalidCIDLink
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid CID: %@", cidString]}];
                }
                return nil;
            }
            return cid;
        }
        
        // Check for $bytes wrapper
        if (dict.count == 1 && dict[@"$bytes"]) {
            NSString *base64String = dict[@"$bytes"];
            if (![base64String isKindOfClass:[NSString class]]) {
                if (error) {
                    *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                                 code:ATProtoDagCBORErrorCodeInvalidType
                                             userInfo:@{NSLocalizedDescriptionKey: @"$bytes value must be a string"}];
                }
                return nil;
            }
            NSData *bytes = [[NSData alloc] initWithBase64EncodedString:base64String options:0];
            if (!bytes) {
                if (error) {
                    *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                                 code:ATProtoDagCBORErrorCodeInvalidType
                                             userInfo:@{NSLocalizedDescriptionKey: @"Invalid base64 in $bytes"}];
                }
                return nil;
            }
            return bytes;
        }
        
        // Recursively convert dictionary values
        NSMutableDictionary *converted = [NSMutableDictionary dictionaryWithCapacity:dict.count];
        for (id key in dict) {
            id value = [self _convertJSONToCBOR:dict[key] error:error];
            if (!value && error && *error) {
                return nil;
            }
            converted[key] = value ?: [NSNull null];
        }
        return converted;
        
    } else if ([json isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)json;
        NSMutableArray *converted = [NSMutableArray arrayWithCapacity:array.count];
        for (id item in array) {
            id value = [self _convertJSONToCBOR:item error:error];
            if (!value && error && *error) {
                return nil;
            }
            [converted addObject:value ?: [NSNull null]];
        }
        return converted;
    }
    
    // Primitives pass through
    return json;
}

+ (id)_convertCBORToJSON:(id)cbor {
    if ([cbor isKindOfClass:[CID class]]) {
        CID *cid = (CID *)cbor;
        return @{@"$link": cid.stringValue};
    } else if ([cbor isKindOfClass:[ATProtoDRISLFloat class]]) {
        // JSON has no way to preserve the float/integer distinction, so this
        // is lossy in one direction: re-encoding the result needs the caller
        // to re-wrap. Only reachable under ATProtoDRISLProfileDRISL.
        return @(((ATProtoDRISLFloat *)cbor).value);
    } else if ([cbor isKindOfClass:[NSData class]]) {
        NSData *data = (NSData *)cbor;
        return @{@"$bytes": [data base64EncodedStringWithOptions:0]};
    } else if ([cbor isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)cbor;
        NSMutableDictionary *converted = [NSMutableDictionary dictionaryWithCapacity:dict.count];
        for (id key in dict) {
            converted[key] = [self _convertCBORToJSON:dict[key]];
        }
        return converted;
    } else if ([cbor isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)cbor;
        NSMutableArray *converted = [NSMutableArray arrayWithCapacity:array.count];
        for (id item in array) {
            [converted addObject:[self _convertCBORToJSON:item]];
        }
        return converted;
    }
    
    return cbor;
}

#pragma mark - Encoding

+ (BOOL)_encodeValue:(id)value
             profile:(ATProtoDRISLProfile)profile
              toData:(NSMutableData *)data
               error:(NSError **)error {
    if ([value isKindOfClass:[NSNull class]]) {
        uint8_t byte = 0xF6;
        [data appendBytes:&byte length:1];
        return YES;

    } else if ([value isKindOfClass:[NSNumber class]]) {
        return [self _encodeNumber:(NSNumber *)value profile:profile toData:data error:error];

    } else if ([value isKindOfClass:[NSString class]]) {
        return [self _encodeString:(NSString *)value toData:data error:error];

    } else if ([value isKindOfClass:[NSData class]]) {
        return [self _encodeByteString:(NSData *)value toData:data error:error];

    } else if ([value isKindOfClass:[NSArray class]]) {
        return [self _encodeArray:(NSArray *)value profile:profile toData:data error:error];

    } else if ([value isKindOfClass:[NSDictionary class]]) {
        return [self _encodeMap:(NSDictionary *)value profile:profile toData:data error:error];

    } else if ([value isKindOfClass:[CID class]]) {
        return [self _encodeCIDLink:(CID *)value toData:data error:error];

    } else if ([value isKindOfClass:[ATProtoDRISLFloat class]]) {
        return [self _encodeDRISLFloat:(ATProtoDRISLFloat *)value profile:profile toData:data error:error];

    } else {
        GZ_LOG_ERROR(@"ATProtoDagCBOR: Unsupported type: %@", NSStringFromClass([value class]));
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeInvalidType
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported type: %@", NSStringFromClass([value class])]}];
        }
        return NO;
    }
}

+ (BOOL)_encodeDRISLFloat:(ATProtoDRISLFloat *)number
                  profile:(ATProtoDRISLProfile)profile
                   toData:(NSMutableData *)data
                    error:(NSError **)error {
    if (profile != ATProtoDRISLProfileDRISL) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeFloatsNotAllowed
                                     userInfo:@{NSLocalizedDescriptionKey: @"ATProto records forbid floats; encode under ATProtoDRISLProfileDRISL to emit one"}];
        }
        return NO;
    }

    double value = number.value;
    if (isnan(value) || isinf(value)) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeFloatsNotAllowed
                                     userInfo:@{NSLocalizedDescriptionKey: @"DRISL forbids NaN, Infinity and -Infinity"}];
        }
        return NO;
    }

    // Major type 7, additional info 27: always the 64-bit form. DRISL forbids
    // the shorter float widths, so there is no minimal-encoding reduction to
    // apply here the way there is for integers.
    uint64_t bits = 0;
    memcpy(&bits, &value, sizeof(bits));
    uint8_t bytes[9] = { 0xFB };
    for (int i = 0; i < 8; i++) {
        bytes[1 + i] = (uint8_t)((bits >> ((7 - i) * 8)) & 0xFF);
    }
    [data appendBytes:bytes length:9];
    return YES;
}

+ (BOOL)_encodeNumber:(NSNumber *)number
              profile:(ATProtoDRISLProfile)profile
               toData:(NSMutableData *)data
                error:(NSError **)error {
    // Check for boolean
    if (CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID()) {
        uint8_t byte = number.boolValue ? 0xF5 : 0xF4;
        [data appendBytes:&byte length:1];
        return YES;
    }
    
    // Check if the value is actually an integer (even if stored as float type)
    // On GNUstep, boxed expressions like @(integerValue) may report as float types
    double doubleValue = number.doubleValue;
    int64_t intValue = number.longLongValue;
    
    // Check if the value is a whole number that fits in int64
    if (doubleValue == (double)intValue && 
        doubleValue >= (double)INT64_MIN && 
        doubleValue <= (double)INT64_MAX) {
        // It's an integer value, encode as integer
        if (intValue < 0) {
            // Negative integer (major type 1)
            uint64_t val = (uint64_t)(-intValue - 1);
            return [self _encodeInteger:val majorType:1 toData:data];
        } else {
            // Unsigned integer (major type 0)
            return [self _encodeInteger:(uint64_t)intValue majorType:0 toData:data];
        }
    }
    
    // A non-integral NSNumber. Even under ATProtoDRISLProfileDRISL this is an
    // error rather than an implicit float: NSNumber cannot distinguish 0.0 from
    // 0, and GNUstep reports some boxed integers as floating types, so treating
    // NSNumber as a float source would silently change how integers encode.
    // Callers that mean a float say so with ATProtoDRISLFloat.
    if (error) {
        NSString *message = (profile == ATProtoDRISLProfileDRISL)
            ? @"Non-integral NSNumber; wrap the value in ATProtoDRISLFloat to encode it as a DRISL float"
            : @"ATProto records forbid IEEE 754 floats";
        *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                     code:ATProtoDagCBORErrorCodeFloatsNotAllowed
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

+ (BOOL)_encodeInteger:(uint64_t)value majorType:(uint8_t)majorType toData:(NSMutableData *)data {
    uint8_t initialByte = (majorType << 5);
    
    if (value < 24) {
        initialByte |= (uint8_t)value;
        [data appendBytes:&initialByte length:1];
    } else if (value < 256) {
        initialByte |= 24;
        uint8_t bytes[2] = { initialByte, (uint8_t)value };
        [data appendBytes:bytes length:2];
    } else if (value < 65536) {
        initialByte |= 25;
        uint8_t bytes[3] = { initialByte, (value >> 8) & 0xFF, value & 0xFF };
        [data appendBytes:bytes length:3];
    } else if (value < 4294967296ULL) {
        initialByte |= 26;
        uint8_t bytes[5] = { initialByte, (value >> 24) & 0xFF, (value >> 16) & 0xFF, 
                             (value >> 8) & 0xFF, value & 0xFF };
        [data appendBytes:bytes length:5];
    } else {
        initialByte |= 27;
        uint8_t bytes[9] = { initialByte };
        for (int i = 7; i >= 0; i--) {
            bytes[8 - i] = (value >> (i * 8)) & 0xFF;
        }
        [data appendBytes:bytes length:9];
    }
    
    return YES;
}

+ (BOOL)_encodeString:(NSString *)string toData:(NSMutableData *)data error:(NSError **)error {
    NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeEncodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode string as UTF-8"}];
        }
        return NO;
    }
    
    NSUInteger length = utf8.length;
    uint8_t initialByte = 0x60; // Major type 3
    
    if (length < 24) {
        initialByte |= (uint8_t)length;
        [data appendBytes:&initialByte length:1];
    } else if (length < 256) {
        initialByte |= 24;
        uint8_t bytes[2] = { initialByte, (uint8_t)length };
        [data appendBytes:bytes length:2];
    } else if (length < 65536) {
        initialByte |= 25;
        uint8_t bytes[3] = { initialByte, (length >> 8) & 0xFF, length & 0xFF };
        [data appendBytes:bytes length:3];
    } else {
        initialByte |= 26;
        uint8_t bytes[5] = { initialByte, (length >> 24) & 0xFF, (length >> 16) & 0xFF,
                             (length >> 8) & 0xFF, length & 0xFF };
        [data appendBytes:bytes length:5];
    }
    
    [data appendData:utf8];
    return YES;
}

+ (BOOL)_encodeByteString:(NSData *)bytes toData:(NSMutableData *)data error:(NSError **)error {
    NSUInteger length = bytes.length;
    uint8_t initialByte = 0x40; // Major type 2
    
    if (length < 24) {
        initialByte |= (uint8_t)length;
        [data appendBytes:&initialByte length:1];
    } else if (length < 256) {
        initialByte |= 24;
        uint8_t header[2] = { initialByte, (uint8_t)length };
        [data appendBytes:header length:2];
    } else if (length < 65536) {
        initialByte |= 25;
        uint8_t header[3] = { initialByte, (length >> 8) & 0xFF, length & 0xFF };
        [data appendBytes:header length:3];
    } else {
        initialByte |= 26;
        uint8_t header[5] = { initialByte, (length >> 24) & 0xFF, (length >> 16) & 0xFF,
                              (length >> 8) & 0xFF, length & 0xFF };
        [data appendBytes:header length:5];
    }
    
    [data appendData:bytes];
    return YES;
}

+ (BOOL)_encodeArray:(NSArray *)array
             profile:(ATProtoDRISLProfile)profile
              toData:(NSMutableData *)data
               error:(NSError **)error {
    NSUInteger count = array.count;
    uint8_t initialByte = 0x80; // Major type 4
    
    if (count < 16) {
        initialByte |= (uint8_t)count;
        [data appendBytes:&initialByte length:1];
    } else if (count < 256) {
        initialByte |= 24;
        uint8_t bytes[2] = { initialByte, (uint8_t)count };
        [data appendBytes:bytes length:2];
    } else if (count < 65536) {
        initialByte |= 25;
        uint8_t bytes[3] = { initialByte, (count >> 8) & 0xFF, count & 0xFF };
        [data appendBytes:bytes length:3];
    } else {
        initialByte |= 26;
        uint8_t bytes[5] = { initialByte, (count >> 24) & 0xFF, (count >> 16) & 0xFF,
                             (count >> 8) & 0xFF, count & 0xFF };
        [data appendBytes:bytes length:5];
    }
    
    for (id item in array) {
        if (![self _encodeValue:item profile:profile toData:data error:error]) {
            return NO;
        }
    }

    return YES;
}

+ (BOOL)_encodeMap:(NSDictionary *)dict
           profile:(ATProtoDRISLProfile)profile
            toData:(NSMutableData *)data
             error:(NSError **)error {
    NSUInteger count = dict.count;
    uint8_t initialByte = 0xA0; // Major type 5
    
    if (count < 16) {
        initialByte |= (uint8_t)count;
        [data appendBytes:&initialByte length:1];
    } else if (count < 256) {
        initialByte |= 24;
        uint8_t bytes[2] = { initialByte, (uint8_t)count };
        [data appendBytes:bytes length:2];
    } else if (count < 65536) {
        initialByte |= 25;
        uint8_t bytes[3] = { initialByte, (count >> 8) & 0xFF, count & 0xFF };
        [data appendBytes:bytes length:3];
    } else {
        initialByte |= 26;
        uint8_t bytes[5] = { initialByte, (count >> 24) & 0xFF, (count >> 16) & 0xFF,
                             (count >> 8) & 0xFF, count & 0xFF };
        [data appendBytes:bytes length:5];
    }
    
    // Sort keys by their encoded representation (canonical ordering)
    NSArray *sortedKeys = [self _canonicallySortedKeys:dict.allKeys error:error];
    if (!sortedKeys) {
        return NO;
    }
    
    for (id key in sortedKeys) {
        if (![self _encodeValue:key profile:profile toData:data error:error]) {
            return NO;
        }
        if (![self _encodeValue:dict[key] profile:profile toData:data error:error]) {
            return NO;
        }
    }

    return YES;
}

+ (nullable NSArray *)_canonicallySortedKeys:(NSArray *)keys error:(NSError **)error {
    // Encode each key and pair it with the original key. DRISL permits only
    // text-string keys, so anything else is rejected before it can be encoded
    // — an integer key would otherwise sort and serialize happily and produce
    // a document no conforming decoder will read back.
    NSMutableArray *encodedPairs = [NSMutableArray arrayWithCapacity:keys.count];
    for (id key in keys) {
        if (![key isKindOfClass:[NSString class]]) {
            if (error) {
                *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                             code:ATProtoDagCBORErrorCodeNonStringMapKey
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"DRISL map keys must be strings, got %@", NSStringFromClass([key class])]}];
            }
            return nil;
        }
        NSData *encoded = [self encodeObject:key error:error];
        if (!encoded) {
            return nil;
        }
        [encodedPairs addObject:@[encoded, key]];
    }
    
    // Sort by encoded bytes (length-first, then lexicographic)
    [encodedPairs sortUsingComparator:^NSComparisonResult(NSArray *pair1, NSArray *pair2) {
        NSData *data1 = pair1[0];
        NSData *data2 = pair2[0];
        
        // Compare lengths first
        if (data1.length < data2.length) return NSOrderedAscending;
        if (data1.length > data2.length) return NSOrderedDescending;
        
        // Same length: byte-wise comparison
        int cmp = memcmp(data1.bytes, data2.bytes, data1.length);
        if (cmp < 0) return NSOrderedAscending;
        if (cmp > 0) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    // Extract original keys in sorted order
    NSMutableArray *sorted = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSArray *pair in encodedPairs) {
        [sorted addObject:pair[1]];
    }
    
    return sorted;
}

+ (BOOL)_encodeCIDLink:(CID *)cid toData:(NSMutableData *)data error:(NSError **)error {
    // CID-link: tag 42 with byte string containing 0x00 || CID bytes
    NSMutableData *cidBytes = [NSMutableData dataWithCapacity:1 + cid.bytes.length];
    uint8_t marker = 0x00;
    [cidBytes appendBytes:&marker length:1];
    [cidBytes appendData:cid.bytes];
    
    // Encode tag 42
    uint8_t tagByte = 0xD8; // Major type 6, additional info 24
    uint8_t tagValue = 42;
    [data appendBytes:&tagByte length:1];
    [data appendBytes:&tagValue length:1];
    
    // Encode the byte string
    return [self _encodeByteString:cidBytes toData:data error:error];
}

#pragma mark - Decoding

+ (nullable id)_decodeFromBytes:(const uint8_t *)bytes
                         length:(NSUInteger)length
                          index:(NSUInteger *)index
                          depth:(NSUInteger)depth
                        profile:(ATProtoDRISLProfile)profile
                          error:(NSError **)error {
    if (depth > kMaxDecodeDepth) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"CBOR nesting depth exceeded"}];
        }
        return nil;
    }
    
    if (*index >= length) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unexpected end of CBOR data"}];
        }
        return nil;
    }
    
    uint8_t initialByte = bytes[*index];
    (*index)++;
    
    uint8_t majorType = (initialByte >> 5) & 0x7;
    uint8_t additionalInfo = initialByte & 0x1F;
    
    switch (majorType) {
        case 0: // Unsigned integer
            return [self _decodeUnsignedInteger:additionalInfo bytes:bytes length:length index:index error:error];
            
        case 1: // Negative integer
            return [self _decodeNegativeInteger:additionalInfo bytes:bytes length:length index:index error:error];
            
        case 2: // Byte string
            return [self _decodeByteString:additionalInfo bytes:bytes length:length index:index error:error];
            
        case 3: // Text string
            return [self _decodeTextString:additionalInfo bytes:bytes length:length index:index error:error];
            
        case 4: // Array
            return [self _decodeArray:additionalInfo bytes:bytes length:length index:index depth:depth profile:profile error:error];

        case 5: // Map
            return [self _decodeMap:additionalInfo bytes:bytes length:length index:index depth:depth profile:profile error:error];

        case 6: // Tag
            return [self _decodeTag:additionalInfo bytes:bytes length:length index:index depth:depth profile:profile error:error];

        case 7: // Special/float
            return [self _decodeSpecial:additionalInfo bytes:bytes length:length index:index profile:profile error:error];

        default:
            if (error) {
                *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                             code:ATProtoDagCBORErrorCodeDecodingFailed
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown major type: %u", majorType]}];
            }
            return nil;
    }
}

+ (void)_setDecodingError:(NSError **)error message:(NSString *)message {
    if (error) {
        *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                     code:ATProtoDagCBORErrorCodeDecodingFailed
                                 userInfo:@{NSLocalizedDescriptionKey: message ?: @"CBOR decoding failed"}];
    }
}

+ (nullable NSNumber *)_decodeLength:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index error:(NSError **)error {
    uint64_t value = 0;
    
    if (additionalInfo < 24) {
        value = additionalInfo;
    } else if (additionalInfo == 24) {
        if (*index >= length) {
            [self _setDecodingError:error message:@"Truncated CBOR length"];
            return nil;
        }
        value = bytes[*index];
        (*index)++;
    } else if (additionalInfo == 25) {
        if (*index + 1 >= length) {
            [self _setDecodingError:error message:@"Truncated CBOR length"];
            return nil;
        }
        value = ((uint64_t)bytes[*index] << 8) | bytes[*index + 1];
        *index += 2;
    } else if (additionalInfo == 26) {
        if (*index + 3 >= length) {
            [self _setDecodingError:error message:@"Truncated CBOR length"];
            return nil;
        }
        value = ((uint64_t)bytes[*index] << 24) | ((uint64_t)bytes[*index + 1] << 16) |
                ((uint64_t)bytes[*index + 2] << 8) | bytes[*index + 3];
        *index += 4;
    } else if (additionalInfo == 27) {
        if (*index + 7 >= length) {
            [self _setDecodingError:error message:@"Truncated CBOR length"];
            return nil;
        }
        value = 0;
        for (int i = 0; i < 8; i++) {
            value = (value << 8) | bytes[*index + i];
        }
        *index += 8;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid additional info"}];
        }
        return nil;
    }

    // Reject non-minimal length encodings. DAG-CBOR canonical form requires
    // that the encoded length fits within the smallest natural encoding for
    // the parsed `additionalInfo`; otherwise one logical value would have
    // multiple valid encodings, breaking content addressing.
    if (additionalInfo >= 24 && additionalInfo <= 27) {
        // Natural floor per DAG-CBOR canonical form — anything below this
        // fits in a smaller additionalInfo, so the wider encoding is
        // non-minimal:
        //   additionalInfo 24 → value < 24    (could have used < 24)
        //   additionalInfo 25 → value < 256   (could have used 24)
        //   additionalInfo 26 → value < 65536 (could have used 25)
        //   additionalInfo 27 → value < 2^32  (could have used 26)
        static const uint64_t kMinValueForAdditional[] = {
            24, 256, 65536, 4294967296ULL
        };
        if (value < kMinValueForAdditional[additionalInfo - 24]) {
            [self _setDecodingError:error message:@"Non-minimal length encoding"];
            return nil;
        }
    }

    return @(value);
}

+ (nullable NSNumber *)_decodeUnsignedInteger:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index error:(NSError **)error {
    NSNumber *unsignedValue = [self _decodeLength:additionalInfo bytes:bytes length:length index:index error:error];
    if (!unsignedValue) return nil;
    if (unsignedValue.unsignedLongLongValue > (uint64_t)INT64_MAX) {
        [self _setDecodingError:error message:@"Unsigned integer exceeds int64 range"];
        return nil;
    }
    return unsignedValue;
}

+ (nullable NSNumber *)_decodeNegativeInteger:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index error:(NSError **)error {
    NSNumber *unsignedValue = [self _decodeLength:additionalInfo bytes:bytes length:length index:index error:error];
    if (!unsignedValue) return nil;
    uint64_t value = unsignedValue.unsignedLongLongValue;
    // DAG-CBOR negative integers decode to -(value+1); value must stay within
    // [0, INT64_MAX] so the result stays within [INT64_MIN, -1]. Above that,
    // value+1 either overflows int64 or wraps uint64_t to 0 (at 2^64-1).
    if (value > (uint64_t)INT64_MAX) {
        [self _setDecodingError:error message:@"Negative integer exceeds int64 range"];
        return nil;
    }
    return @( -1 - (int64_t)value );
}

+ (nullable NSData *)_decodeByteString:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index error:(NSError **)error {
    NSNumber *byteLength = [self _decodeLength:additionalInfo bytes:bytes length:length index:index error:error];
    if (!byteLength) return nil;
    
    uint64_t len = byteLength.unsignedLongLongValue;
    // Compare against remaining bytes rather than summing *index + len, which
    // can wrap NSUInteger for an attacker-controlled 64-bit len.
    if (*index > length || len > length - *index) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Byte string length exceeds data"}];
        }
        return nil;
    }
    
    NSData *result = [NSData dataWithBytes:bytes + *index length:len];
    *index += len;
    return result;
}

+ (nullable NSString *)_decodeTextString:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index error:(NSError **)error {
    NSData *byteData = [self _decodeByteString:additionalInfo bytes:bytes length:length index:index error:error];
    if (!byteData) return nil;
    
    NSString *string = [[NSString alloc] initWithData:byteData encoding:NSUTF8StringEncoding];
    if (!string && error) {
        *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                     code:ATProtoDagCBORErrorCodeDecodingFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"Invalid UTF-8 in text string"}];
    }
    return string;
}

+ (nullable NSArray *)_decodeArray:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index depth:(NSUInteger)depth profile:(ATProtoDRISLProfile)profile error:(NSError **)error {
    NSNumber *arrayLength = [self _decodeLength:additionalInfo bytes:bytes length:length index:index error:error];
    if (!arrayLength) return nil;
    
    uint64_t count = arrayLength.unsignedLongLongValue;
    // Every array item needs at least one byte, so a declared count larger
    // than the remaining input is never valid — reject before allocating a
    // capacity hint sized from attacker-controlled input.
    NSUInteger remaining = (*index <= length) ? (length - *index) : 0;
    if (count > remaining) {
        [self _setDecodingError:error message:@"Array count exceeds remaining data"];
        return nil;
    }
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:count];

    for (uint64_t i = 0; i < count; i++) {
        id item = [self _decodeFromBytes:bytes length:length index:index depth:depth + 1 profile:profile error:error];
        if (!item) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                             code:ATProtoDagCBORErrorCodeDecodingFailed
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode array item"}];
            }
            return nil;
        }
        [array addObject:item];
    }
    
    return array;
}

+ (nullable NSDictionary *)_decodeMap:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index depth:(NSUInteger)depth profile:(ATProtoDRISLProfile)profile error:(NSError **)error {
    NSNumber *mapLength = [self _decodeLength:additionalInfo bytes:bytes length:length index:index error:error];
    if (!mapLength) return nil;
    
    uint64_t count = mapLength.unsignedLongLongValue;
    // Every map entry needs at least one byte for its key and one for its
    // value, so a declared count larger than half the remaining input is
    // never valid — reject before allocating a capacity hint sized from
    // attacker-controlled input. Dividing first avoids overflowing 2*count.
    NSUInteger remaining = (*index <= length) ? (length - *index) : 0;
    if (count > remaining / 2) {
        [self _setDecodingError:error message:@"Map count exceeds remaining data"];
        return nil;
    }
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:count];

    // Previous key's raw encoded bytes for sort-order + duplicate detection.
    const uint8_t *prevKeyBytes = NULL;
    NSUInteger prevKeyLen = 0;

    for (uint64_t i = 0; i < count; i++) {
        NSUInteger keyStart = *index;
        id key = [self _decodeFromBytes:bytes length:length index:index depth:depth + 1 profile:profile error:error];
        if (!key) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                             code:ATProtoDagCBORErrorCodeDecodingFailed
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode map key"}];
            }
            return nil;
        }

        // DRISL permits text-string keys only. Without this, an integer key
        // decodes into a perfectly usable NSNumber dictionary key and the
        // document silently round-trips as something no conforming decoder
        // accepts.
        if (![key isKindOfClass:[NSString class]]) {
            if (error) {
                *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                             code:ATProtoDagCBORErrorCodeNonStringMapKey
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"DRISL map keys must be strings, got %@", NSStringFromClass([key class])]}];
            }
            return nil;
        }
        NSUInteger keyEnd = *index;
        NSUInteger keyLen = keyEnd - keyStart;

        // Enforce DAG-CBOR canonical sort order and reject duplicate keys.
        // Two distinct encodings that decode to the same NSDictionary key
        // would otherwise silently last-write-win through `dict[key] = value`,
        // hiding the loss.
        if (prevKeyBytes != NULL) {
            NSInteger cmp = _dagCBORCompareEncodedKeys(bytes + keyStart, keyLen,
                                                       prevKeyBytes, prevKeyLen);
            if (cmp < 0) {
                [self _setDecodingError:error message:@"Map keys not in canonical DAG-CBOR order"];
                return nil;
            }
            if (cmp == 0) {
                [self _setDecodingError:error message:@"Duplicate map key"];
                return nil;
            }
        }
        prevKeyBytes = bytes + keyStart;
        prevKeyLen = keyLen;

        id value = [self _decodeFromBytes:bytes length:length index:index depth:depth + 1 profile:profile error:error];
        if (!value) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                             code:ATProtoDagCBORErrorCodeDecodingFailed
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode map value"}];
            }
            return nil;
        }

        dict[key] = value;
    }
    
    return dict;
}

+ (nullable id)_decodeTag:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index depth:(NSUInteger)depth profile:(ATProtoDRISLProfile)profile error:(NSError **)error {
    NSNumber *tagNumber = [self _decodeLength:additionalInfo bytes:bytes length:length index:index error:error];
    if (!tagNumber) return nil;

    uint64_t tag = tagNumber.unsignedLongLongValue;

    // DRISL permits tag 42 and nothing else. Reject before decoding the
    // content: an unknown tag used to be unwrapped and its payload returned,
    // which meant a tagged document decoded and re-encoded to *different*
    // bytes — a different CID for the same input. Bignums (tags 2 and 3),
    // datetimes (tag 0) and self-describing CBOR (tag 55799) all land here.
    if (tag != 42) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeDisallowedTag
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"DRISL permits only CBOR tag 42, got tag %llu", (unsigned long long)tag]}];
        }
        return nil;
    }

    // Decode the tagged value
    id taggedValue = [self _decodeFromBytes:bytes length:length index:index depth:depth + 1 profile:profile error:error];
    if (!taggedValue) return nil;

    // Handle CID-link (tag 42)
    {
        if (![taggedValue isKindOfClass:[NSData class]]) {
            if (error) {
                *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                             code:ATProtoDagCBORErrorCodeInvalidCIDLink
                                         userInfo:@{NSLocalizedDescriptionKey: @"Tag 42 value must be byte string"}];
            }
            return nil;
        }
        
        NSData *cidData = (NSData *)taggedValue;
        if (cidData.length < 1) {
            if (error) {
                *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                             code:ATProtoDagCBORErrorCodeInvalidCIDLink
                                         userInfo:@{NSLocalizedDescriptionKey: @"CID-link byte string is empty"}];
            }
            return nil;
        }
        
        const uint8_t *cidBytes = cidData.bytes;
        if (cidBytes[0] != 0x00) {
            if (error) {
                *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                             code:ATProtoDagCBORErrorCodeInvalidCIDLink
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"CID-link must start with 0x00, got 0x%02X", cidBytes[0]]}];
            }
            return nil;
        }
        
        NSData *pureCIDBytes = [cidData subdataWithRange:NSMakeRange(1, cidData.length - 1)];

        // The ATProto profile keeps the permissive parser on purpose. Links
        // inside records include blob references, and blobs uploaded before
        // the CID rules settled carry dag-pb and other non-DASL CIDs; those
        // records are already signed and must stay readable. The DRISL
        // profile, which no repository data goes through, holds links to the
        // strict spec.
        CID *cid = (profile == ATProtoDRISLProfileDRISL)
            ? [CID daslCIDFromBytes:pureCIDBytes profile:ATProtoDASLCIDProfileBig]
            : [CID cidFromBytes:pureCIDBytes];
        if (!cid && error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeInvalidCIDLink
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID bytes in tag 42"}];
        }
        return cid;
    }
}

+ (nullable id)_decodeSpecial:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index profile:(ATProtoDRISLProfile)profile error:(NSError **)error {
    switch (additionalInfo) {
        case 20: // false
            return @NO;
        case 21: // true
            return @YES;
        case 22: // null
            return [NSNull null];

        case 23:
            // `undefined`. DRISL allows true, false and null only. Decoding it
            // to NSNull used to make 0xF7 re-encode as 0xF6 — a silent change
            // of bytes, and so of CID, for any document containing it.
            [self _setDecodingError:error message:@"DRISL forbids the `undefined` simple value"];
            return nil;

        case 27:
            return [self _decodeFloat64:bytes length:length index:index profile:profile error:error];

        case 25: // half-precision float
        case 26: // single-precision float
            if (error) {
                *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                             code:ATProtoDagCBORErrorCodeFloatsNotAllowed
                                         userInfo:@{NSLocalizedDescriptionKey: @"DRISL permits only 64-bit floats"}];
            }
            return nil;

        default:
            // additionalInfo 24 is a simple value in the following byte, and
            // 0-19 are the inline unassigned simple values. DRISL allows
            // neither. 28-30 are reserved and 31 is the indefinite-length
            // break code.
            if (error) {
                *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                             code:ATProtoDagCBORErrorCodeDecodingFailed
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported special value: %u", additionalInfo]}];
            }
            return nil;
    }
}

+ (nullable ATProtoDRISLFloat *)_decodeFloat64:(const uint8_t *)bytes
                                        length:(NSUInteger)length
                                         index:(NSUInteger *)index
                                       profile:(ATProtoDRISLProfile)profile
                                         error:(NSError **)error {
    if (profile != ATProtoDRISLProfileDRISL) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeFloatsNotAllowed
                                     userInfo:@{NSLocalizedDescriptionKey: @"ATProto records forbid floats; decode under ATProtoDRISLProfileDRISL to accept one"}];
        }
        return nil;
    }

    // Compare against remaining bytes rather than summing, which can wrap.
    if (*index > length || length - *index < 8) {
        [self _setDecodingError:error message:@"Truncated 64-bit float"];
        return nil;
    }

    uint64_t bits = 0;
    for (int i = 0; i < 8; i++) {
        bits = (bits << 8) | bytes[*index + i];
    }
    *index += 8;

    double value = 0;
    memcpy(&value, &bits, sizeof(value));

    if (isnan(value) || isinf(value)) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeFloatsNotAllowed
                                     userInfo:@{NSLocalizedDescriptionKey: @"DRISL forbids NaN, Infinity and -Infinity"}];
        }
        return nil;
    }

    return [ATProtoDRISLFloat floatWithValue:value];
}

@end
