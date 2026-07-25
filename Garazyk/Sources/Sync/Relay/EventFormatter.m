// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/EventFormatter.h"
#import "Sync/Firehose/Firehose.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import "Debug/GZLogger.h"

NSString * const EventFormatterErrorDomain = @"com.atproto.pds.eventformatter";
NSInteger const EventFormatterErrorCodeEncodingFailed = 5000;
NSInteger const EventFormatterErrorCodeDecodingFailed = 5001;

static const uint8_t kXRPCStreamOpMessage = 1;
static const NSUInteger kEventFormatterMaxFrameBytes = 1024 * 1024;
static const uint64_t kEventFormatterMaxContainerItems = 4096;
static const NSUInteger kEventFormatterMaxNestingDepth = 32;

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

- (NSData *)encodeSyncEvent:(FirehoseSyncEvent *)event error:(NSError **)error {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"seq"] = @(event.seq);
    payload[@"did"] = event.did;
    payload[@"blocks"] = event.blocks ?: [NSData data];
    payload[@"rev"] = event.rev ?: @"";
    payload[@"time"] = event.time ?: @"";

    return [self encodeStreamEventWithType:@"#sync" payload:payload error:error];
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
        GZ_LOG_SYNC_ERROR(@"encodeStreamEventWithType: failed to encode payload for msgType %@: %@", msgType, error ? *error : @"unknown error");
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
    if (data.length > kEventFormatterMaxFrameBytes) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Event exceeds the maximum frame size"}];
        }
        return nil;
    }

    // XRPC stream frames are two concatenated CBOR objects: Header and Payload
    NSUInteger index = 0;
    id decodedHeader = [self decodeCBORFromBytes:data.bytes
                                          length:data.length
                                           index:&index
                                           depth:0
                                           error:error];
    if (![decodedHeader isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid XRPC frame header"}];
        }
        return nil;
    }
    
    NSDictionary *header = (NSDictionary *)decodedHeader;
    NSNumber *opNumber = [header[@"op"] isKindOfClass:[NSNumber class]]
        ? header[@"op"]
        : nil;
    NSString *headerType = [header[@"t"] isKindOfClass:[NSString class]]
        ? header[@"t"]
        : nil;
    if (!opNumber ||
        (opNumber.integerValue != XRPCStreamOpKindErrorFrame &&
         opNumber.integerValue != XRPCStreamOpKindMessage) ||
        (opNumber.integerValue == XRPCStreamOpKindMessage &&
         headerType.length == 0)) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Invalid XRPC frame header fields"}];
        }
        return nil;
    }

    NSInteger opValue = opNumber.integerValue;
    if (op) *op = opValue;
    
    if (opValue == -1) {
        if (msgType) *msgType = @"#error";
    } else {
        if (msgType) *msgType = headerType;
    }
    
    if (index >= data.length) return nil;

    id body = [self decodeCBORFromBytes:data.bytes
                                 length:data.length
                                  index:&index
                                  depth:0
                                  error:error];
    if (![body isKindOfClass:[NSDictionary class]] ||
        index != data.length) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Invalid XRPC frame body"}];
        }
        return nil;
    }
    return body;
}

#pragma mark - Minimal CBOR Decoding helpers (for splitting concatenated frames)

- (id)decodeCBORFromBytes:(const uint8_t *)bytes
                   length:(NSUInteger)length
                    index:(NSUInteger *)index
                    depth:(NSUInteger)depth
                    error:(NSError **)error {
    if (depth > kEventFormatterMaxNestingDepth) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"CBOR nesting depth exceeds limit"}];
        }
        return nil;
    }
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
            decoded = [self decodeArray:additionalInfo
                                  bytes:bytes
                                 length:length
                                  index:index
                                  depth:depth
                                  error:error];
            break;
        case 5:
            decoded = [self decodeMap:additionalInfo
                                bytes:bytes
                               length:length
                                index:index
                                depth:depth
                                error:error];
            break;
        case 6:
            decoded = [self decodeTag:additionalInfo
                                bytes:bytes
                               length:length
                                index:index
                                depth:depth
                                error:error];
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
    } else {
        return nil;
    }
    return @(value);
}

- (NSNumber *)decodeNegativeInteger:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index {
    NSNumber *unsignedValue = [self decodeUnsignedInteger:additionalInfo bytes:bytes length:length index:index];
    if (!unsignedValue) return nil;
    uint64_t magnitude = unsignedValue.unsignedLongLongValue;
    if (magnitude > INT64_MAX) {
        return nil;
    }
    if (magnitude == INT64_MAX) {
        return @(INT64_MIN);
    }
    return @(-((int64_t)magnitude + 1));
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
    } else {
        return nil;
    }
    if (byteLength > kEventFormatterMaxFrameBytes ||
        *index > length ||
        byteLength > (uint64_t)(length - *index)) {
        return nil;
    }
    NSUInteger boundedLength = (NSUInteger)byteLength;
    NSData *result = [NSData dataWithBytes:bytes + *index length:boundedLength];
    *index += boundedLength;
    return result;
}

