// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/EventFormatter.h"
#import "Sync/Firehose/Firehose.h"
#import "Core/ATProtoDagCBOR.h"
#import "Debug/GZLogger.h"

NSString * const EventFormatterErrorDomain = @"com.atproto.pds.eventformatter";
NSInteger const EventFormatterErrorCodeEncodingFailed = 5000;
NSInteger const EventFormatterErrorCodeDecodingFailed = 5001;

static const uint8_t kXRPCStreamOpMessage = 1;
static const NSUInteger kEventFormatterMaxFrameBytes = 1024 * 1024;

@implementation EventFormatter

- (NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event error:(NSError **)error {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"seq"] = @(event.seq);
    payload[@"rebase"] = @(event.rebase);
    payload[@"tooBig"] = @(event.tooBig);
    payload[@"repo"] = event.repo;
    payload[@"commit"] = event.commit;
    payload[@"rev"] = event.rev;
    payload[@"since"] = event.since ?: [NSNull null];
    payload[@"blocks"] = event.blocks ?: [NSData data];

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
    payload[@"blobs"] = event.blobs ?: @[];
    payload[@"time"] = event.time ?: @"";
    if (event.prevData) {
        payload[@"prevData"] = event.prevData;
    }

    return [self encodeStreamEventWithType:@"#commit" payload:payload error:error];
}

- (NSData *)encodeSyncEvent:(FirehoseSyncEvent *)event error:(NSError **)error {
    NSDictionary *payload = @{
        @"seq": @(event.seq),
        @"did": event.did,
        @"blocks": event.blocks ?: [NSData data],
        @"rev": event.rev ?: @"",
        @"time": event.time ?: @""
    };
    return [self encodeStreamEventWithType:@"#sync" payload:payload error:error];
}

- (NSData *)encodeIdentityEvent:(FirehoseIdentityEvent *)event error:(NSError **)error {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"seq"] = @(event.seq);
    payload[@"did"] = event.did;
    payload[@"time"] = event.time ?: @"";
    if (event.handle) payload[@"handle"] = event.handle;
    return [self encodeStreamEventWithType:@"#identity" payload:payload error:error];
}

- (NSData *)encodeAccountEvent:(FirehoseAccountEvent *)event error:(NSError **)error {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"seq"] = @(event.seq);
    payload[@"did"] = event.did;
    payload[@"active"] = @(event.active);
    payload[@"time"] = event.time ?: @"";
    if (event.status) payload[@"status"] = event.status;
    return [self encodeStreamEventWithType:@"#account" payload:payload error:error];
}

- (NSData *)encodeInfoEvent:(FirehoseInfoEvent *)event error:(NSError **)error {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"name"] = event.kind ?: @"";
    if (event.message.length > 0) payload[@"message"] = event.message;
    return [self encodeStreamEventWithType:@"#info" payload:payload error:error];
}

- (NSData *)encodeErrorEvent:(FirehoseErrorEvent *)event error:(NSError **)error {
    NSDictionary *header = @{@"op": @(-1)};
    NSString *errorCode = event.error.length > 0 ? event.error : event.message;
    NSMutableDictionary *body = [@{
        @"error": errorCode.length > 0 ? errorCode : @"UnknownError"
    } mutableCopy];
    if (event.message.length > 0) body[@"message"] = event.message;

    NSData *headerData = [ATProtoDagCBOR encodeObject:header error:error];
    if (!headerData) return nil;
    NSData *bodyData = [ATProtoDagCBOR encodeObject:body error:error];
    if (!bodyData) return nil;
    NSMutableData *result = [headerData mutableCopy];
    [result appendData:bodyData];
    if (result.length > kEventFormatterMaxFrameBytes) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeEncodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Event exceeds the maximum frame size"}];
        }
        return nil;
    }
    return result;
}

