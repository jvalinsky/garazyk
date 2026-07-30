// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file CBOR.m

 @abstract CBOR (Concise Binary Object Representation) encoding and decoding.

 @discussion This file implements CBOR serialization for ATProto repository
 data structures. CBOR is used for Merkle Search Tree node serialization
 and CAR file content encoding, following RFC 8949.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import "Core/CBOR.h"
#import <Security/Security.h>

/// Maximum nesting depth for CBOR decoder recursion.
/// Prevents stack overflow from deeply nested arrays and maps.
/// Matches the depth cap in ATProtoDagCBOR (kMaxDecodeDepth = 64).
/// @see ParserRecursionExploitTests.testNestingDepthIsBounded
static const NSUInteger kCBORMaxDecodeDepth = 64;

#pragma mark - CBORValue Implementation

@implementation CBORValue

+ (instancetype)unsignedInteger:(NSUInteger)value {
    CBORValue *result = [[CBORValue alloc] initWithUnsignedInteger:@(value)];
    return result;
}

+ (instancetype)negativeInteger:(NSInteger)value {
    CBORValue *result = [[CBORValue alloc] initWithNegativeInteger:@(value)];
    return result;
}

+ (instancetype)byteString:(NSData *)data {
    return [[self alloc] initWithByteString:data];
}

+ (instancetype)textString:(NSString *)string {
    return [[self alloc] initWithTextString:string];
}

+ (instancetype)array:(NSArray<CBORValue *> *)array {
    return [[self alloc] initWithArray:array];
}

+ (instancetype)map:(NSDictionary<CBORValue *, CBORValue *> *)map {
    return [[self alloc] initWithMap:map];
}

+ (instancetype)tag:(NSUInteger)tag value:(CBORValue *)value {
    return [[self alloc] initWithTag:@(tag) value:value];
}

+ (instancetype)simple:(NSUInteger)value {
    return [[self alloc] initWithSimpleValue:@(value)];
}

+ (instancetype)floatingPoint:(double)value {
    return [[self alloc] initWithFloatValue:@(value)];
}

+ (instancetype)nilValue {
    return [self simple:22];
}

- (instancetype)initWithType:(CBORType)type {
    self = [super init];
    if (self) {
        _type = type;
    }
    return self;
}

- (instancetype)initWithUnsignedInteger:(NSNumber *)value {
    self = [self initWithType:CBORTypeUnsignedInteger];
    if (self) {
        _unsignedInteger = value;
    }
    return self;
}

- (instancetype)initWithNegativeInteger:(NSNumber *)value {
    self = [self initWithType:CBORTypeNegativeInteger];
    if (self) {
        _negativeInteger = value;
    }
    return self;
}

- (instancetype)initWithByteString:(NSData *)data {
    self = [self initWithType:CBORTypeByteString];
    if (self) {
        _byteString = data;
    }
    return self;
}

- (instancetype)initWithTextString:(NSString *)string {
    self = [self initWithType:CBORTypeTextString];
    if (self) {
        _textString = string;
    }
    return self;
}

- (instancetype)initWithArray:(NSArray<CBORValue *> *)array {
    self = [self initWithType:CBORTypeArray];
    if (self) {
        _array = array;
    }
    return self;
}

- (instancetype)initWithMap:(NSDictionary<CBORValue *, CBORValue *> *)map {
    self = [self initWithType:CBORTypeMap];
    if (self) {
        _map = map;
    }
    return self;
}

- (instancetype)initWithTag:(NSNumber *)tag value:(CBORValue *)value {
    self = [self initWithType:CBORTypeTag];
    if (self) {
        _tag = tag;
        _tagValue = value;
    }
    return self;
}

- (instancetype)initWithSimpleValue:(NSNumber *)value {
    self = [self initWithType:CBORTypeSimpleOrFloat];
    if (self) {
        _simpleValue = value;
    }
    return self;
}

