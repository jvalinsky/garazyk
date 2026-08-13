// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/ATProtoMUXLTranscoderBridge.h"
#import "Video/ATProtoMUXLFMP4.h"
#import "Video/ATProtoMUXLPlayback.h"
#import "MediaCore/ATProtoMUXLBox.h"
#import "Auth/Crypto/Secp256k1.h"
#include <string.h>

NSString * const ATProtoMUXLTranscoderBridgeErrorDomain = @"com.atproto.muxl.transcoder";

static NSError *MUXLBridgeError(ATProtoMUXLTranscoderBridgeErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoMUXLTranscoderBridgeErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void MUXLBridgeSetError(NSError **error, ATProtoMUXLTranscoderBridgeErrorCode code,
                               NSString *message) {
    if (error) *error = MUXLBridgeError(code, message);
}

static uint32_t MUXLBridgeReadU32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) | (uint32_t)bytes[3];
}

static BOOL MUXLBridgeWalk(const uint8_t *bytes, NSUInteger length, NSUInteger offset,
                           NSUInteger end,
                           BOOL (^visitor)(NSUInteger boxOffset, uint32_t size, const char *type,
                                           NSUInteger bodyOffset, NSUInteger bodyLength)) {
    NSUInteger cursor = offset;
    while (cursor + 8 <= end) {
        uint32_t size = MUXLBridgeReadU32(bytes + cursor);
        if (size < 8 || cursor + size > end) return NO;
        const char *type = (const char *)(bytes + cursor + 4);
        if (!visitor(cursor, size, type, cursor + 8, size - 8)) return NO;
        cursor += size;
    }
    return cursor == end;
}

@implementation ATProtoMUXLTranscoderBridge

