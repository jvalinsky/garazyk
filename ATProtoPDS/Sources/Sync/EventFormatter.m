#import "Sync/EventFormatter.h"
#import "Sync/Firehose.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const EventFormatterErrorDomain = @"com.atproto.pds.eventformatter";
NSInteger const EventFormatterErrorCodeEncodingFailed = 5000;
NSInteger const EventFormatterErrorCodeDecodingFailed = 5001;

@implementation EventFormatter

- (NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event error:(NSError **)error {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];

    payload[@"kind"] = @"commit";
    payload[@"repo"] = event.repo;
    payload[@"commit"] = event.commit;

    if (event.previous) {
        payload[@"previous"] = event.previous;
    }

    payload[@"ops"] = event.ops ?: @[];

    if (event.blobs.count > 0) {
        payload[@"blobs"] = event.blobs;
    }

    return [self encodeEventWithKind:@"commit" payload:payload error:error];
}

- (NSData *)encodeIdentityEvent:(FirehoseIdentityEvent *)event error:(NSError **)error {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"kind"] = @"identity";
    payload[@"did"] = event.did;

    return [self encodeEventWithKind:@"identity" payload:payload error:error];
}

- (NSData *)encodeErrorEvent:(FirehoseErrorEvent *)event error:(NSError **)error {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"kind"] = @"error";
    payload[@"message"] = event.message;

    return [self encodeEventWithKind:@"error" payload:payload error:error];
}

- (NSData *)encodeEventWithKind:(NSString *)kind payload:(NSDictionary *)payload error:(NSError **)error {
    NSData *cborData = [self encodeCBORObject:payload error:error];
    if (!cborData) {
        return nil;
    }

    return cborData;
}

- (id)decodeEventFromData:(NSData *)data error:(NSError **)error {
    id cborObject = [self decodeCBORData:data error:error];
    if (!cborObject) {
        return nil;
    }

    if (![cborObject isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Expected dictionary in CBOR payload"}];
        }
        return nil;
    }

    NSDictionary *dict = (NSDictionary *)cborObject;
    NSString *kind = dict[@"kind"];

    if ([kind isEqualToString:@"commit"]) {
        FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
        event.repo = dict[@"repo"];
        event.commit = dict[@"commit"];
        event.previous = dict[@"previous"];
        event.ops = dict[@"ops"] ?: @[];
        event.blobs = dict[@"blobs"];
        return event;

    } else if ([kind isEqualToString:@"identity"]) {
        FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
        event.did = dict[@"did"];
        return event;

    } else if ([kind isEqualToString:@"error"]) {
        FirehoseErrorEvent *event = [[FirehoseErrorEvent alloc] init];
        event.message = dict[@"message"];
        return event;
    }

    return dict;
}

- (NSData *)encodeCBORObject:(id)object error:(NSError **)error {
    NSMutableData *data = [NSMutableData data];

    if ([object isKindOfClass:[NSString class]]) {
        [self encodeString:object toData:data];
    } else if ([object isKindOfClass:[NSNumber class]]) {
        [self encodeNumber:object toData:data];
    } else if ([object isKindOfClass:[NSArray class]]) {
        [self encodeArray:object toData:data];
    } else if ([object isKindOfClass:[NSDictionary class]]) {
        [self encodeDictionary:object toData:data];
    } else if ([object isKindOfClass:[NSData class]]) {
        [self encodeBytes:object toData:data];
    } else if ([object isKindOfClass:[NSNull class]]) {
        [data appendBytes:(uint8_t[]){0xF6} length:1];
    } else {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeEncodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported type for CBOR encoding"}];
        }
        return nil;
    }

    return data;
}

- (void)encodeString:(NSString *)string toData:(NSMutableData *)data {
    NSData *utf8Data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger length = utf8Data.length;

    uint8_t initialByte;
    if (length < 24) {
        initialByte = 0x60 | (uint8_t)length;
        [data appendBytes:&initialByte length:1];
    } else if (length < 256) {
        initialByte = 0x78;
        [data appendBytes:&initialByte length:1];
        uint8_t lenByte = (uint8_t)length;
        [data appendBytes:&lenByte length:1];
    } else if (length < 65536) {
        initialByte = 0x79;
        [data appendBytes:&initialByte length:1];
        uint8_t lenBytes[2] = { (length >> 8) & 0xFF, length & 0xFF };
        [data appendBytes:lenBytes length:2];
    } else {
        initialByte = 0x7A;
        [data appendBytes:&initialByte length:1];
        uint8_t lenBytes[4] = { (length >> 24) & 0xFF, (length >> 16) & 0xFF, (length >> 8) & 0xFF, length & 0xFF };
        [data appendBytes:lenBytes length:4];
    }

    [data appendData:utf8Data];
}