- (NSString *)decodeTextString:(uint8_t)additionalInfo bytes:(const uint8_t *)bytes length:(NSUInteger)length index:(NSUInteger *)index {
    NSData *byteData = [self decodeByteString:additionalInfo bytes:bytes length:length index:index];
    if (!byteData) return nil;
    return [[NSString alloc] initWithData:byteData encoding:NSUTF8StringEncoding];
}

- (NSArray *)decodeArray:(uint8_t)additionalInfo
                   bytes:(const uint8_t *)bytes
                  length:(NSUInteger)length
                   index:(NSUInteger *)index
                   depth:(NSUInteger)depth
                   error:(NSError **)error {
    uint64_t arrayLength = 0;
    if (additionalInfo < 24) {
        arrayLength = additionalInfo;
    } else if (additionalInfo == 24) {
        if (*index >= length) return nil;
        arrayLength = bytes[*index];
        (*index)++;
    } else if (additionalInfo == 25) {
        if (*index + 1 >= length) return nil;
        arrayLength = (uint64_t)bytes[*index] << 8 | bytes[*index + 1];
        *index += 2;
    } else if (additionalInfo == 26) {
        if (*index + 3 >= length) return nil;
        arrayLength = ((uint64_t)bytes[*index] << 24) | ((uint64_t)bytes[*index + 1] << 16) |
                     ((uint64_t)bytes[*index + 2] << 8) | bytes[*index + 3];
        *index += 4;
    } else if (additionalInfo == 27) {
        if (*index + 7 >= length) return nil;
        arrayLength = 0;
        for (int i = 0; i < 8; i++) {
            arrayLength = (arrayLength << 8) | bytes[*index + i];
        }
        *index += 8;
    } else {
        return nil;
    }
    if (arrayLength > kEventFormatterMaxContainerItems) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"CBOR array exceeds item limit"}];
        }
        return nil;
    }
    NSMutableArray *array =
        [NSMutableArray arrayWithCapacity:(NSUInteger)arrayLength];
    for (uint64_t i = 0; i < arrayLength; i++) {
        id item = [self decodeCBORFromBytes:bytes
                                     length:length
                                      index:index
                                      depth:depth + 1
                                      error:error];
        if (item) {
            [array addObject:item];
        } else {
            return nil;
        }
    }
    return array;
}

- (NSDictionary *)decodeMap:(uint8_t)additionalInfo
                      bytes:(const uint8_t *)bytes
                     length:(NSUInteger)length
                      index:(NSUInteger *)index
                      depth:(NSUInteger)depth
                      error:(NSError **)error {
    uint64_t mapLength = 0;
    if (additionalInfo < 24) {
        mapLength = additionalInfo;
    } else if (additionalInfo == 24) {
        if (*index >= length) return nil;
        mapLength = bytes[*index];
        (*index)++;
    } else if (additionalInfo == 25) {
        if (*index + 1 >= length) return nil;
        mapLength = (uint64_t)bytes[*index] << 8 | bytes[*index + 1];
        *index += 2;
    } else if (additionalInfo == 26) {
        if (*index + 3 >= length) return nil;
        mapLength = ((uint64_t)bytes[*index] << 24) | ((uint64_t)bytes[*index + 1] << 16) |
                    ((uint64_t)bytes[*index + 2] << 8) | bytes[*index + 3];
        *index += 4;
    } else if (additionalInfo == 27) {
        if (*index + 7 >= length) return nil;
        mapLength = 0;
        for (int i = 0; i < 8; i++) {
            mapLength = (mapLength << 8) | bytes[*index + i];
        }
        *index += 8;
    } else {
        return nil;
    }
    if (mapLength > kEventFormatterMaxContainerItems) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"CBOR map exceeds item limit"}];
        }
        return nil;
    }
    NSMutableDictionary *dict =
        [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)mapLength];
    for (uint64_t i = 0; i < mapLength; i++) {
        id key = [self decodeCBORFromBytes:bytes
                                    length:length
                                     index:index
                                     depth:depth + 1
                                     error:error];
        if (!key || ![key conformsToProtocol:@protocol(NSCopying)]) return nil;
        id value = [self decodeCBORFromBytes:bytes
                                      length:length
                                       index:index
                                       depth:depth + 1
                                       error:error];
        if (!value) return nil;
        dict[key] = value;
    }
    return dict;
}

- (id)decodeTag:(uint8_t)additionalInfo
          bytes:(const uint8_t *)bytes
         length:(NSUInteger)length
          index:(NSUInteger *)index
          depth:(NSUInteger)depth
          error:(NSError **)error {
    NSNumber *tag = [self decodeUnsignedInteger:additionalInfo bytes:bytes length:length index:index];
    if (!tag) return nil;
    
    id value = [self decodeCBORFromBytes:bytes
                                  length:length
                                   index:index
                                   depth:depth + 1
                                   error:error];
    if (!value) return nil;
    
    if (tag.unsignedIntegerValue == 42 && [value isKindOfClass:[NSData class]]) {
        // Tag 42 (CID)
        NSData *cidBytes = (NSData *)value;
        if (cidBytes.length > 1 && ((const uint8_t *)cidBytes.bytes)[0] == 0x00) {
            return [CID cidFromBytes:[cidBytes subdataWithRange:NSMakeRange(1, cidBytes.length - 1)]];
        }
        return [CID cidFromBytes:cidBytes];
    }
    
    return value; // For other tags, just return the inner value
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