+ (nullable NSDictionary *)catalogFromCMAFInit:(NSData *)initSegment
                                         error:(NSError **)error {
    if (![initSegment isKindOfClass:[NSData class]] || initSegment.length < 16) {
        MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidArgument,
                           @"CMAF init segment is truncated");
        return nil;
    }
    const uint8_t *bytes = initSegment.bytes;
    NSUInteger length = initSegment.length;

    __block BOOL foundTrack = NO;
    __block BOOL isVideo = NO;
    __block uint32_t trackID = 0;
    __block uint32_t timescale = 0;
    __block uint32_t width = 0;
    __block uint32_t height = 0;
    __block uint32_t sampleRate = 0;
    __block uint32_t channels = 0;
    __block NSString *codec = nil;
    __block NSData *description = nil;

    BOOL ok = MUXLBridgeWalk(bytes, length, 0, length,
                             ^BOOL(NSUInteger boxOffset, uint32_t size, const char *type,
                                   NSUInteger bodyOffset, NSUInteger bodyLength) {
        (void)boxOffset;
        (void)size;
        if (memcmp(type, "moov", 4) != 0) return YES;
        return MUXLBridgeWalk(bytes, length, bodyOffset, bodyOffset + bodyLength,
                              ^BOOL(NSUInteger tOff, uint32_t tSize, const char *tType,
                                    NSUInteger tBody, NSUInteger tLen) {
            (void)tOff;
            (void)tSize;
            if (memcmp(tType, "trak", 4) != 0) return YES;
            if (foundTrack) {
                MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorUnsupportedInit,
                                   @"CMAF init has multiple tracks; MUXL bridge expects one");
                return NO;
            }
            foundTrack = YES;
            __block BOOL sawTkhd = NO;
            __block BOOL sawMdhd = NO;
            __block BOOL sawSample = NO;
            BOOL trakOK = MUXLBridgeWalk(bytes, length, tBody, tBody + tLen,
                                         ^BOOL(NSUInteger cOff, uint32_t cSize, const char *cType,
                                               NSUInteger cBody, NSUInteger cLen) {
                (void)cOff;
                (void)cSize;
                if (memcmp(cType, "tkhd", 4) == 0) {
                    // version/flags (4) + creation/mod (8) + track_id (4) for v0
                    if (cLen < 20) return NO;
                    uint8_t version = bytes[cBody];
                    NSUInteger idOff = cBody + 4 + (version == 1 ? 16 : 8);
                    if (idOff + 4 > cBody + cLen) return NO;
                    trackID = MUXLBridgeReadU32(bytes + idOff);
                    if (version == 0 && cLen >= 84) {
                        // FullBox body: vf(4) + 72 fixed fields + width(4) + height(4)
                        width = MUXLBridgeReadU32(bytes + cBody + 76) >> 16;
                        height = MUXLBridgeReadU32(bytes + cBody + 80) >> 16;
                    }
                    sawTkhd = YES;
                } else if (memcmp(cType, "mdia", 4) == 0) {
                    return MUXLBridgeWalk(bytes, length, cBody, cBody + cLen,
                                          ^BOOL(NSUInteger mOff, uint32_t mSize, const char *mType,
                                                NSUInteger mBody, NSUInteger mLen) {
                        (void)mOff;
                        (void)mSize;
                        if (memcmp(mType, "mdhd", 4) == 0) {
                            if (mLen < 20) return NO;
                            uint8_t version = bytes[mBody];
                            NSUInteger tsOff = mBody + 4 + (version == 1 ? 16 : 8);
                            if (tsOff + 4 > mBody + mLen) return NO;
                            timescale = MUXLBridgeReadU32(bytes + tsOff);
                            sawMdhd = YES;
                        } else if (memcmp(mType, "hdlr", 4) == 0) {
                            if (mLen < 12) return NO;
                            const char *handler = (const char *)(bytes + mBody + 8);
                            if (memcmp(handler, "vide", 4) == 0) isVideo = YES;
                            else if (memcmp(handler, "soun", 4) == 0) isVideo = NO;
                            else {
                                MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorUnsupportedInit,
                                                   @"CMAF init track handler must be vide or soun");
                                return NO;
                            }
                        } else if (memcmp(mType, "minf", 4) == 0) {
                            return MUXLBridgeWalk(bytes, length, mBody, mBody + mLen,
                                                  ^BOOL(NSUInteger nOff, uint32_t nSize, const char *nType,
                                                        NSUInteger nBody, NSUInteger nLen) {
                                (void)nOff;
                                (void)nSize;
                                if (memcmp(nType, "stbl", 4) != 0) return YES;
                                return MUXLBridgeWalk(bytes, length, nBody, nBody + nLen,
                                                      ^BOOL(NSUInteger sOff, uint32_t sSize, const char *sType,
                                                            NSUInteger sBody, NSUInteger sLen) {
                                    (void)sOff;
                                    (void)sSize;
                                    if (memcmp(sType, "stsd", 4) != 0) return YES;
                                    if (sLen < 8) return NO;
                                    uint32_t entryCount = MUXLBridgeReadU32(bytes + sBody + 4);
                                    if (entryCount != 1 || sLen < 16) return NO;
                                    NSUInteger entryOff = sBody + 8;
                                    uint32_t entrySize = MUXLBridgeReadU32(bytes + entryOff);
                                    if (entrySize < 16 || entryOff + entrySize > sBody + sLen) return NO;
                                    const char *fourcc = (const char *)(bytes + entryOff + 4);
                                    if (memcmp(fourcc, "avc1", 4) == 0 || memcmp(fourcc, "avc3", 4) == 0) {
                                        codec = @"avc1.64001f";
                                        isVideo = YES;
                                    } else if (memcmp(fourcc, "av01", 4) == 0) {
                                        codec = @"av01.0.01M.08";
                                        isVideo = YES;
                                    } else if (memcmp(fourcc, "mp4a", 4) == 0) {
                                        codec = @"mp4a.40.2";
                                        isVideo = NO;
                                    } else {
                                        MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorUnsupportedInit,
                                                           @"CMAF init sample entry must be avc1/av01/mp4a");
                                        return NO;
                                    }
                                    // Prefer VisualSampleEntry / AudioSampleEntry field layouts when present;
                                    // also accept the compact MUXL-synthesized sample-entry layout.
                                    if (isVideo && entrySize >= 40) {
                                        // ISO VisualSampleEntry width/height at +32/+34 from entry start.
                                        uint16_t isoW = ((uint16_t)bytes[entryOff + 32] << 8) | bytes[entryOff + 33];
                                        uint16_t isoH = ((uint16_t)bytes[entryOff + 34] << 8) | bytes[entryOff + 35];
                                        if (isoW > 0 && isoH > 0) {
                                            width = isoW;
                                            height = isoH;
                                        } else if (entrySize >= 24) {
                                            // Compact MUXL layout: data_ref(2)+pad(16)+w(2)+h(2)
                                            width = ((uint32_t)bytes[entryOff + 20] << 8) | bytes[entryOff + 21];
                                            height = ((uint32_t)bytes[entryOff + 22] << 8) | bytes[entryOff + 23];
                                        }
                                    } else if (!isVideo && entrySize >= 36) {
                                        channels = ((uint32_t)bytes[entryOff + 24] << 8) | bytes[entryOff + 25];
                                        sampleRate = MUXLBridgeReadU32(bytes + entryOff + 32) >> 16;
                                        if (sampleRate == 0 && entrySize >= 28) {
                                            // Compact: data_ref(2)+pad(8)+channels(2)+…+rate at +20
                                            channels = ((uint32_t)bytes[entryOff + 16] << 8) | bytes[entryOff + 17];
                                            sampleRate = MUXLBridgeReadU32(bytes + entryOff + 20) >> 16;
                                        }
                                    }
                                    // Locate codec-config child boxes without treating fixed Visual/Audio
                                    // SampleEntry fields as BMFF boxes (byte-scan for known types).
                                    for (NSUInteger child = entryOff + 8; child + 8 <= entryOff + entrySize; child++) {
                                        uint32_t csz = MUXLBridgeReadU32(bytes + child);
                                        if (csz < 8 || child + csz > entryOff + entrySize) continue;
                                        const char *ctype = (const char *)(bytes + child + 4);
                                        if ((isVideo && (memcmp(ctype, "avcC", 4) == 0 || memcmp(ctype, "av1C", 4) == 0)) ||
                                            (!isVideo && memcmp(ctype, "esds", 4) == 0)) {
                                            description = [NSData dataWithBytes:bytes + child + 8 length:csz - 8];
                                            break;
                                        }
                                    }
                                    sawSample = YES;
                                    return YES;
                                });
                            });
                        }
                        return YES;
                    });
                }
                return YES;
            });
            return trakOK && sawTkhd && sawMdhd && sawSample;
        });
    });

    if (!ok || !foundTrack || trackID == 0 || timescale == 0 || codec.length == 0) {
        if (error && !*error) {
            MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorUnsupportedInit,
                               @"Failed to extract a MUXL catalog from CMAF init");
        }
        return nil;
    }

    NSMutableDictionary *track = [@{
        @"codec": codec,
        @"container": @{
            @"kind": @"cmaf",
            @"timescale": @(timescale),
            @"trackId": @(trackID),
        },
    } mutableCopy];
    if (description) track[@"description"] = description;
    if (isVideo) {
        if (width == 0 || height == 0) {
            MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorUnsupportedInit,
                               @"CMAF video init is missing coded dimensions");
            return nil;
        }
        track[@"codedWidth"] = @(width);
        track[@"codedHeight"] = @(height);
        return @{ @"video": @{ @"renditions": @{ @"main": [track copy] } } };
    }
    if (sampleRate == 0 || channels == 0) {
        MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorUnsupportedInit,
                           @"CMAF audio init is missing sampleRate/channels");
        return nil;
    }
    track[@"sampleRate"] = @(sampleRate);
    track[@"numberOfChannels"] = @(channels);
    return @{ @"audio": @{ @"renditions": @{ @"main": [track copy] } } };
}