- (void)encodeNumber:(NSNumber *)number toData:(NSMutableData *)data {
    CFNumberType type = CFNumberGetType((CFNumberRef)number);
    if (CFGetTypeID((CFNumberRef)number) == CFBooleanGetTypeID()) {
        uint8_t byte = number.boolValue ? 0xF5 : 0xF4;
        [data appendBytes:&byte length:1];
        return;
    }

    if (type == kCFNumberCharType || type == kCFNumberSInt8Type || type == kCFNumberSInt16Type || type == kCFNumberSInt32Type || type == kCFNumberSInt64Type || type == kCFNumberShortType || type == kCFNumberIntType || type == kCFNumberLongType || type == kCFNumberLongLongType || type == kCFNumberNSIntegerType) {
        NSInteger intValue = number.integerValue;
        if (intValue < 0) {
            uint8_t bytes[9] = { 0x3B };
            int64_t val = -intValue - 1;
            for (int i = 7; i >= 0; i--) {
                bytes[i + 1] = val & 0xFF;
                val >>= 8;
            }
            [data appendBytes:bytes length:9];
            return;
        }
        uint64_t uvalue = (uint64_t)intValue;
        if (uvalue < 24) {
            uint8_t byte = (uint8_t)uvalue;
            [data appendBytes:&byte length:1];
        } else if (uvalue < 256) {
            uint8_t bytes[2] = { 0x18, (uint8_t)uvalue };
            [data appendBytes:bytes length:2];
        } else if (uvalue < 65536) {
            uint8_t bytes[3] = { 0x19, (uvalue >> 8) & 0xFF, uvalue & 0xFF };
            [data appendBytes:bytes length:3];
        } else if (uvalue < 4294967296ULL) {
            uint8_t bytes[5] = { 0x1A, (uvalue >> 24) & 0xFF, (uvalue >> 16) & 0xFF, (uvalue >> 8) & 0xFF, uvalue & 0xFF };
            [data appendBytes:bytes length:5];
        } else {
            uint8_t bytes[9] = { 0x1B };
            for (int i = 7; i >= 0; i--) {
                bytes[i + 1] = uvalue & 0xFF;
                uvalue >>= 8;
            }
            [data appendBytes:bytes length:9];
        }
    } else if (type == kCFNumberFloat32Type || type == kCFNumberFloat64Type || type == kCFNumberFloatType || kCFNumberDoubleType) {
        double doubleValue = number.doubleValue;
        uint8_t bytes[9] = { 0xFB };
        uint64_t val;
        memcpy(&val, &doubleValue, sizeof(double));
        for (int i = 7; i >= 0; i--) {
            bytes[i + 1] = val & 0xFF;
            val >>= 8;
        }
        [data appendBytes:bytes length:9];
    }
}

- (void)encodeArray:(NSArray *)array toData:(NSMutableData *)data {
    NSUInteger count = array.count;

    uint8_t initialByte;
    if (count < 16) {
        initialByte = 0x80 | (uint8_t)count;
        [data appendBytes:&initialByte length:1];
    } else if (count < 256) {
        uint8_t bytes[2] = { 0x98, (uint8_t)count };
        [data appendBytes:bytes length:2];
    } else if (count < 65536) {
        uint8_t bytes[3] = { 0x99, (count >> 8) & 0xFF, count & 0xFF };
        [data appendBytes:bytes length:3];
    } else {
        uint8_t bytes[5] = { 0x9A, (count >> 24) & 0xFF, (count >> 16) & 0xFF, (count >> 8) & 0xFF, count & 0xFF };
        [data appendBytes:bytes length:5];
    }

    for (id item in array) {
        NSError *error = nil;
        NSData *itemData = [self encodeCBORObject:item error:&error];
        if (itemData) {
            [data appendData:itemData];
        }
    }
}

