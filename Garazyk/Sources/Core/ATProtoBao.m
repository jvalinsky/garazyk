// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/ATProtoBao.h"
#import "Core/ATProtoBaoEncode.h"

NSErrorDomain const ATProtoBaoErrorDomain = @"ATProtoBaoErrorDomain";

static NSError *ATProtoBaoError(ATProtoBaoErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoBaoErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

@implementation ATProtoBao

+ (NSData *)hashForData:(NSData *)data {
    uint8_t hash[32];
    const uint8_t *bytes = data.bytes;
    size_t len = data.length;
    if (atproto_bao_hash(bytes, len, hash) != 0) {
        return [NSData data];
    }
    return [NSData dataWithBytes:hash length:32];
}

+ (NSData *)outboardForData:(NSData *)data error:(NSError **)error {
    uint8_t *out = NULL;
    size_t outLen = 0;
    if (atproto_bao_outboard(data.bytes, data.length, &out, &outLen) != 0 || !out) {
        if (error) *error = ATProtoBaoError(ATProtoBaoErrorInvalidArgument, @"Failed to encode outboard");
        return nil;
    }
    NSData *result = [NSData dataWithBytes:out length:outLen];
    free(out);
    return result;
}

+ (NSData *)sliceFromData:(NSData *)data
                 outboard:(NSData *)outboard
                   offset:(NSUInteger)offset
                   length:(NSUInteger)length
                    error:(NSError **)error {
    if (!outboard) {
        if (error) *error = ATProtoBaoError(ATProtoBaoErrorInvalidArgument, @"outboard required");
        return nil;
    }
    uint8_t *out = NULL;
    size_t outLen = 0;
    int rc = atproto_bao_slice(data.bytes, data.length, outboard.bytes, outboard.length,
                               (uint64_t)offset, (uint64_t)length, &out, &outLen);
    if (rc != 0 || !out) {
        if (error) {
            *error = ATProtoBaoError(rc == -1 ? ATProtoBaoErrorTruncated : ATProtoBaoErrorRange,
                                    @"Failed to extract Bao slice");
        }
        return nil;
    }
    NSData *result = [NSData dataWithBytes:out length:outLen];
    free(out);
    return result;
}

+ (NSData *)verifiedContentFromSlice:(NSData *)slice
                        expectedHash:(NSData *)hash32
                              offset:(NSUInteger)offset
                              length:(NSUInteger)length
                               error:(NSError **)error {
    if (hash32.length != 32) {
        if (error) *error = ATProtoBaoError(ATProtoBaoErrorInvalidArgument, @"expectedHash must be 32 bytes");
        return nil;
    }
    if (!slice) {
        if (error) *error = ATProtoBaoError(ATProtoBaoErrorInvalidArgument, @"slice required");
        return nil;
    }
    uint8_t *content = NULL;
    size_t contentLen = 0;
    int rc = atproto_bao_verify_slice(slice.bytes, slice.length, hash32.bytes,
                                      (uint64_t)offset, (uint64_t)length, &content, &contentLen);
    if (rc != 0) {
        free(content);
        if (error) {
            if (rc == -2) {
                *error = ATProtoBaoError(ATProtoBaoErrorHashMismatch, @"Bao slice hash mismatch");
            } else {
                *error = ATProtoBaoError(ATProtoBaoErrorTruncated, @"Bao slice truncated or invalid");
            }
        }
        return nil;
    }
    NSData *result = [NSData dataWithBytes:content length:contentLen];
    free(content);
    return result;
}

@end