+ (nullable NSArray<NSData *> *)muxlSegmentsWithCatalog:(NSDictionary *)catalog
                                          cmafFragments:(NSArray<NSData *> *)fragments
                                                  error:(NSError **)error {
    if (![catalog isKindOfClass:[NSDictionary class]] ||
        ![fragments isKindOfClass:[NSArray class]] || fragments.count == 0) {
        MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidArgument,
                           @"MUXL bridge requires a catalog and CMAF fragments");
        return nil;
    }
    NSMutableArray<NSData *> *out = [NSMutableArray arrayWithCapacity:fragments.count];
    for (NSData *fragment in fragments) {
        if (![fragment isKindOfClass:[NSData class]] || fragment.length < 16) {
            MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidFragment,
                               @"CMAF fragment is truncated");
            return nil;
        }
        // Opaque CMAF envelope check only — nested trun flags may differ from
        // MUXL-minted fragments (ffmpeg). ATProtoMUXLBox keeps nested structure opaque.
        const uint8_t *bytes = fragment.bytes;
        uint32_t moofSize = MUXLBridgeReadU32(bytes);
        if (moofSize < 8 || moofSize + 8 > fragment.length ||
            memcmp(bytes + 4, "moof", 4) != 0 ||
            memcmp(bytes + moofSize + 4, "mdat", 4) != 0) {
            MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidFragment,
                               @"CMAF fragment must be [moof][mdat]");
            return nil;
        }
        uint32_t mdatSize = MUXLBridgeReadU32(bytes + moofSize);
        if (mdatSize < 8 || moofSize + mdatSize > fragment.length) {
            MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidFragment,
                               @"CMAF fragment mdat size is invalid");
            return nil;
        }
        NSData *segment = [ATProtoMUXLBox segmentWithCatalog:catalog
                                                   fragments:@[fragment]
                                                       error:error];
        if (!segment) return nil;
        [out addObject:segment];
    }
    return [out copy];
}