- (void)encodeDictionary:(NSDictionary *)dict toData:(NSMutableData *)data {
    NSUInteger count = dict.count;

    uint8_t initialByte;
    if (count < 16) {
        initialByte = 0xA0 | (uint8_t)count;
        [data appendBytes:&initialByte length:1];
    } else if (count < 256) {
        uint8_t bytes[2] = { 0xB8, (uint8_t)count };
        [data appendBytes:bytes length:2];
    } else if (count < 65536) {
        uint8_t bytes[3] = { 0xB9, (count >> 8) & 0xFF, count & 0xFF };
        [data appendBytes:bytes length:3];
    } else {
        uint8_t bytes[5] = { 0xBA, (count >> 24) & 0xFF, (count >> 16) & 0xFF, (count >> 8) & 0xFF, count & 0xFF };
        [data appendBytes:bytes length:5];
    }

    NSArray *sortedKeys = [dict.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (id key in sortedKeys) {
        NSError *error = nil;
        NSData *keyData = [self encodeCBORObject:key error:&error];
        if (keyData) {
            [data appendData:keyData];
        }

        id value = dict[key];
        NSData *valueData = [self encodeCBORObject:value error:&error];
        if (valueData) {
            [data appendData:valueData];
        }
    }
}

- (void)encodeBytes:(NSData *)bytes toData:(NSMutableData *)data {
    NSUInteger length = bytes.length;

    uint8_t initialByte;
    if (length < 32) {
        initialByte = 0x40 | (uint8_t)length;
        [data appendBytes:&initialByte length:1];
    } else if (length < 256) {
        uint8_t bytes[2] = { 0x58, (uint8_t)length };
        [data appendBytes:bytes length:2];
    } else if (length < 65536) {
        uint8_t bytes[3] = { 0x59, (length >> 8) & 0xFF, length & 0xFF };
        [data appendBytes:bytes length:3];
    } else if (length < 4294967296) {
        uint8_t bytes[5] = { 0x5A, (length >> 24) & 0xFF, (length >> 16) & 0xFF, (length >> 8) & 0xFF, length & 0xFF };
        [data appendBytes:bytes length:5];
    } else {
        uint8_t bytes[9] = { 0x5B };
        uint64_t len = length;
        for (int i = 7; i >= 0; i--) {
            bytes[i + 1] = len & 0xFF;
            len >>= 8;
        }
        [data appendBytes:bytes length:9];
    }

    [data appendData:bytes];
}

- (id)decodeCBORData:(NSData *)data error:(NSError **)error {
    if (data.length == 0) {
        return nil;
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger index = 0;

    return [self decodeCBORFromBytes:bytes length:data.length index:&index error:error];
}

- (id)decodeCBORFromBytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index error:(NSError **)error {
    if (*index >= length) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unexpected end of CBOR data"}];
        }
        return nil;
    }

    uint8_t initialByte = bytes[*index];
    (*index)++;

    uint8_t majorType = (initialByte >> 5) & 0x7;
    uint8_t additionalInfo = initialByte & 0x1F;

    id decoded = nil;
    switch (majorType) {
        case 0:
            decoded = [self decodeUnsignedInteger:additionalInfo bytes:bytes length:length index:index];
            break;

        case 1:
            decoded = [self decodeNegativeInteger:additionalInfo bytes:bytes length:length index:index];
            break;

        case 2:
            decoded = [self decodeByteString:additionalInfo bytes:bytes length:length index:index];
            break;

        case 3:
            decoded = [self decodeTextString:additionalInfo bytes:bytes length:length index:index];
            break;

        case 4:
            decoded = [self decodeArray:additionalInfo bytes:bytes length:length index:index error:error];
            break;

        case 5:
            decoded = [self decodeMap:additionalInfo bytes:bytes length:length index:index error:error];
            break;

        case 7:
            decoded = [self decodeSpecial:additionalInfo bytes:bytes length:length index:index];
            break;

        default:
            if (error) {
                *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                             code:EventFormatterErrorCodeDecodingFailed
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown CBOR major type: %u", majorType]}];
            }
            return nil;
    }

    if (!decoded && error && !*error) {
        *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                     code:EventFormatterErrorCodeDecodingFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"Unexpected end of CBOR data"}];
    }

    return decoded;
}

- (NSNumber *)decodeUnsignedInteger:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index {
    uint64_t value = 0;

    if (additionalInfo < 24) {
        value = additionalInfo;
    } else if (additionalInfo == 24) {
        if (*index >= length) return nil;
        value = bytes[*index];
        (*index)++;
    } else if (additionalInfo == 25) {
        if (*index + 1 >= length) return nil;
        value = (uint64_t)bytes[*index] << 8 | bytes[*index + 1];
        *index += 2;
    } else if (additionalInfo == 26) {
        if (*index + 3 >= length) return nil;
        value = ((uint64_t)bytes[*index] << 24) | ((uint64_t)bytes[*index + 1] << 16) |
                ((uint64_t)bytes[*index + 2] << 8) | bytes[*index + 3];
        *index += 4;
    } else if (additionalInfo == 27) {
        if (*index + 7 >= length) return nil;
        value = 0;
        for (int i = 0; i < 8; i++) {
            value = (value << 8) | bytes[*index + i];
        }
        *index += 8;
    }

    return @(value);
}

- (NSNumber *)decodeNegativeInteger:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index {
    NSNumber *unsignedValue = [self decodeUnsignedInteger:additionalInfo bytes:bytes length:length index:index];
    if (!unsignedValue) return nil;
    return @(-(int64_t)(unsignedValue.unsignedLongLongValue + 1));
}

