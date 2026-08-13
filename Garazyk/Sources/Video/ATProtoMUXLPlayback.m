// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/ATProtoMUXLPlayback.h"
#import "Video/ATProtoMUXLFMP4.h"
#import "MediaCore/ATProtoMUXLBox.h"
#import "MediaCore/ATProtoMUXLFragment.h"
#import "Security/S2PA/ATProtoS2PAJUMBF.h"
#import "Auth/Crypto/Secp256k1.h"
#include <string.h>

NSString * const ATProtoMUXLPlaybackErrorDomain = @"com.atproto.muxl.playback";

static NSError *MUXLPlaybackError(ATProtoMUXLPlaybackErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoMUXLPlaybackErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void MUXLPlaybackSetError(NSError **error, ATProtoMUXLPlaybackErrorCode code,
                                 NSString *message) {
    if (error) *error = MUXLPlaybackError(code, message);
}

static uint32_t MUXLPlaybackReadU32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) | (uint32_t)bytes[3];
}

static BOOL MUXLPlaybackReadBox(const uint8_t *bytes, NSUInteger length, NSUInteger offset,
                                uint64_t *outSize, const char **outType, NSUInteger *outHeader) {
    if (offset + 8 > length) return NO;
    uint32_t size32 = MUXLPlaybackReadU32(bytes + offset);
    *outType = (const char *)(bytes + offset + 4);
    if (size32 == 1) {
        if (offset + 16 > length) return NO;
        uint64_t hi = MUXLPlaybackReadU32(bytes + offset + 8);
        uint64_t lo = MUXLPlaybackReadU32(bytes + offset + 12);
        *outSize = (hi << 32) | lo;
        *outHeader = 16;
    } else if (size32 == 0) {
        *outSize = length - offset;
        *outHeader = 8;
    } else {
        *outSize = size32;
        *outHeader = 8;
    }
    if (*outSize < *outHeader || offset + *outSize > length) return NO;
    return YES;
}

@implementation ATProtoMUXLPlayback

+ (nullable NSData *)canonicalSegmentsFromPresentation:(NSData *)presentation
                                                 error:(NSError **)error {
    if (![presentation isKindOfClass:[NSData class]] || presentation.length < 24) {
        MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidArgument,
                             @"MUXL presentation is truncated");
        return nil;
    }
    const uint8_t *bytes = presentation.bytes;
    NSUInteger length = presentation.length;
    NSData *muxlUUID = [ATProtoMUXLBox muxlUUID];
    NSUInteger offset = 0;
    while (offset + 24 <= length) {
        uint64_t size = 0;
        const char *type = NULL;
        NSUInteger header = 0;
        if (!MUXLPlaybackReadBox(bytes, length, offset, &size, &type, &header)) {
            MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidPresentation,
                                 @"MUXL presentation has an invalid box");
            return nil;
        }
        if (memcmp(type, "uuid", 4) == 0 && size >= header + 16 &&
            memcmp(bytes + offset + header, muxlUUID.bytes, 16) == 0) {
            return [presentation subdataWithRange:NSMakeRange(offset, length - offset)];
        }
        // Flat MP4: outer mdat envelope carries the segment stream verbatim.
        if (memcmp(type, "mdat", 4) == 0) {
            NSUInteger payload = offset + header;
            if (payload >= length) {
                MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidPresentation,
                                     @"MUXL flat MP4 mdat has no payload");
                return nil;
            }
            return [presentation subdataWithRange:NSMakeRange(payload, length - payload)];
        }
        offset += (NSUInteger)size;
    }
    MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidPresentation,
                         @"MUXL presentation has no uuid-muxl or mdat segment stream");
    return nil;
}