+ (nullable NSDictionary<NSString *, id> *)packageHLSVariantDirectory:(NSString *)directory
                                                                error:(NSError **)error {
    if (directory.length == 0) {
        MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidArgument,
                           @"HLS variant directory is required");
        return nil;
    }
    NSString *initPath = [directory stringByAppendingPathComponent:@"init.mp4"];
    NSData *initData = [NSData dataWithContentsOfFile:initPath];
    if (!initData) {
        MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidArgument,
                           @"HLS variant is missing init.mp4");
        return nil;
    }
    NSDictionary *catalog = [self catalogFromCMAFInit:initData error:error];
    if (!catalog) return nil;

    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory
                                                                                     error:error];
    if (!names) return nil;
    NSArray<NSString *> *sorted = [[names filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
            (void)bindings;
            return [name hasPrefix:@"segment_"] && [name hasSuffix:@".m4s"];
        }]] sortedArrayUsingSelector:@selector(compare:)];
    if (sorted.count == 0) {
        MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidArgument,
                           @"HLS variant has no segment_*.m4s files");
        return nil;
    }
    NSMutableArray<NSData *> *fragments = [NSMutableArray arrayWithCapacity:sorted.count];
    for (NSString *name in sorted) {
        NSData *data = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:name]];
        if (!data) {
            MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidFragment,
                               @"Failed to read an HLS media segment");
            return nil;
        }
        [fragments addObject:data];
    }
    NSArray<NSData *> *segments = [self muxlSegmentsWithCatalog:catalog
                                                  cmafFragments:fragments
                                                          error:error];
    if (!segments) return nil;
    NSData *muxlInit = [ATProtoMUXLFMP4 initSegmentWithCatalogs:@[catalog] error:error];
    if (!muxlInit) return nil;
    NSData *presentation = [ATProtoMUXLFMP4 presentationWithInit:muxlInit
                                                        segments:segments
                                                           error:error];
    if (!presentation) return nil;
    // Flat MP4 requires MUXL-minted fragment layout. ffmpeg CMAF often differs,
    // so Flat packaging is best-effort and omitted when fragments are opaque.
    NSError *flatError = nil;
    NSData *flat = [ATProtoMUXLFMP4 flatMP4WithSegments:segments error:&flatError];
    NSMutableDictionary *result = [@{
        @"catalog": catalog,
        @"segments": segments,
        @"init": muxlInit,
        @"presentation": presentation,
    } mutableCopy];
    if (flat) {
        result[@"flat"] = flat;
    }
    return [result copy];
}