- (instancetype)initWithFloatValue:(NSNumber *)value {
    self = [self initWithType:CBORTypeSimpleOrFloat];
    if (self) {
        _floatValue = value;
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[CBORValue class]]) {
        return NO;
    }
    CBORValue *other = (CBORValue *)object;
    if (self.type != other.type) {
        return NO;
    }
    switch (self.type) {
        case CBORTypeUnsignedInteger:
            return [self.unsignedInteger isEqualToNumber:other.unsignedInteger];
        case CBORTypeNegativeInteger:
            return [self.negativeInteger isEqualToNumber:other.negativeInteger];
        case CBORTypeByteString:
            return [self.byteString isEqualToData:other.byteString];
        case CBORTypeTextString:
            return [self.textString isEqualToString:other.textString];
        case CBORTypeArray:
            return [self.array isEqualToArray:other.array];
        case CBORTypeMap:
            return [self.map isEqualToDictionary:other.map];
        case CBORTypeTag:
            return [self.tag isEqualToNumber:other.tag] && [self.tagValue isEqual:other.tagValue];
        case CBORTypeSimpleOrFloat:
            if (self.simpleValue && other.simpleValue) {
                return [self.simpleValue isEqualToNumber:other.simpleValue];
            }
            if (self.floatValue && other.floatValue) {
                return self.floatValue.doubleValue == other.floatValue.doubleValue;
            }
            return NO;
    }
    return NO;
}

- (id)underlyingValue {
    switch (self.type) {
        case CBORTypeUnsignedInteger:
            return self.unsignedInteger;
        case CBORTypeNegativeInteger:
            return self.negativeInteger;
        case CBORTypeByteString:
            return self.byteString;
        case CBORTypeTextString:
            return self.textString;
        case CBORTypeArray:
            return self.array;
        case CBORTypeMap:
            return self.map;
        case CBORTypeTag:
            return self.tag;
        case CBORTypeSimpleOrFloat:
            return self.simpleValue ?: @(self.floatValue.doubleValue);
    }
    return nil;
}

- (NSUInteger)hash {
    return self.type ^ [[self underlyingValue] hash];
}

- (NSData *)encode {
    return [CBOREncoder encode:self];
}

+ (instancetype)decode:(NSData *)data {
    return [CBORDecoder decode:data];
}

- (id)copyWithZone:(NSZone *)zone {
    CBORValue *copy = [[CBORValue allocWithZone:zone] initWithType:self.type];
    copy->_unsignedInteger = self.unsignedInteger;
    copy->_negativeInteger = self.negativeInteger;
    copy->_byteString = self.byteString;
    copy->_textString = self.textString;
    copy->_array = self.array;
    copy->_map = self.map;
    copy->_tag = self.tag;
    copy->_tagValue = self.tagValue;
    copy->_simpleValue = self.simpleValue;
    copy->_floatValue = self.floatValue;
    return copy;
}

@end

#pragma mark - CBOREncoder Implementation

@implementation CBOREncoder

+ (NSData *)encode:(CBORValue *)value {
    NSMutableData *data = [NSMutableData data];
    [self encodeValue:value toData:data];
    return [data copy];
}

+ (void)encodeValue:(CBORValue *)value toData:(NSMutableData *)data {
    switch (value.type) {
        case CBORTypeUnsignedInteger:
            [self encodeUnsignedInteger:value.unsignedInteger.unsignedIntegerValue toData:data];
            break;
        case CBORTypeNegativeInteger:
            [self encodeNegativeInteger:value.negativeInteger.integerValue toData:data];
            break;
        case CBORTypeByteString:
            [self encodeByteString:value.byteString toData:data];
            break;
        case CBORTypeTextString:
            [self encodeTextString:value.textString toData:data];
            break;
        case CBORTypeArray:
            [self encodeArray:value.array toData:data];
            break;
        case CBORTypeMap:
            [self encodeMap:value.map toData:data];
            break;
        case CBORTypeTag:
            [self encodeTag:value.tag.unsignedIntegerValue value:value.tagValue toData:data];
            break;
        case CBORTypeSimpleOrFloat:
            if (value.simpleValue) {
                [self encodeSimpleValue:value.simpleValue.unsignedIntegerValue toData:data];
            } else if (value.floatValue) {
                [self encodeFloatValue:value.floatValue.doubleValue toData:data];
            }
            break;
    }
}