+ (nullable NSArray<NSData *> *)splitSegments:(NSData *)segmentStream
                                        error:(NSError **)error {
    if (![segmentStream isKindOfClass:[NSData class]] || segmentStream.length == 0) {
        MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidArgument,
                             @"MUXL segment stream is empty");
        return nil;
    }
    const uint8_t *bytes = segmentStream.bytes;
    NSUInteger length = segmentStream.length;
    NSData *muxlUUID = [ATProtoMUXLBox muxlUUID];
    NSMutableArray<NSData *> *segments = [NSMutableArray array];
    NSUInteger offset = 0;
    NSUInteger segmentStart = NSNotFound;

    while (offset + 8 <= length) {
        uint64_t size = 0;
        const char *type = NULL;
        NSUInteger header = 0;
        if (!MUXLPlaybackReadBox(bytes, length, offset, &size, &type, &header)) {
            MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidSegment,
                                 @"MUXL segment stream has an invalid box");
            return nil;
        }
        BOOL isMuxlUUID = (memcmp(type, "uuid", 4) == 0 && size >= header + 16 &&
                           memcmp(bytes + offset + header, muxlUUID.bytes, 16) == 0);
        if (isMuxlUUID) {
            if (segmentStart != NSNotFound) {
                [segments addObject:[segmentStream subdataWithRange:
                    NSMakeRange(segmentStart, offset - segmentStart)]];
            }
            segmentStart = offset;
        } else if (segmentStart == NSNotFound) {
            MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidSegment,
                                 @"MUXL segment stream must begin with uuid-muxl");
            return nil;
        }
        offset += (NSUInteger)size;
    }
    if (segmentStart == NSNotFound || offset != length) {
        MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidSegment,
                             @"MUXL segment stream is incomplete");
        return nil;
    }
    [segments addObject:[segmentStream subdataWithRange:
        NSMakeRange(segmentStart, length - segmentStart)]];
    return [segments copy];
}

+ (BOOL)validateSegmentBytes:(NSData *)segment error:(NSError **)error {
    // Decode leading uuid-muxl then validate each moof+mdat pair.
    if (segment.length < 24) {
        MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidSegment,
                             @"MUXL segment is truncated");
        return NO;
    }
    const uint8_t *bytes = segment.bytes;
    uint64_t uuidSize = 0;
    const char *type = NULL;
    NSUInteger header = 0;
    if (!MUXLPlaybackReadBox(bytes, segment.length, 0, &uuidSize, &type, &header) ||
        memcmp(type, "uuid", 4) != 0) {
        MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidSegment,
                             @"MUXL segment must start with uuid-muxl");
        return NO;
    }
    NSData *uuidBox = [segment subdataWithRange:NSMakeRange(0, (NSUInteger)uuidSize)];
    if (![ATProtoMUXLBox catalogFromUUIDMuxlBox:uuidBox error:error]) {
        return NO;
    }
    NSUInteger offset = (NSUInteger)uuidSize;
    NSUInteger fragmentCount = 0;
    while (offset < segment.length) {
        if (offset + 16 > segment.length) {
            MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidSegment,
                                 @"MUXL segment ends mid-fragment");
            return NO;
        }
        uint32_t moofSize = MUXLPlaybackReadU32(bytes + offset);
        if (moofSize < 8 || offset + moofSize + 8 > segment.length ||
            memcmp(bytes + offset + 4, "moof", 4) != 0) {
            MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidSegment,
                                 @"MUXL segment expected moof after catalog");
            return NO;
        }
        uint32_t mdatSize = MUXLPlaybackReadU32(bytes + offset + moofSize);
        if (mdatSize < 8 || offset + moofSize + mdatSize > segment.length ||
            memcmp(bytes + offset + moofSize + 4, "mdat", 4) != 0) {
            MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidSegment,
                                 @"MUXL segment expected mdat after moof");
            return NO;
        }
        NSData *fragment = [segment subdataWithRange:
            NSMakeRange(offset, (NSUInteger)moofSize + (NSUInteger)mdatSize)];
        if (![ATProtoMUXLFragment validateFragment:fragment error:error]) {
            return NO;
        }
        offset += (NSUInteger)moofSize + (NSUInteger)mdatSize;
        fragmentCount++;
    }
    if (fragmentCount == 0) {
        MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidSegment,
                             @"MUXL segment has no fragments");
        return NO;
    }
    return YES;
}

+ (BOOL)validateFMP4Presentation:(NSData *)presentation error:(NSError **)error {
    NSData *segments = [self canonicalSegmentsFromPresentation:presentation error:error];
    if (!segments) return NO;
    if (segments.length >= presentation.length) {
        MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidPresentation,
                             @"MUXL fMP4 presentation is missing an init header");
        return NO;
    }
    NSData *init = [presentation subdataWithRange:
        NSMakeRange(0, presentation.length - segments.length)];
    if (![ATProtoMUXLFMP4 validateInitSegment:init error:error]) {
        return NO;
    }
    NSArray<NSData *> *parts = [self splitSegments:segments error:error];
    if (!parts) return NO;
    for (NSData *part in parts) {
        if (![self validateSegmentBytes:part error:error]) return NO;
    }
    return YES;
}