+ (nullable NSDictionary<NSString *, id> *)writePackage:(NSDictionary<NSString *, id> *)package
                                            toDirectory:(NSString *)directory
                                                  error:(NSError **)error {
    if (![package isKindOfClass:[NSDictionary class]] || directory.length == 0) {
        MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidArgument,
                           @"MUXL package write requires a package and directory");
        return nil;
    }
    NSData *initData = package[@"init"];
    NSData *presentation = package[@"presentation"];
    NSArray *segments = package[@"segments"];
    if (![initData isKindOfClass:[NSData class]] ||
        ![presentation isKindOfClass:[NSData class]] ||
        ![segments isKindOfClass:[NSArray class]] || segments.count == 0) {
        MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidArgument,
                           @"MUXL package is missing init, presentation, or segments");
        return nil;
    }
    NSString *muxlDir = [directory stringByAppendingPathComponent:@"muxl"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:muxlDir withIntermediateDirectories:YES attributes:nil error:error]) {
        return nil;
    }
    NSMutableDictionary<NSString *, id> *paths = [NSMutableDictionary dictionary];
    NSString *initPath = [muxlDir stringByAppendingPathComponent:@"init.mp4"];
    if (![initData writeToFile:initPath options:NSDataWritingAtomic error:error]) return nil;
    paths[@"init"] = initPath;

    NSString *presentationPath = [muxlDir stringByAppendingPathComponent:@"presentation.mp4"];
    if (![presentation writeToFile:presentationPath options:NSDataWritingAtomic error:error]) return nil;
    paths[@"presentation"] = presentationPath;

    NSData *flat = package[@"flat"];
    if ([flat isKindOfClass:[NSData class]]) {
        NSString *flatPath = [muxlDir stringByAppendingPathComponent:@"flat.mp4"];
        if (![flat writeToFile:flatPath options:NSDataWritingAtomic error:error]) return nil;
        paths[@"flat"] = flatPath;
    }

    NSMutableArray<NSString *> *segmentPaths = [NSMutableArray arrayWithCapacity:segments.count];
    for (NSUInteger i = 0; i < segments.count; i++) {
        NSData *seg = segments[i];
        if (![seg isKindOfClass:[NSData class]]) {
            MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidFragment,
                               @"MUXL package segment is not data");
            return nil;
        }
        NSString *name = [NSString stringWithFormat:@"segment_%05lu.m4s", (unsigned long)i];
        NSString *segPath = [muxlDir stringByAppendingPathComponent:name];
        if (![seg writeToFile:segPath options:NSDataWritingAtomic error:error]) return nil;
        [segmentPaths addObject:segPath];
    }
    paths[@"segments"] = [segmentPaths copy];
    paths[@"directory"] = muxlDir;

    NSArray *s2paSegments = package[@"s2paSegments"];
    if ([s2paSegments isKindOfClass:[NSArray class]] && s2paSegments.count > 0) {
        if (s2paSegments.count != segments.count) {
            MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidArgument,
                               @"s2paSegments count must match segments");
            return nil;
        }
        NSMutableArray<NSString *> *s2paPaths = [NSMutableArray arrayWithCapacity:s2paSegments.count];
        for (NSUInteger i = 0; i < s2paSegments.count; i++) {
            NSData *seg = s2paSegments[i];
            if (![seg isKindOfClass:[NSData class]]) {
                MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidFragment,
                                   @"MUXL package s2pa segment is not data");
                return nil;
            }
            NSString *name = [NSString stringWithFormat:@"segment_%05lu.s2pa.m4s", (unsigned long)i];
            NSString *segPath = [muxlDir stringByAppendingPathComponent:name];
            if (![seg writeToFile:segPath options:NSDataWritingAtomic error:error]) return nil;
            [s2paPaths addObject:segPath];
        }
        paths[@"s2paSegments"] = [s2paPaths copy];
        paths[@"s2paHardBound"] = @YES;
    }
    return [paths copy];
}

+ (nullable NSDictionary<NSString *, id> *)hardBoundPackage:(NSDictionary<NSString *, id> *)package
                                               withKeyPair:(ATProtoSecp256k1KeyPair *)keyPair
                                                       did:(nullable NSString *)did
                                                 notBefore:(NSDate *)notBefore
                                                  notAfter:(NSDate *)notAfter
                                                     error:(NSError **)error {
    if (![package isKindOfClass:[NSDictionary class]] || !keyPair) {
        MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidArgument,
                           @"S2PA hard-bound package requires package and key pair");
        return nil;
    }
    NSArray *segments = package[@"segments"];
    if (![segments isKindOfClass:[NSArray class]] || segments.count == 0) {
        MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidArgument,
                           @"package has no MUXL segments to hard-bind");
        return nil;
    }
    NSMutableArray<NSData *> *bound = [NSMutableArray arrayWithCapacity:segments.count];
    for (NSData *seg in segments) {
        if (![seg isKindOfClass:[NSData class]]) {
            MUXLBridgeSetError(error, ATProtoMUXLTranscoderBridgeErrorInvalidFragment,
                               @"MUXL segment is not data");
            return nil;
        }
        NSData *signedSeg = [ATProtoMUXLPlayback presentationByHardBindingSegment:seg
                                                                      withKeyPair:keyPair
                                                                              did:did
                                                                        notBefore:notBefore
                                                                         notAfter:notAfter
                                                                            error:error];
        if (!signedSeg) return nil;
        [bound addObject:signedSeg];
    }
    NSMutableDictionary *out = [package mutableCopy];
    out[@"s2paSegments"] = [bound copy];
    out[@"s2paHardBound"] = @YES;
    return [out copy];
}

@end