+ (void)encodeCount:(NSUInteger)count withMajorType:(uint8_t)majorType toData:(NSMutableData *)data {
    uint8_t major = majorType;
    if (count < 24) {
        uint8_t byte = major | (uint8_t)count;
        [data appendBytes:&byte length:1];
    } else if (count < 256) {
        major |= 24;
        [data appendBytes:&major length:1];
        uint8_t len = (uint8_t)count;
        [data appendBytes:&len length:1];
    } else if (count < 65536) {
        major |= 25;
        [data appendBytes:&major length:1];
        uint16_t be = OSSwapHostToBigInt16((uint16_t)count);
        [data appendBytes:&be length:2];
    } else if (count < 4294967296ULL) {
        major |= 26;
        [data appendBytes:&major length:1];
        uint32_t be = OSSwapHostToBigInt32((uint32_t)count);
        [data appendBytes:&be length:4];
    } else {
        major |= 27;
        [data appendBytes:&major length:1];
        uint64_t be = OSSwapHostToBigInt64((uint64_t)count);
        [data appendBytes:&be length:8];
    }
}

+ (void)encodeUnsignedInteger:(NSUInteger)value toData:(NSMutableData *)data {
    if (value < 24) {
        uint8_t byte = (uint8_t)value;
        [data appendBytes:&byte length:1];
    } else if (value < 256) {
        uint8_t major = 0x18;
        [data appendBytes:&major length:1];
        uint8_t byte = (uint8_t)value;
        [data appendBytes:&byte length:1];
    } else if (value < 65536) {
        uint8_t major = 0x19;
        [data appendBytes:&major length:1];
        uint16_t be = OSSwapHostToBigInt16((uint16_t)value);
        [data appendBytes:&be length:2];
    } else if (value < 4294967296ULL) {
        uint8_t major = 0x1A;
        [data appendBytes:&major length:1];
        uint32_t be = OSSwapHostToBigInt32((uint32_t)value);
        [data appendBytes:&be length:4];
    } else {
        uint8_t major = 0x1B;
        [data appendBytes:&major length:1];
        uint64_t be = OSSwapHostToBigInt64(value);
        [data appendBytes:&be length:8];
    }
}

+ (void)encodeNegativeInteger:(NSInteger)value toData:(NSMutableData *)data {
    // The general formula works for all NSInteger values including INT64_MIN:
    // INT64_MIN + 1 = -INT64_MAX (in range), negated = INT64_MAX (9223372036854775807).
    // The old special case (value == NSIntegerMin → UINT64_MAX) was wrong.
    NSUInteger unsignedValue = (NSUInteger)(-(value + 1));

    uint8_t base = 0x20;
    if (unsignedValue < 24) {
        uint8_t byte = base | (uint8_t)unsignedValue;
        [data appendBytes:&byte length:1];
    } else if (unsignedValue < 256) {
        uint8_t bytes[2] = { base | 24, (uint8_t)unsignedValue };
        [data appendBytes:bytes length:2];
    } else if (unsignedValue < 65536) {
        uint8_t bytes[3] = { base | 25 };
        uint16_t be = OSSwapHostToBigInt16((uint16_t)unsignedValue);
        memcpy(bytes + 1, &be, 2);
        [data appendBytes:bytes length:3];
    } else if (unsignedValue < 4294967296ULL) {
        uint8_t major = 0x3A;
        [data appendBytes:&major length:1];
        uint32_t be = OSSwapHostToBigInt32((uint32_t)unsignedValue);
        [data appendBytes:&be length:4];
    } else {
        uint8_t major = 0x3B;
        [data appendBytes:&major length:1];
        uint64_t be = OSSwapHostToBigInt64(unsignedValue);
        [data appendBytes:&be length:8];
    }
}