- (NSData *)decodeByteString:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index {
    uint64_t byteLength = 0;

    if (additionalInfo < 24) {
        byteLength = additionalInfo;
    } else if (additionalInfo == 24) {
        if (*index >= length) return nil;
        byteLength = bytes[*index];
        (*index)++;
    } else if (additionalInfo == 25) {
        if (*index + 1 >= length) return nil;
        byteLength = (uint64_t)bytes[*index] << 8 | bytes[*index + 1];
        *index += 2;
    } else if (additionalInfo == 26) {
        if (*index + 3 >= length) return nil;
        byteLength = ((uint64_t)bytes[*index] << 24) | ((uint64_t)bytes[*index + 1] << 16) |
                     ((uint64_t)bytes[*index + 2] << 8) | bytes[*index + 3];
        *index += 4;
    } else if (additionalInfo == 27) {
        if (*index + 7 >= length) return nil;
        byteLength = 0;
        for (int i = 0; i < 8; i++) {
            byteLength = (byteLength << 8) | bytes[*index + i];
        }
        *index += 8;
    }

    if (*index > length || *index + byteLength > length) return nil;

    NSData *result = [NSData dataWithBytes:bytes + *index length:byteLength];
    *index += byteLength;

    return result;
}

- (NSString *)decodeTextString:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index {
    NSData *byteData = [self decodeByteString:additionalInfo bytes:bytes length:length index:index];
    if (!byteData) return nil;
    return [[NSString alloc] initWithData:byteData encoding:NSUTF8StringEncoding];
}

- (NSArray *)decodeArray:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index error:(NSError **)error {
    uint64_t arrayLength = 0;

    if (additionalInfo < 24) {
        arrayLength = additionalInfo;
    } else if (additionalInfo == 24) {
        if (*index < length) arrayLength = bytes[*index];
        (*index)++;
    } else if (additionalInfo == 25) {
        if (*index + 1 < length) {
            arrayLength = (uint64_t)bytes[*index] << 8 | bytes[*index + 1];
            *index += 2;
        }
    } else if (additionalInfo == 26) {
        if (*index + 3 < length) {
            arrayLength = ((uint64_t)bytes[*index] << 24) | ((uint64_t)bytes[*index + 1] << 16) |
                         ((uint64_t)bytes[*index + 2] << 8) | bytes[*index + 3];
            *index += 4;
        }
    } else if (additionalInfo == 27) {
        if (*index + 7 < length) {
            arrayLength = 0;
            for (int i = 0; i < 8; i++) {
                arrayLength = (arrayLength << 8) | bytes[*index + i];
            }
            *index += 8;
        }
    }

    NSMutableArray *array = [NSMutableArray arrayWithCapacity:arrayLength];
    for (uint64_t i = 0; i < arrayLength; i++) {
        id item = [self decodeCBORFromBytes:bytes length:length index:index error:error];
        if (item) {
            [array addObject:item];
        } else {
            break;
        }
    }

    return array;
}

- (NSDictionary *)decodeMap:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index error:(NSError **)error {
    uint64_t mapLength = 0;

    if (additionalInfo < 16) {
        mapLength = additionalInfo;
    } else if (additionalInfo == 24) {
        if (*index < length) mapLength = bytes[*index];
        (*index)++;
    } else if (additionalInfo == 25) {
        if (*index + 1 < length) {
            mapLength = (uint64_t)bytes[*index] << 8 | bytes[*index + 1];
            *index += 2;
        }
    } else if (additionalInfo == 26) {
        if (*index + 3 < length) {
            mapLength = ((uint64_t)bytes[*index] << 24) | ((uint64_t)bytes[*index + 1] << 16) |
                         ((uint64_t)bytes[*index + 2] << 8) | bytes[*index + 3];
            *index += 4;
        }
    } else if (additionalInfo == 27) {
        if (*index + 7 < length) {
            mapLength = 0;
            for (int i = 0; i < 8; i++) {
                mapLength = (mapLength << 8) | bytes[*index + i];
            }
            *index += 8;
        }
    }

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (uint64_t i = 0; i < mapLength; i++) {
        id key = [self decodeCBORFromBytes:bytes length:length index:index error:error];
        if (!key) break;

        id value = [self decodeCBORFromBytes:bytes length:length index:index error:error];
        if (!value) break;

        dict[key] = value;
    }

    return dict;
}

- (id)decodeSpecial:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index {
    switch (additionalInfo) {
        case 20:
            return @NO;
        case 21:
            return @YES;
        case 22:
            return [NSNull null];
        case 23:
            return nil;
        default:
            return nil;
    }
}

@end
