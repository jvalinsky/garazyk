// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoMUXLBox.h"
#import "Core/ATProtoDagCBOR.h"
#include <string.h>

NSString * const ATProtoMUXLErrorDomain = @"com.atproto.muxl";

static const uint32_t kMUXLStandardBoxHeaderLength = 8;
static const uint32_t kMUXLMaxBoxSize = 0xFFFFFFFFU;

static NSError *MUXLError(ATProtoMUXLErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoMUXLErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void MUXLSetError(NSError **error, ATProtoMUXLErrorCode code, NSString *message) {
    if (error) *error = MUXLError(code, message);
}

static void MUXLAppendUInt32BE(uint32_t value, NSMutableData *data) {
    uint8_t bytes[4] = {
        (uint8_t)(value >> 24), (uint8_t)(value >> 16),
        (uint8_t)(value >> 8), (uint8_t)value
    };
    [data appendBytes:bytes length:sizeof(bytes)];
}

static uint32_t MUXLReadUInt32BE(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) | bytes[3];
}

static BOOL MUXLIsPositiveUInt32(id value) {
    if (![value isKindOfClass:[NSNumber class]]) return NO;
    const char *type = [(NSNumber *)value objCType];
    if (!type || strlen(type) != 1 || strchr("islqiuILQ", type[0]) == NULL) return NO;
    return [(NSNumber *)value unsignedLongLongValue] > 0 &&
           [(NSNumber *)value unsignedLongLongValue] <= UINT32_MAX;
}

static BOOL MUXLValidateContainer(NSDictionary *container, NSError **error) {
    if (![container isKindOfClass:[NSDictionary class]] ||
        ![container[@"kind"] isKindOfClass:[NSString class]] ||
        ![container[@"kind"] isEqualToString:@"cmaf"] ||
        !MUXLIsPositiveUInt32(container[@"timescale"]) ||
        !MUXLIsPositiveUInt32(container[@"trackId"])) {
        MUXLSetError(error, ATProtoMUXLErrorInvalidContainer,
                     @"MUXL container requires kind cmaf and positive uint32 timescale/trackId");
        return NO;
    }
    return YES;
}

static BOOL MUXLValidateTrack(NSDictionary *track, BOOL video, NSError **error) {
    if (![track isKindOfClass:[NSDictionary class]] ||
        ![track[@"codec"] isKindOfClass:[NSString class]] ||
        [track[@"codec"] length] == 0 ||
        ![track[@"container"] isKindOfClass:[NSDictionary class]] ||
        !MUXLValidateContainer(track[@"container"], error)) {
        if (error && !*error) {
            MUXLSetError(error, ATProtoMUXLErrorInvalidTrack,
                         @"MUXL track requires codec and container");
        }
        return NO;
    }
    if (video && (!MUXLIsPositiveUInt32(track[@"codedWidth"]) ||
                  !MUXLIsPositiveUInt32(track[@"codedHeight"]))) {
        MUXLSetError(error, ATProtoMUXLErrorInvalidTrack,
                     @"MUXL video track requires positive codedWidth/codedHeight");
        return NO;
    }
    if (!video && (!MUXLIsPositiveUInt32(track[@"sampleRate"]) ||
                   !MUXLIsPositiveUInt32(track[@"numberOfChannels"]))) {
        MUXLSetError(error, ATProtoMUXLErrorInvalidTrack,
                     @"MUXL audio track requires positive sampleRate/numberOfChannels");
        return NO;
    }
    return YES;
}

static BOOL MUXLValidateCatalog(NSDictionary *catalog, NSError **error) {
    if (![catalog isKindOfClass:[NSDictionary class]]) {
        MUXLSetError(error, ATProtoMUXLErrorInvalidCatalog, @"MUXL catalog must be a DRISL map");
        return NO;
    }
    NSDictionary *video = catalog[@"video"];
    NSDictionary *audio = catalog[@"audio"];
    BOOL hasVideo = video != nil;
    BOOL hasAudio = audio != nil;
    if (hasVideo == hasAudio) {
        MUXLSetError(error, ATProtoMUXLErrorInvalidCatalog,
                     @"A canonical MUXL catalog must contain video or audio, but not both");
        return NO;
    }
    NSDictionary *media = hasVideo ? video : audio;
    NSDictionary *renditions = media[@"renditions"];
    if (![renditions isKindOfClass:[NSDictionary class]] || renditions.count != 1) {
        MUXLSetError(error, ATProtoMUXLErrorInvalidCatalog,
                     @"A canonical MUXL catalog must contain exactly one rendition");
        return NO;
    }
    NSString *name = renditions.allKeys.firstObject;
    if (![name isKindOfClass:[NSString class]] || name.length == 0 ||
        !MUXLValidateTrack(renditions[name], hasVideo, error)) return NO;
    return YES;
}