+ (void)encodeByteString:(NSData *)data toData:(NSMutableData *)output {
    NSUInteger length = data.length;
    [self encodeCount:length withMajorType:0x40 toData:output];
    [output appendData:data];
}

+ (void)encodeTextString:(NSString *)string toData:(NSMutableData *)data {
    NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger length = utf8.length;
    [self encodeCount:length withMajorType:0x60 toData:data];
    [data appendData:utf8];
}

+ (void)encodeArray:(NSArray<CBORValue *> *)array toData:(NSMutableData *)output {
    NSUInteger count = array.count;
    [self encodeCount:count withMajorType:0x80 toData:output];
    for (CBORValue *value in array) {
        [self encodeValue:value toData:output];
    }
}

+ (void)encodeMap:(NSDictionary<CBORValue *, CBORValue *> *)map toData:(NSMutableData *)output {
    NSUInteger count = map.count;
    [self encodeCount:count withMajorType:0xA0 toData:output];
    if (count == 0) return;
    
    NSArray *keys = [map allKeys];
    NSArray *sortedKeys = [keys sortedArrayUsingComparator:^NSComparisonResult(CBORValue *key1, CBORValue *key2) {
        NSData *d1 = [key1 encode];
        NSData *d2 = [key2 encode];
        if (d1.length < d2.length) return NSOrderedAscending;
        if (d1.length > d2.length) return NSOrderedDescending;
        int cmp = memcmp(d1.bytes, d2.bytes, d1.length);
        if (cmp < 0) return NSOrderedAscending;
        if (cmp > 0) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    for (CBORValue *key in sortedKeys) {
        [self encodeValue:key toData:output];
        [self encodeValue:map[key] toData:output];
    }
}

+ (void)encodeTag:(NSUInteger)tag value:(CBORValue *)value toData:(NSMutableData *)data {
    [self encodeCount:tag withMajorType:0xC0 toData:data];
    [self encodeValue:value toData:data];
}

+ (void)encodeSimpleValue:(NSUInteger)value toData:(NSMutableData *)data {
    uint8_t byte = 0xE0 | (uint8_t)value;
    [data appendBytes:&byte length:1];
}

+ (void)encodeFloatValue:(double)value toData:(NSMutableData *)data {
    uint8_t major = 0xFB;
    [data appendBytes:&major length:1];
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    uint64_t be = OSSwapHostToBigInt64(bits);
    [data appendBytes:&be length:8];
}

@end

#pragma mark - CBORDecoder Implementation

@implementation CBORDecoder

+ (CBORValue *)decode:(NSData *)data {
    // §3.4 option (c): the generic CBOR decoder is lenient; strict canonical-form
    // enforcement (trailing-data rejection, duplicate-key rejection, non-minimal
    // length rejection) belongs in ATProtoDagCBOR for content-addressed callers.
    // §1.2 depth cap: passes depth=0 to the internal decoder, which rejects
    // nesting beyond kCBORMaxDecodeDepth.
    // Match test: ParserRecursionExploitTests/testNestingDepthIsBounded.
    NSUInteger offset = 0;
    CBORValue *result = [self decodeInternal:data offset:&offset depth:0];
    if (result == nil) return nil;
    return result;
}

+ (CBORValue *)decode:(NSData *)data offset:(NSUInteger *)offset {
    return [self decodeInternal:data offset:offset depth:0];
}

/// Internal decoder with explicit depth tracking.
/// @param data The CBOR-encoded data.
/// @param offset On input, the position to start decoding; on output, the
///   position after the decoded item.
/// @param depth Current nesting depth. Must be <= kCBORMaxDecodeDepth.
/// @return The decoded CBOR value, or nil on failure (including exceeding
///   the depth cap).
+ (CBORValue *)decodeInternal:(NSData *)data offset:(NSUInteger *)offset depth:(NSUInteger)depth {
    if (depth > kCBORMaxDecodeDepth) return nil;
    if (*offset >= data.length) {
        return nil;
    }

    const uint8_t *bytes = data.bytes;
    uint8_t initial = bytes[(*offset)++];
    uint8_t majorType = (initial & 0xE0) >> 5;
    uint8_t additional = initial & 0x1F;

    CBORValue *result = nil;
    switch (majorType) {
        case 0: result = [self decodeUnsignedInteger:additional data:data offset:offset]; break;
        case 1: result = [self decodeNegativeInteger:additional data:data offset:offset]; break;
        case 2: result = [self decodeByteString:additional data:data offset:offset]; break;
        case 3: result = [self decodeTextString:additional data:data offset:offset]; break;
        case 4: result = [self decodeArray:additional data:data offset:offset depth:depth]; break;
        case 5: result = [self decodeMap:additional data:data offset:offset depth:depth]; break;
        case 6: result = [self decodeTag:additional data:data offset:offset depth:depth]; break;
        case 7: result = [self decodeSimpleOrFloat:additional data:data offset:offset]; break;
        default: return nil;
    }
    return result;
}

+ (CBORValue *)decodeUnsignedInteger:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
    NSUInteger value = 0;
    if (additional < 24) {
        value = additional;
    } else {
        NSUInteger bytesToRead = [self bytesToReadForAdditional:additional];
        if (bytesToRead == 0 || *offset + bytesToRead > data.length) return nil;
        value = [self readIntegerFromData:data offset:offset bytesToRead:bytesToRead];
        *offset += bytesToRead;
    }
    return [CBORValue unsignedInteger:value];
}

+ (CBORValue *)decodeNegativeInteger:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
    CBORValue *unsignedValue = [self decodeUnsignedInteger:additional data:data offset:offset];
    if (!unsignedValue) return nil;
    // §3.3: the old expression -(NSInteger)(u + 1) has signed-overflow UB
    // when u == INT64_MAX (payload 0x7FFFF...). Fix shape matches §1.5 item 4.
    NSUInteger u = unsignedValue.unsignedInteger.unsignedIntegerValue;
    if (u > (NSUInteger)INT64_MAX) return nil;  // Payload exceeds representable range.
    NSInteger value = -1 - (NSInteger)u;
    return [CBORValue negativeInteger:value];
}

