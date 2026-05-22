// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const ATProtoDagCBORErrorDomain = @"com.atproto.dagcbor";

static const NSUInteger kMaxDecodeDepth = 64;

@implementation ATProtoDagCBOR

#pragma mark - Public API

+ (nullable NSData *)encodeObject:(id)object error:(NSError **)error {
    NSMutableData *result = [NSMutableData data];
    if (![self _encodeValue:object toData:result error:error]) {
        return nil;
    }
    return result;
}

+ (nullable id)decodeData:(NSData *)data error:(NSError **)error {
    if (data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty CBOR data"}];
        }
        return nil;
    }
    
    NSUInteger index = 0;
    return [self _decodeFromBytes:data.bytes length:data.length index:&index depth:0 error:error];
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

+ (BOOL)_encodeValue:(id)value toData:(NSMutableData *)data error:(NSError **)error {
    if ([value isKindOfClass:[NSNull class]]) {
        uint8_t byte = 0xF6;
        [data appendBytes:&byte length:1];
        return YES;
        
    } else if ([value isKindOfClass:[NSNumber class]]) {
        return [self _encodeNumber:(NSNumber *)value toData:data error:error];
        
    } else if ([value isKindOfClass:[NSString class]]) {
        return [self _encodeString:(NSString *)value toData:data error:error];
        
    } else if ([value isKindOfClass:[NSData class]]) {
        return [self _encodeByteString:(NSData *)value toData:data error:error];
        
    } else if ([value isKindOfClass:[NSArray class]]) {
        return [self _encodeArray:(NSArray *)value toData:data error:error];
        
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        return [self _encodeMap:(NSDictionary *)value toData:data error:error];
        
    } else if ([value isKindOfClass:[CID class]]) {
        return [self _encodeCIDLink:(CID *)value toData:data error:error];
        
    } else {
        NSLog(@"ATProtoDagCBOR: Unsupported type: %@", NSStringFromClass([value class]));
        if (error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeInvalidType
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported type: %@", NSStringFromClass([value class])]}];
        }
        return NO;
    }
}

+ (BOOL)_encodeNumber:(NSNumber *)number toData:(NSMutableData *)data error:(NSError **)error {
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
    
    // Reject non-integer floats per DRISL-CBOR spec
    if (error) {
        *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                     code:ATProtoDagCBORErrorCodeFloatsNotAllowed
                                 userInfo:@{NSLocalizedDescriptionKey: @"DRISL-CBOR forbids IEEE 754 floats"}];
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

+ (BOOL)_encodeArray:(NSArray *)array toData:(NSMutableData *)data error:(NSError **)error {
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
        if (![self _encodeValue:item toData:data error:error]) {
            return NO;
        }
    }
    
    return YES;
}

+ (BOOL)_encodeMap:(NSDictionary *)dict toData:(NSMutableData *)data error:(NSError **)error {
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
        if (![self _encodeValue:key toData:data error:error]) {
            return NO;
        }
        if (![self _encodeValue:dict[key] toData:data error:error]) {
            return NO;
        }
    }
    
    return YES;
}

+ (nullable NSArray *)_canonicallySortedKeys:(NSArray *)keys error:(NSError **)error {
    // Encode each key and pair it with the original key
    NSMutableArray *encodedPairs = [NSMutableArray arrayWithCapacity:keys.count];
    for (id key in keys) {
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

+ (nullable id)_decodeFromBytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index depth:(NSUInteger)depth error:(NSError **)error {
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
            return [self _decodeArray:additionalInfo bytes:bytes length:length index:index depth:depth error:error];
            
        case 5: // Map
            return [self _decodeMap:additionalInfo bytes:bytes length:length index:index depth:depth error:error];
            
        case 6: // Tag
            return [self _decodeTag:additionalInfo bytes:bytes length:length index:index depth:depth error:error];
            
        case 7: // Special/float
            return [self _decodeSpecial:additionalInfo bytes:bytes length:length index:index error:error];
            
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
    
    return @(value);
}

+ (nullable NSNumber *)_decodeUnsignedInteger:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index error:(NSError **)error {
    return [self _decodeLength:additionalInfo bytes:bytes length:length index:index error:error];
}

+ (nullable NSNumber *)_decodeNegativeInteger:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index error:(NSError **)error {
    NSNumber *unsignedValue = [self _decodeLength:additionalInfo bytes:bytes length:length index:index error:error];
    if (!unsignedValue) return nil;
    return @(-(int64_t)(unsignedValue.unsignedLongLongValue + 1));
}

+ (nullable NSData *)_decodeByteString:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index error:(NSError **)error {
    NSNumber *byteLength = [self _decodeLength:additionalInfo bytes:bytes length:length index:index error:error];
    if (!byteLength) return nil;
    
    uint64_t len = byteLength.unsignedLongLongValue;
    if (*index > length || *index + len > length) {
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

+ (nullable NSArray *)_decodeArray:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index depth:(NSUInteger)depth error:(NSError **)error {
    NSNumber *arrayLength = [self _decodeLength:additionalInfo bytes:bytes length:length index:index error:error];
    if (!arrayLength) return nil;
    
    uint64_t count = arrayLength.unsignedLongLongValue;
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:count];
    
    for (uint64_t i = 0; i < count; i++) {
        id item = [self _decodeFromBytes:bytes length:length index:index depth:depth + 1 error:error];
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

+ (nullable NSDictionary *)_decodeMap:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index depth:(NSUInteger)depth error:(NSError **)error {
    NSNumber *mapLength = [self _decodeLength:additionalInfo bytes:bytes length:length index:index error:error];
    if (!mapLength) return nil;
    
    uint64_t count = mapLength.unsignedLongLongValue;
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:count];
    
    for (uint64_t i = 0; i < count; i++) {
        id key = [self _decodeFromBytes:bytes length:length index:index depth:depth + 1 error:error];
        if (!key) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                             code:ATProtoDagCBORErrorCodeDecodingFailed
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode map key"}];
            }
            return nil;
        }
        
        id value = [self _decodeFromBytes:bytes length:length index:index depth:depth + 1 error:error];
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

+ (nullable id)_decodeTag:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index depth:(NSUInteger)depth error:(NSError **)error {
    NSNumber *tagNumber = [self _decodeLength:additionalInfo bytes:bytes length:length index:index error:error];
    if (!tagNumber) return nil;
    
    uint64_t tag = tagNumber.unsignedLongLongValue;
    
    // Decode the tagged value
    id taggedValue = [self _decodeFromBytes:bytes length:length index:index depth:depth + 1 error:error];
    if (!taggedValue) return nil;
    
    // Handle CID-link (tag 42)
    if (tag == 42) {
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
        CID *cid = [CID cidFromBytes:pureCIDBytes];
        if (!cid && error) {
            *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                         code:ATProtoDagCBORErrorCodeInvalidCIDLink
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID bytes in tag 42"}];
        }
        return cid;
    }
    
    // Unknown tags: return the tagged value as-is
    // (In a full implementation, you might want to preserve the tag somehow)
    return taggedValue;
}

+ (nullable id)_decodeSpecial:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index error:(NSError **)error {
    switch (additionalInfo) {
        case 20: // false
            return @NO;
        case 21: // true
            return @YES;
        case 22: // null
            return [NSNull null];
        case 23: // undefined (treat as null)
            return [NSNull null];
        default:
            if (error) {
                *error = [NSError errorWithDomain:ATProtoDagCBORErrorDomain
                                             code:ATProtoDagCBORErrorCodeDecodingFailed
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported special value: %u", additionalInfo]}];
            }
            return nil;
    }
}

@end
