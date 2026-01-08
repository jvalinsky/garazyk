#import "Repository/CBOR.h"

#pragma mark - CBORValue Implementation

@implementation CBORValue

+ (instancetype)unsignedInteger:(NSUInteger)value {
    return [[self alloc] initWithUnsignedInteger:@(value)];
}

+ (instancetype)negativeInteger:(NSInteger)value {
    return [[self alloc] initWithNegativeInteger:@(value)];
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
            return [self.tag isEqualToNumber:other.tag];
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

- (NSUInteger)hash {
    NSUInteger result = self.type;
    switch (self.type) {
        case CBORTypeUnsignedInteger:
            result ^= [self.unsignedInteger hash];
            break;
        case CBORTypeNegativeInteger:
            result ^= [self.negativeInteger hash];
            break;
        case CBORTypeByteString:
            result ^= [self.byteString hash];
            break;
        case CBORTypeTextString:
            result ^= [self.textString hash];
            break;
        case CBORTypeArray:
            result ^= [self.array hash];
            break;
        case CBORTypeMap:
            result ^= [self.map hash];
            break;
        case CBORTypeTag:
            result ^= [self.tag hash];
            break;
        case CBORTypeSimpleOrFloat:
            if (self.simpleValue) {
                result ^= [self.simpleValue hash];
            } else if (self.floatValue) {
                result ^= [@(self.floatValue.doubleValue) hash];
            }
            break;
    }
    return result;
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
            [self encodeTag:value.tag.unsignedIntegerValue value:value toData:data];
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
    if (count < 24) {
        uint8_t byte = majorType | (uint8_t)count;
        [data appendBytes:&byte length:1];
    } else if (count < 256) {
        uint8_t major = majorType | 24;
        [data appendBytes:&major length:1];
        uint8_t len = (uint8_t)count;
        [data appendBytes:&len length:1];
    } else if (count < 65536) {
        uint8_t major = majorType | 25;
        [data appendBytes:&major length:1];
        uint16_t be = OSSwapHostToBigInt16((uint16_t)count);
        [data appendBytes:&be length:2];
    } else {
        uint8_t major = majorType | 26;
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

    if (unsignedValue < 24) {
        uint8_t byte = 0x20 | (uint8_t)unsignedValue;
        [data appendBytes:&byte length:1];
    } else if (unsignedValue < 256) {
        uint8_t major = 0x38;
        [data appendBytes:&major length:1];
        uint8_t byte = (uint8_t)unsignedValue;
        [data appendBytes:&byte length:1];
    } else if (unsignedValue < 65536) {
        uint8_t major = 0x39;
        [data appendBytes:&major length:1];
        uint16_t be = OSSwapHostToBigInt16((uint16_t)unsignedValue);
        [data appendBytes:&be length:2];
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
    for (CBORValue *key in map) {
        [self encodeValue:key toData:output];
        [self encodeValue:map[key] toData:output];
    }
}

+ (void)encodeTag:(NSUInteger)tag value:(CBORValue *)value toData:(NSMutableData *)data {
    [self encodeUnsignedInteger:tag toData:data];
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

    switch (majorType) {
        case 0:
            return [self decodeUnsignedInteger:additional data:data offset:offset];
        case 1:
            return [self decodeNegativeInteger:additional data:data offset:offset];
        case 2:
            return [self decodeByteString:additional data:data offset:offset];
        case 3:
            return [self decodeTextString:additional data:data offset:offset];
        case 4:
            return [self decodeArray:additional data:data offset:offset];
        case 5:
            return [self decodeMap:additional data:data offset:offset];
        case 6:
            return [self decodeTag:additional data:data offset:offset];
        case 7:
            return [self decodeSimpleOrFloat:additional data:data offset:offset];
        default:
            return nil;
    }
}

+ (CBORValue *)decodeUnsignedInteger:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
    NSUInteger value = 0;

    if (additional < 24) {
        value = additional;
    } else {
        NSUInteger bytesToRead = [self bytesToReadForAdditional:additional];
        if (bytesToRead == 0 || *offset + bytesToRead > data.length) {
            return nil;
        }
        value = [self readIntegerFromData:data offset:offset bytesToRead:bytesToRead];
        *offset += bytesToRead;
    }

    return [CBORValue unsignedInteger:value];
}

+ (CBORValue *)decodeNegativeInteger:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
    CBORValue *unsignedValue = [self decodeUnsignedInteger:additional data:data offset:offset];
    if (!unsignedValue) {
        return nil;
    }
    NSInteger value = -(NSInteger)(unsignedValue.unsignedInteger.unsignedIntegerValue + 1);
    return [CBORValue negativeInteger:value];
}

+ (CBORValue *)decodeByteString:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
    NSUInteger length = 0;

    if (additional < 24) {
        length = additional;
    } else {
        NSUInteger bytesToRead = 0;
        switch (additional) {
            case 24: bytesToRead = 1; break;
            case 25: bytesToRead = 2; break;
            case 26: bytesToRead = 4; break;
            default: return nil;
        }

        if (*offset + bytesToRead > data.length) {
            return nil;
        }

        const uint8_t *bytes = data.bytes;
        switch (bytesToRead) {
            case 1:
                length = bytes[*offset];
                break;
            case 2: {
                uint16_t be;
                memcpy(&be, bytes + *offset, 2);
                length = OSSwapBigToHostInt16(be);
                break;
            }
            case 4: {
                uint32_t be;
                memcpy(&be, bytes + *offset, 4);
                length = OSSwapBigToHostInt32(be);
                break;
            }
        }
        *offset += bytesToRead;
    }

    if (*offset + length > data.length) {
        return nil;
    }

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
        if (bytesToRead == 0 || bytesToRead > 4 || *offset + bytesToRead > data.length) {
            return nil;
        }
        length = [self readIntegerFromData:data offset:offset bytesToRead:bytesToRead];
        *offset += bytesToRead;
    }

    if (*offset + length > data.length) {
        return nil;
    }

    NSData *valueData = [data subdataWithRange:NSMakeRange(*offset, length)];
    *offset += length;

    NSString *value = [[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding];
    if (!value) {
        value = [[NSString alloc] initWithData:valueData encoding:NSISOLatin1StringEncoding];
    }
    if (!value) {
        return nil;
    }

    return [CBORValue textString:value];
}