+ (CBORValue *)decodeByteString:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
    NSUInteger length = 0;
    if (additional < 24) {
        length = additional;
    } else {
        NSUInteger bytesToRead = [self bytesToReadForAdditional:additional];
        if (bytesToRead == 0 || *offset + bytesToRead > data.length) return nil;
        length = [self readIntegerFromData:data offset:offset bytesToRead:bytesToRead];
        *offset += bytesToRead;
    }
    if (length > data.length - *offset) return nil;
    NSData *value = [data subdataWithRange:NSMakeRange(*offset, length)];
    *offset += length;
    return [CBORValue byteString:value];
}

+ (CBORValue *)decodeTextString:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
    NSUInteger length = 0;
    if (additional < 24) {
        length = additional;
    } else {
        NSUInteger bytesToRead = [self bytesToReadForAdditional:additional];
        if (bytesToRead == 0 || *offset + bytesToRead > data.length) return nil;
        length = [self readIntegerFromData:data offset:offset bytesToRead:bytesToRead];
        *offset += bytesToRead;
    }
    if (length > data.length - *offset) return nil;
    NSData *valueData = [data subdataWithRange:NSMakeRange(*offset, length)];
    *offset += length;
    NSString *value = [[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding];
    return [CBORValue textString:value ?: @""];
}

+ (CBORValue *)decodeArray:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset depth:(NSUInteger)depth {
    NSUInteger count = 0;
    if (additional < 24) {
        count = additional;
    } else {
        NSUInteger bytesToRead = [self bytesToReadForAdditional:additional];
        if (bytesToRead == 0 || *offset + bytesToRead > data.length) return nil;
        count = [self readIntegerFromData:data offset:offset bytesToRead:bytesToRead];
        *offset += bytesToRead;
    }
    
    // Security check: Ensure we have enough data remaining to satisfy the count.
    // Minimum size of an item is 1 byte.
    if (data.length - *offset < count) {
        return nil;
    }
    
    NSMutableArray<CBORValue *> *array = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        CBORValue *value = [self decodeInternal:data offset:offset depth:depth + 1];
        if (!value) return nil;
        [array addObject:value];
    }
    return [CBORValue array:array];
}

