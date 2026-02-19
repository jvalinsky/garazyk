#import "Sync/EventFormatter.h"
#import "Sync/Firehose.h"
#import "Core/ATProtoDagCBOR.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const EventFormatterErrorDomain = @"com.atproto.pds.eventformatter";
NSInteger const EventFormatterErrorCodeEncodingFailed = 5000;
NSInteger const EventFormatterErrorCodeDecodingFailed = 5001;

static const uint8_t kXRPCStreamOpMessage = 1;
static const uint8_t kXRPCStreamOpErrorFrame = 0x20;

@implementation EventFormatter

- (NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event error:(NSError **)error {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    
    // Required fields per com.atproto.sync.subscribeRepos#commit
    payload[@"seq"] = @(event.seq);
    payload[@"rebase"] = @(event.rebase);
    payload[@"tooBig"] = @(event.tooBig);
    payload[@"repo"] = event.repo;
    payload[@"commit"] = event.commit;  // CID object - will encode as tag 42
    payload[@"rev"] = event.rev;
    payload[@"since"] = event.since ?: [NSNull null];
    payload[@"blocks"] = event.blocks ?: [NSData data];
    
    // Sanitize ops to remove recordCBOR which is internal-only and huge
    // Per ATProto spec, the record data is in the blocks (CAR), not in the ops metadata
    NSMutableArray *sanitizedOps = [NSMutableArray arrayWithCapacity:event.ops.count];
    for (NSDictionary *op in event.ops) {
        if (op[@"recordCBOR"]) {
            NSMutableDictionary *cleanOp = [op mutableCopy];
            [cleanOp removeObjectForKey:@"recordCBOR"];
            [sanitizedOps addObject:cleanOp];
        } else {
            [sanitizedOps addObject:op];
        }
    }
    payload[@"ops"] = sanitizedOps;
    
    payload[@"blobs"] = event.blobs ?: @[];  // Array of CIDs
    payload[@"time"] = event.time ?: @"";  // RFC-3339 timestamp
    
    if (event.prevData) {
        payload[@"prevData"] = event.prevData;  // CID object - will encode as tag 42
    }

    return [self encodeStreamEventWithType:@"#commit" payload:payload error:error];
}

- (NSData *)encodeIdentityEvent:(FirehoseIdentityEvent *)event error:(NSError **)error {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"seq"] = @(event.seq);
    payload[@"did"] = event.did;
    payload[@"time"] = event.time ?: @"";

    if (event.handle) {
        payload[@"handle"] = event.handle;
    }

    return [self encodeStreamEventWithType:@"#identity" payload:payload error:error];
}

- (NSData *)encodeAccountEvent:(FirehoseAccountEvent *)event error:(NSError **)error {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"seq"] = @(event.seq);
    payload[@"did"] = event.did;
    payload[@"active"] = @(event.active);
    payload[@"time"] = event.time ?: @"";

    if (event.status) {
        payload[@"status"] = event.status;
    }

    return [self encodeStreamEventWithType:@"#account" payload:payload error:error];
}

- (NSData *)encodeInfoEvent:(FirehoseInfoEvent *)event error:(NSError **)error {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"name"] = event.kind ?: @"";
    if (event.message.length > 0) {
        payload[@"message"] = event.message;
    }

    return [self encodeStreamEventWithType:@"#info" payload:payload error:error];
}

- (NSData *)encodeErrorEvent:(FirehoseErrorEvent *)event error:(NSError **)error {
    NSMutableDictionary *header = [NSMutableDictionary dictionary];
    header[@"op"] = @(-1);

    NSMutableDictionary *errorFrame = [NSMutableDictionary dictionary];
    NSString *errorCode = event.error.length > 0 ? event.error : event.message;
    errorFrame[@"error"] = errorCode.length > 0 ? errorCode : @"UnknownError";
    if (event.message.length > 0) {
        errorFrame[@"message"] = event.message;
    }

    NSMutableData *result = [NSMutableData data];
    
    NSData *headerData = [ATProtoDagCBOR encodeObject:header error:error];
    if (!headerData) return nil;
    [result appendData:headerData];

    NSData *cborData = [ATProtoDagCBOR encodeObject:errorFrame error:error];
    if (!cborData) return nil;
    [result appendData:cborData];

    return result;
}

- (NSData *)encodeStreamEventWithType:(NSString *)msgType payload:(NSDictionary *)payload error:(NSError **)error {
    NSMutableData *result = [NSMutableData data];

    NSMutableDictionary *header = [NSMutableDictionary dictionary];
    header[@"op"] = @(kXRPCStreamOpMessage);
    header[@"t"] = msgType;

    NSData *headerData = [ATProtoDagCBOR encodeObject:header error:error];
    if (!headerData) {
        return nil;
    }
    [result appendData:headerData];

    NSData *payloadData = [ATProtoDagCBOR encodeObject:payload error:error];
    if (!payloadData) {
        if (error) {
             // Retain original error if set
        }
        return nil;
    }
    [result appendData:payloadData];
    
    // Enforce 1MB size limit (1024 * 1024 bytes)
    if (result.length > 1024 * 1024) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeEncodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Event size %lu exceeds 1MB limit", (unsigned long)result.length]}];
        }
        return nil;
    }

    return result;
}

- (NSDictionary *)decodeEventFromData:(NSData *)data op:(NSInteger *)op msgType:(NSString **)msgType error:(NSError **)error {
    if (data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty event data"}];
        }
        return nil;
    }

    // XRPC stream frames are two concatenated CBOR objects: Header and Payload
    NSUInteger index = 0;
    id decodedHeader = [self decodeCBORFromBytes:data.bytes length:data.length index:&index error:error];
    if (![decodedHeader isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid XRPC frame header"}];
        }
        return nil;
    }
    
    NSDictionary *header = (NSDictionary *)decodedHeader;
    NSInteger opValue = [header[@"op"] integerValue];
    if (op) *op = opValue;
    
    if (opValue == -1) {
        if (msgType) *msgType = @"#error";
    } else {
        if (msgType) *msgType = header[@"t"];
    }
    
    if (index >= data.length) return nil;
    
    NSData *bodyData = [data subdataWithRange:NSMakeRange(index, data.length - index)];
    return [ATProtoDagCBOR decodeData:bodyData error:error];
}

#pragma mark - Minimal CBOR Decoding helpers (for splitting concatenated frames)

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
    if (additionalInfo < 24) {
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
        case 20: return @NO;
        case 21: return @YES;
        case 22: return [NSNull null];
        case 23: return nil;
        default: return nil;
    }
}

@end