static BOOL MUXLReadStandardBox(NSData *data, NSUInteger *offset,
                                NSString *expectedType, NSData **body,
                                NSError **error) {
    if (*offset > data.length || data.length - *offset < kMUXLStandardBoxHeaderLength) {
        MUXLSetError(error, ATProtoMUXLErrorInvalidBox, @"MUXL fragment is missing a box header");
        return NO;
    }
    const uint8_t *bytes = data.bytes;
    uint32_t size = MUXLReadUInt32BE(bytes + *offset);
    NSString *type = [[NSString alloc] initWithBytes:bytes + *offset + 4 length:4 encoding:NSASCIIStringEncoding];
    if (size < kMUXLStandardBoxHeaderLength || size > data.length - *offset ||
        ![type isEqualToString:expectedType]) {
        MUXLSetError(error, ATProtoMUXLErrorInvalidBox,
                     [NSString stringWithFormat:@"Expected %@ box with a valid size", expectedType]);
        return NO;
    }
    *body = [data subdataWithRange:NSMakeRange(*offset + kMUXLStandardBoxHeaderLength,
                                               size - kMUXLStandardBoxHeaderLength)];
    *offset += size;
    return YES;
}

@implementation ATProtoMUXLBox

+ (NSData *)muxlUUID {
    static const uint8_t uuid[] = {
        0xe6, 0x40, 0x4e, 0xa2, 0x8f, 0x01, 0x43, 0x05,
        0x98, 0xda, 0x7b, 0xec, 0x3c, 0x2a, 0x91, 0x73
    };
    return [NSData dataWithBytes:uuid length:sizeof(uuid)];
}

+ (nullable NSData *)uuidMuxlBoxWithCatalog:(NSDictionary *)catalog
                                      error:(NSError **)error {
    if (!MUXLValidateCatalog(catalog, error)) return nil;
    NSError *encodeError = nil;
    NSData *body = [ATProtoDagCBOR encodeObject:catalog
                                         profile:ATProtoDRISLProfileDRISL
                                           error:&encodeError];
    if (!body) {
        if (error) *error = encodeError;
        return nil;
    }
    if (body.length > (NSUInteger)kMUXLMaxBoxSize - 24U) {
        MUXLSetError(error, ATProtoMUXLErrorOversizedBox, @"MUXL uuid box exceeds 32-bit BMFF size");
        return nil;
    }
    NSUInteger totalLength = body.length + 24U;
    NSMutableData *box = [NSMutableData dataWithCapacity:totalLength];
    MUXLAppendUInt32BE((uint32_t)totalLength, box);
    [box appendBytes:"uuid" length:4];
    [box appendData:[self muxlUUID]];
    [box appendData:body];
    return box;
}

+ (nullable NSDictionary *)catalogFromUUIDMuxlBox:(NSData *)boxData
                                            error:(NSError **)error {
    if (![boxData isKindOfClass:[NSData class]] || boxData.length < 8 + 16) {
        MUXLSetError(error, ATProtoMUXLErrorInvalidBox, @"MUXL uuid box is truncated");
        return nil;
    }
    const uint8_t *bytes = boxData.bytes;
    uint32_t size = MUXLReadUInt32BE(bytes);
    if (size != boxData.length || size < 24 ||
        memcmp(bytes + 4, "uuid", 4) != 0 ||
        memcmp(bytes + 8, [self muxlUUID].bytes, 16) != 0) {
        MUXLSetError(error, ATProtoMUXLErrorInvalidBox, @"Not an exact uuid-muxl box");
        return nil;
    }
    NSData *body = [boxData subdataWithRange:NSMakeRange(24, boxData.length - 24)];
    NSError *decodeError = nil;
    id catalog = [ATProtoDagCBOR decodeData:body profile:ATProtoDRISLProfileDRISL error:&decodeError];
    if (!catalog || !MUXLValidateCatalog(catalog, error)) {
        if (error && !*error) *error = decodeError;
        return nil;
    }
    return catalog;
}

+ (nullable NSData *)segmentWithCatalog:(NSDictionary *)catalog
                              fragments:(NSArray<NSData *> *)fragments
                                  error:(NSError **)error {
    if (!MUXLValidateCatalog(catalog, error)) return nil;
    if (![fragments isKindOfClass:[NSArray class]] || fragments.count == 0) {
        MUXLSetError(error, ATProtoMUXLErrorInvalidBox, @"MUXL segment requires at least one fragment");
        return nil;
    }
    NSMutableData *segment = [[self uuidMuxlBoxWithCatalog:catalog error:error] mutableCopy];
    if (!segment) return nil;
    for (NSData *fragment in fragments) {
        if (![fragment isKindOfClass:[NSData class]]) {
            MUXLSetError(error, ATProtoMUXLErrorInvalidBox, @"MUXL fragment must be NSData");
            return nil;
        }
        NSUInteger offset = 0;
        NSData *body = nil;
        if (!MUXLReadStandardBox(fragment, &offset, @"moof", &body, error) ||
            !MUXLReadStandardBox(fragment, &offset, @"mdat", &body, error) ||
            offset != fragment.length) {
            if (error && !*error) *error = MUXLError(ATProtoMUXLErrorTrailingData,
                                                       @"MUXL fragment must be exactly moof followed by mdat");
            return nil;
        }
        [segment appendData:fragment];
    }
    return segment;
}

@end