+ (CBORValue *)decodeMap:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset depth:(NSUInteger)depth {
    NSUInteger count = 0;
    if (additional < 24) {
        count = additional;
    } else {
        NSUInteger bytesToRead = [self bytesToReadForAdditional:additional];
        if (bytesToRead == 0 || *offset + bytesToRead > data.length) return nil;
        count = [self readIntegerFromData:data offset:offset bytesToRead:bytesToRead];
        *offset += bytesToRead;
    }
    
    // Security check: Ensure we have enough data remaining to satisfy the count.
    // Minimum size of a map entry is 2 bytes (1 key + 1 value).
    if (data.length - *offset < count * 2) {
        return nil;
    }
    
    NSMutableDictionary<CBORValue *, CBORValue *> *map = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < count; i++) {
        CBORValue *key = [self decodeInternal:data offset:offset depth:depth + 1];
        CBORValue *value = [self decodeInternal:data offset:offset depth:depth + 1];
        if (!key || !value) return nil;
        map[key] = value;
    }
    return [CBORValue map:map];
}

+ (CBORValue *)decodeTag:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset depth:(NSUInteger)depth {
    CBORValue *tagValue = [self decodeUnsignedInteger:additional data:data offset:offset];
    if (!tagValue) return nil;
    CBORValue *value = [self decodeInternal:data offset:offset depth:depth + 1];
    if (!value) return nil;
    return [CBORValue tag:tagValue.unsignedInteger.unsignedIntegerValue value:value];
}

+ (CBORValue *)decodeSimpleOrFloat:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
    // §3.4 (and §1.5 item 4): for simple-value additional-info values 24, 25,
    // 26, and 27, the simple value itself is encoded as the big-endian
    // unsigned integer (1/2/4/8 bytes respectively) immediately following the
    // additional-info byte. The previous code returned [CBORValue simple:additional]
    // without advancing the offset, so the 1-byte payload was re-read as the head
    // of the next CBOR item -- a structural desync that produces two records
    // from identical logical bytes.
    // Match test: CBORParserExploitTests/testSimpleValuePayloadAdvancesOffset.
    if (additional == 22) return [CBORValue nilValue];
    NSUInteger bytesToConsume;
    switch (additional) {
        case 24: bytesToConsume = 1; break;
        case 25: bytesToConsume = 2; break;
        case 26: bytesToConsume = 4; break;
        case 27: bytesToConsume = 8; break;
        default:
            // additional < 24: simple value, no payload.
            // additional >= 28: reserved/unassigned (28-30) or BREAK (31);
            // preserved as a no-payload simple value for backward compat.
            return [CBORValue simple:additional];
    }
    if (*offset + bytesToConsume > data.length) return nil;
    NSUInteger simpleValue = [self readIntegerFromData:data offset:offset
                                            bytesToRead:bytesToConsume];
    *offset += bytesToConsume;
    return [CBORValue simple:simpleValue];
}

+ (NSUInteger)bytesToReadForAdditional:(uint8_t)additional {
    if (additional == 24) return 1;
    if (additional == 25) return 2;
    if (additional == 26) return 4;
    if (additional == 27) return 8;
    return 0;
}

+ (NSUInteger)readIntegerFromData:(NSData *)data offset:(NSUInteger *)offset bytesToRead:(NSUInteger)bytesToRead {
    const uint8_t *bytes = data.bytes;
    uint64_t val = 0;
    for (NSUInteger i = 0; i < bytesToRead; i++) {
        val = (val << 8) | bytes[*offset + i];
    }
    return (NSUInteger)val;
}

@end
