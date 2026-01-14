#import "Repository/CBOR.h"
#import <Security/Security.h>

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
    } else {
        major |= 26;
        [data appendBytes:&major length:1];
        uint32_t be = OSSwapHostToBigInt32((uint32_t)count);
        [data appendBytes:&be length:4];
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
    NSUInteger unsignedValue;
    if (value == NSIntegerMin) {
        unsignedValue = 18446744073709551615ULL;
    } else {
        unsignedValue = (NSUInteger)(-(value + 1));
    }

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
        NSUInteger len1 = d1.length;
        NSUInteger len2 = d2.length;
        NSUInteger len = MIN(len1, len2);
        int cmp = memcmp(d1.bytes, d2.bytes, len);
        if (cmp != 0) return cmp < 0 ? NSOrderedAscending : NSOrderedDescending;
        if (len1 < len2) return NSOrderedAscending;
        if (len1 > len2) return NSOrderedDescending;
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
    NSUInteger offset = 0;
    return [self decode:data offset:&offset];
}

+ (CBORValue *)decode:(NSData *)data offset:(NSUInteger *)offset {
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
        case 4: result = [self decodeArray:additional data:data offset:offset]; break;
        case 5: result = [self decodeMap:additional data:data offset:offset]; break;
        case 6: result = [self decodeTag:additional data:data offset:offset]; break;
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
    NSInteger value = -(NSInteger)(unsignedValue.unsignedInteger.unsignedIntegerValue + 1);
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
    if (*offset + length > data.length) return nil;
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
    if (*offset + length > data.length) return nil;
    NSData *valueData = [data subdataWithRange:NSMakeRange(*offset, length)];
    *offset += length;
    NSString *value = [[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding];
    return [CBORValue textString:value ?: @""];
}

+ (CBORValue *)decodeArray:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
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
        CBORValue *value = [self decode:data offset:offset];
        if (!value) return nil;
        [array addObject:value];
    }
    return [CBORValue array:array];
}

+ (CBORValue *)decodeMap:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
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
        CBORValue *key = [self decode:data offset:offset];
        CBORValue *value = [self decode:data offset:offset];
        if (!key || !value) return nil;
        map[key] = value;
    }
    return [CBORValue map:map];
}

+ (CBORValue *)decodeTag:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
    CBORValue *tagValue = [self decodeUnsignedInteger:additional data:data offset:offset];
    if (!tagValue) return nil;
    CBORValue *value = [self decode:data offset:offset];
    if (!value) return nil;
    return [CBORValue tag:tagValue.unsignedInteger.unsignedIntegerValue value:value];
}

+ (CBORValue *)decodeSimpleOrFloat:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
    if (additional == 22) return [CBORValue nilValue];
    return [CBORValue simple:additional];
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