+ (CBORValue *)decodeArray:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
    NSUInteger count = 0;

    if (additional < 24) {
        count = additional;
    } else {
        NSUInteger bytesToRead = [self bytesToReadForAdditional:additional];
        if (bytesToRead == 0 || *offset + bytesToRead > data.length) {
            return nil;
        }
        count = [self readCountFromData:data offset:offset bytesToRead:bytesToRead];
        *offset += bytesToRead;
    }

    NSMutableArray<CBORValue *> *array = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        CBORValue *value = [self decode:data offset:offset];
        if (!value) {
            return nil;
        }
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
        if (bytesToRead == 0 || *offset + bytesToRead > data.length) {
            return nil;
        }
        count = [self readCountFromData:data offset:offset bytesToRead:bytesToRead];
        *offset += bytesToRead;
    }

    NSMutableDictionary<CBORValue *, CBORValue *> *map = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < count; i++) {
        CBORValue *key = [self decode:data offset:offset];
        if (!key) {
            return nil;
        }
        CBORValue *value = [self decode:data offset:offset];
        if (!value) {
            return nil;
        }
        map[key] = value;
    }

    return [CBORValue map:map];
}

+ (CBORValue *)decodeTag:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
    CBORValue *tagValue = [self decodeUnsignedInteger:additional data:data offset:offset];
    if (!tagValue) {
        return nil;
    }

    CBORValue *value = [self decode:data offset:offset];
    if (!value) {
        return nil;
    }

    return [CBORValue tag:tagValue.unsignedInteger.unsignedIntegerValue value:value];
}

+ (CBORValue *)decodeSimpleOrFloat:(uint8_t)additional data:(NSData *)data offset:(NSUInteger *)offset {
    if (additional < 20) {
        return [CBORValue simple:additional];
    } else if (additional == 20) {
        return [CBORValue simple:20];
    } else if (additional == 21) {
        return [CBORValue simple:21];
    } else if (additional == 22) {
        return [CBORValue nilValue];
    } else if (additional == 23) {
        return [CBORValue simple:23];
    } else if (additional == 24) {
        if (*offset >= data.length) {
            return nil;
        }
        const uint8_t *bytes = data.bytes;
        uint8_t simple = bytes[*offset];
        (*offset)++;
        return [CBORValue simple:simple];
    } else if (additional == 25) {
        if (*offset + 2 > data.length) {
            return nil;
        }
        const uint8_t *bytes = data.bytes;
        uint16_t be;
        memcpy(&be, bytes + *offset, 2);
        float value = OSSwapBigToHostInt16(be);
        *offset += 2;
        return [CBORValue floatingPoint:value];
    } else if (additional == 26) {
        if (*offset + 4 > data.length) {
            return nil;
        }
        const uint8_t *bytes = data.bytes;
        uint32_t be;
        memcpy(&be, bytes + *offset, 4);
        float value = OSSwapBigToHostInt32(be);
        *offset += 4;
        return [CBORValue floatingPoint:value];
    } else if (additional == 27) {
        if (*offset + 8 > data.length) {
            return nil;
        }
        const uint8_t *bytes = data.bytes;
        uint64_t be;
        memcpy(&be, bytes + *offset, 8);
        double value = (double)be;
        *offset += 8;
        return [CBORValue floatingPoint:value];
    }

    return nil;
}

+ (NSUInteger)bytesToReadForAdditional:(uint8_t)additional {
    switch (additional) {
        case 24: return 1;
        case 25: return 2;
        case 26: return 4;
        case 27: return 8;
        default: return 0;
    }
}

+ (NSUInteger)readIntegerFromData:(NSData *)data offset:(NSUInteger *)offset bytesToRead:(NSUInteger)bytesToRead {
    const uint8_t *bytes = data.bytes;
    switch (bytesToRead) {
        case 1:
            return bytes[*offset];
        case 2: {
            uint16_t be;
            memcpy(&be, bytes + *offset, 2);
            return OSSwapBigToHostInt16(be);
        }
        case 4: {
            uint32_t be;
            memcpy(&be, bytes + *offset, 4);
            return OSSwapBigToHostInt32(be);
        }
        case 8: {
            uint64_t be;
            memcpy(&be, bytes + *offset, 8);
            return be;
        }
        default:
            return 0;
    }
}

+ (NSUInteger)readCountFromData:(NSData *)data offset:(NSUInteger *)offset bytesToRead:(NSUInteger)bytesToRead {
    const uint8_t *bytes = data.bytes;
    switch (bytesToRead) {
        case 1:
            return bytes[*offset];
        case 2: {
            uint16_t be;
            memcpy(&be, bytes + *offset, 2);
            return OSSwapBigToHostInt16(be);
        }
        case 4: {
            uint32_t be;
            memcpy(&be, bytes + *offset, 4);
            return OSSwapBigToHostInt32(be);
        }
        default:
            return 0;
    }
}

@end