+ (BOOL)validateFlatMP4Presentation:(NSData *)presentation error:(NSError **)error {
    if (![presentation isKindOfClass:[NSData class]] || presentation.length < 32) {
        MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidArgument,
                             @"MUXL flat MP4 presentation is truncated");
        return NO;
    }
    const uint8_t *bytes = presentation.bytes;
    uint64_t ftypSize = 0;
    const char *type = NULL;
    NSUInteger header = 0;
    if (!MUXLPlaybackReadBox(bytes, presentation.length, 0, &ftypSize, &type, &header) ||
        memcmp(type, "ftyp", 4) != 0) {
        MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidPresentation,
                             @"MUXL flat MP4 must begin with ftyp");
        return NO;
    }
    NSData *segments = [self canonicalSegmentsFromPresentation:presentation error:error];
    if (!segments) return NO;
    NSArray<NSData *> *parts = [self splitSegments:segments error:error];
    if (!parts) return NO;
    for (NSData *part in parts) {
        if (![self validateSegmentBytes:part error:error]) return NO;
    }
    // Round-trip: rebuilt flat MP4 must preserve the segment stream bytes.
    NSData *rebuilt = [ATProtoMUXLFMP4 flatMP4WithSegments:parts error:error];
    if (!rebuilt) return NO;
    NSData *recovered = [self canonicalSegmentsFromPresentation:rebuilt error:error];
    if (!recovered || ![recovered isEqualToData:segments]) {
        MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidPresentation,
                             @"MUXL flat MP4 round-trip altered segment bytes");
        return NO;
    }
    return YES;
}

+ (nullable NSData *)presentationByHardBindingSegment:(NSData *)segment
                                          withKeyPair:(ATProtoSecp256k1KeyPair *)keyPair
                                                  did:(nullable NSString *)did
                                            notBefore:(NSDate *)notBefore
                                             notAfter:(NSDate *)notAfter
                                                error:(NSError **)error {
    if (![segment isKindOfClass:[NSData class]] || segment.length == 0 || !keyPair) {
        MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidArgument,
                             @"MUXL S2PA hard binding requires segment and key pair");
        return nil;
    }
    // Ensure the payload is a recognizable MUXL segment stream before signing.
    if (![self splitSegments:segment error:error]) {
        return nil;
    }
    NSData *bound = [ATProtoS2PAJUMBF presentationHardBindingMediaData:segment
                                                          withKeyPair:keyPair
                                                                  did:did
                                                            notBefore:notBefore
                                                             notAfter:notAfter
                                                                error:error];
    if (!bound) {
        if (error && !*error) {
            MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidPresentation,
                                 @"MUXL S2PA hard binding failed");
        }
        return nil;
    }
    return bound;
}

+ (BOOL)verifyHardBoundPresentation:(NSData *)presentation
                        expectedDID:(nullable NSString *)expectedDID
                              error:(NSError **)error {
    if (![presentation isKindOfClass:[NSData class]] || presentation.length < 24) {
        MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidArgument,
                             @"MUXL hard-bound presentation is truncated");
        return NO;
    }
    const uint8_t *bytes = presentation.bytes;
    uint64_t size = 0;
    const char *type = NULL;
    NSUInteger header = 0;
    if (!MUXLPlaybackReadBox(bytes, presentation.length, 0, &size, &type, &header) ||
        memcmp(type, "uuid", 4) != 0) {
        MUXLPlaybackSetError(error, ATProtoMUXLPlaybackErrorInvalidPresentation,
                             @"MUXL hard-bound presentation must begin with uuid box");
        return NO;
    }
    NSData *uuidBox = [presentation subdataWithRange:NSMakeRange(0, (NSUInteger)size)];
    NSData *segment = [presentation subdataWithRange:
        NSMakeRange((NSUInteger)size, presentation.length - (NSUInteger)size)];
    if (![ATProtoS2PAJUMBF verifyUUIDBox:uuidBox
                   hardBoundToMediaData:segment
                           expectedDID:expectedDID
                                 error:error]) {
        return NO;
    }
    if (![self splitSegments:segment error:error]) {
        return NO;
    }
    return YES;
}

@end