- (NSData *)encodeStreamEventWithType:(NSString *)msgType
                              payload:(NSDictionary *)payload
                                error:(NSError **)error {
    NSDictionary *header = @{
        @"op": @(kXRPCStreamOpMessage),
        @"t": msgType
    };
    NSData *headerData = [ATProtoDagCBOR encodeObject:header error:error];
    if (!headerData) return nil;
    NSData *payloadData = [ATProtoDagCBOR encodeObject:payload error:error];
    if (!payloadData) {
        GZ_LOG_SYNC_ERROR(@"Failed to encode firehose payload %@: %@", msgType,
                          error ? *error : @"unknown error");
        return nil;
    }

    NSMutableData *result = [headerData mutableCopy];
    [result appendData:payloadData];
    if (result.length > kEventFormatterMaxFrameBytes) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeEncodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Event exceeds the maximum frame size"}];
        }
        return nil;
    }
    return result;
}

- (NSDictionary *)decodeEventFromData:(NSData *)data
                                   op:(NSInteger *)op
                              msgType:(NSString **)msgType
                                error:(NSError **)error {
    if (data.length == 0 || data.length > kEventFormatterMaxFrameBytes) {
        if (error) {
            *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                         code:EventFormatterErrorCodeDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: data.length == 0
                                         ? @"Empty event data"
                                         : @"Event exceeds the maximum frame size"}];
        }
        return nil;
    }

    // A stream message is exactly two concatenated ATProto DRISL items. The
    // consumed-length API splits them without reimplementing CBOR parsing;
    // the authoritative decoder rejects non-canonical lengths, unknown tags,
    // invalid UTF-8, floats, undefined, and non-string map keys.
    NSUInteger headerLength = 0;
    NSError *decodeError = nil;
    id decodedHeader = [ATProtoDagCBOR decodeOneFromData:data
                                                  profile:ATProtoDRISLProfileATProto
                                          consumedLength:&headerLength
                                                    error:&decodeError];
    if (![decodedHeader isKindOfClass:[NSDictionary class]] || headerLength == 0) {
        if (error) *error = decodeError ?: [self formatterError:@"Invalid XRPC frame header"];
        return nil;
    }

    NSDictionary *header = decodedHeader;
    NSNumber *opNumber = [header[@"op"] isKindOfClass:[NSNumber class]] ? header[@"op"] : nil;
    NSString *headerType = [header[@"t"] isKindOfClass:[NSString class]] ? header[@"t"] : nil;
    if (!opNumber ||
        (opNumber.integerValue != XRPCStreamOpKindErrorFrame &&
         opNumber.integerValue != XRPCStreamOpKindMessage) ||
        (opNumber.integerValue == XRPCStreamOpKindMessage && headerType.length == 0)) {
        if (error) *error = [self formatterError:@"Invalid XRPC frame header fields"];
        return nil;
    }

    NSInteger opValue = opNumber.integerValue;
    if (op) *op = opValue;
    if (msgType) *msgType = opValue == XRPCStreamOpKindErrorFrame ? @"#error" : headerType;

    if (headerLength >= data.length) {
        if (error) *error = [self formatterError:@"XRPC frame is missing its body"];
        return nil;
    }

    NSData *bodyData = [data subdataWithRange:NSMakeRange(headerLength, data.length - headerLength)];
    NSUInteger bodyLength = 0;
    decodeError = nil;
    id body = [ATProtoDagCBOR decodeOneFromData:bodyData
                                         profile:ATProtoDRISLProfileATProto
                                 consumedLength:&bodyLength
                                           error:&decodeError];
    if (![body isKindOfClass:[NSDictionary class]] || bodyLength == 0 || bodyLength != bodyData.length) {
        if (error) *error = decodeError ?: [self formatterError:@"Invalid XRPC frame body"];
        return nil;
    }
    return body;
}

- (NSError *)formatterError:(NSString *)message {
    return [NSError errorWithDomain:EventFormatterErrorDomain
                                code:EventFormatterErrorCodeDecodingFailed
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end
