// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/ATProtoMUXLFMP4.h"
#import "MediaCore/ATProtoMUXLBox.h"
#import "MediaCore/ATProtoMUXLFragment.h"
#include <string.h>

NSString * const ATProtoMUXLFMP4ErrorDomain = @"com.atproto.muxl.fmp4";

/** ISO-639-2/T "und" packed into mdhd.language (5 bits per letter). */
static const uint16_t kMUXLLanguageUnd = (uint16_t)((('u' - 0x60) << 10) |
                                                    (('n' - 0x60) << 5) |
                                                    ('d' - 0x60));

typedef struct {
    uint32_t trackID;
    uint32_t timescale;
    BOOL video;
    uint32_t codedWidth;
    uint32_t codedHeight;
    uint32_t sampleRate;
    uint32_t channelCount;
    char fourcc[5];
    NSData * __unsafe_unretained description;
} MUXLFMP4Track;

static NSError *MUXLFMP4Error(ATProtoMUXLFMP4ErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoMUXLFMP4ErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void MUXLFMP4SetError(NSError **error, ATProtoMUXLFMP4ErrorCode code,
                             NSString *message) {
    if (error) *error = MUXLFMP4Error(code, message);
}

static void MUXLAppendUInt16BE(uint16_t value, NSMutableData *data) {
    uint8_t bytes[2] = {(uint8_t)(value >> 8), (uint8_t)value};
    [data appendBytes:bytes length:sizeof(bytes)];
}

static void MUXLAppendUInt32BE(uint32_t value, NSMutableData *data) {
    uint8_t bytes[4] = {
        (uint8_t)(value >> 24), (uint8_t)(value >> 16),
        (uint8_t)(value >> 8), (uint8_t)value
    };
    [data appendBytes:bytes length:sizeof(bytes)];
}

static void MUXLAppendInt16BE(int16_t value, NSMutableData *data) {
    MUXLAppendUInt16BE((uint16_t)value, data);
}

static uint32_t MUXLReadUInt32BE(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) | bytes[3];
}

static void MUXLWriteBoxHeader(NSMutableData *data, const char *type,
                               NSUInteger bodyLength) {
    MUXLAppendUInt32BE((uint32_t)(8 + bodyLength), data);
    [data appendBytes:type length:4];
}

static void MUXLWriteFullBoxHeader(NSMutableData *data, const char *type,
                                   uint8_t version, uint32_t flags,
                                   NSUInteger bodyAfterFullHeader) {
    MUXLAppendUInt32BE((uint32_t)(12 + bodyAfterFullHeader), data);
    [data appendBytes:type length:4];
    uint8_t vf[4] = {
        version,
        (uint8_t)((flags >> 16) & 0xFF),
        (uint8_t)((flags >> 8) & 0xFF),
        (uint8_t)(flags & 0xFF)
    };
    [data appendBytes:vf length:4];
}

static void MUXLAppendIdentityMatrix(NSMutableData *data) {
    static const uint32_t matrix[9] = {
        0x00010000, 0, 0,
        0, 0x00010000, 0,
        0, 0, 0x40000000
    };
    for (NSUInteger i = 0; i < 9; i++) {
        MUXLAppendUInt32BE(matrix[i], data);
    }
}

static BOOL MUXLFourCCFromCodec(NSString *codec, char outFourcc[5],
                                NSError **error) {
    if (![codec isKindOfClass:[NSString class]] || codec.length < 4) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorUnsupportedCodec,
                         @"MUXL fMP4 requires a WebCodecs codec string");
        return NO;
    }
    NSString *prefix = [codec substringToIndex:4];
    if (!([prefix isEqualToString:@"avc1"] ||
          [prefix isEqualToString:@"av01"] ||
          [prefix isEqualToString:@"mp4a"])) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorUnsupportedCodec,
                         [NSString stringWithFormat:
                          @"MUXL fMP4 unsupported codec fourcc from '%@'", codec]);
        return NO;
    }
    memcpy(outFourcc, prefix.UTF8String, 4);
    outFourcc[4] = '\0';
    return YES;
}

static BOOL MUXLExtractTrack(NSDictionary *catalog, MUXLFMP4Track *out,
                             NSError **error) {
    // Reuse catalog shape rules via box encoder (does not emit when invalid).
    if (![ATProtoMUXLBox uuidMuxlBoxWithCatalog:catalog error:error]) {
        if (error && *error) {
            // Remap domain for callers of the fMP4 API.
            NSString *message = (*error).localizedDescription ?: @"Invalid MUXL catalog";
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument, message);
        }
        return NO;
    }
    NSDictionary *video = catalog[@"video"];
    NSDictionary *audio = catalog[@"audio"];
    BOOL isVideo = video != nil;
    NSDictionary *media = isVideo ? video : audio;
    NSDictionary *renditions = media[@"renditions"];
    NSDictionary *track = renditions[renditions.allKeys.firstObject];
    NSDictionary *container = track[@"container"];
    char fourcc[5];
    if (!MUXLFourCCFromCodec(track[@"codec"], fourcc, error)) return NO;
    if (isVideo && memcmp(fourcc, "mp4a", 4) == 0) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorUnsupportedCodec,
                         @"MUXL fMP4 video track cannot use mp4a");
        return NO;
    }
    if (!isVideo && memcmp(fourcc, "mp4a", 4) != 0) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorUnsupportedCodec,
                         @"MUXL fMP4 audio track requires mp4a codec");
        return NO;
    }
    id description = track[@"description"];
    if (description != nil && ![description isKindOfClass:[NSData class]]) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                         @"MUXL track description must be bytes when present");
        return NO;
    }
    memset(out, 0, sizeof(*out));
    out->trackID = [container[@"trackId"] unsignedIntValue];
    out->timescale = [container[@"timescale"] unsignedIntValue];
    out->video = isVideo;
    out->codedWidth = isVideo ? [track[@"codedWidth"] unsignedIntValue] : 0;
    out->codedHeight = isVideo ? [track[@"codedHeight"] unsignedIntValue] : 0;
    out->sampleRate = isVideo ? 0 : [track[@"sampleRate"] unsignedIntValue];
    out->channelCount = isVideo ? 0 : [track[@"numberOfChannels"] unsignedIntValue];
    memcpy(out->fourcc, fourcc, 5);
    out->description = description;
    return YES;
}

static NSData *MUXLWrapCodecConfig(const char *boxType, NSData *payload) {
    NSMutableData *box = [NSMutableData dataWithCapacity:8 + payload.length];
    MUXLWriteBoxHeader(box, boxType, payload.length);
    [box appendData:payload];
    return box;
}

static NSData *MUXLBuildSampleEntry(const MUXLFMP4Track *track, NSError **error) {
    NSData *config = nil;
    if (track->description.length > 0) {
        if (memcmp(track->fourcc, "avc1", 4) == 0) {
            config = MUXLWrapCodecConfig("avcC", track->description);
        } else if (memcmp(track->fourcc, "av01", 4) == 0) {
            config = MUXLWrapCodecConfig("av1C", track->description);
        } else if (memcmp(track->fourcc, "mp4a", 4) == 0) {
            config = MUXLWrapCodecConfig("esds", track->description);
        }
    }

    NSMutableData *body = [NSMutableData data];
    uint8_t reserved6[6] = {0};
    [body appendBytes:reserved6 length:6];
    MUXLAppendUInt16BE(1, body); // data_reference_index

    if (track->video) {
        MUXLAppendUInt16BE(0, body); // pre_defined
        MUXLAppendUInt16BE(0, body); // reserved
        MUXLAppendUInt32BE(0, body);
        MUXLAppendUInt32BE(0, body);
        MUXLAppendUInt32BE(0, body);
        if (track->codedWidth > UINT16_MAX || track->codedHeight > UINT16_MAX) {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                             @"MUXL codedWidth/codedHeight exceed uint16");
            return nil;
        }
        MUXLAppendUInt16BE((uint16_t)track->codedWidth, body);
        MUXLAppendUInt16BE((uint16_t)track->codedHeight, body);
        MUXLAppendUInt32BE(0x00480000, body); // horizresolution
        MUXLAppendUInt32BE(0x00480000, body); // vertresolution
        MUXLAppendUInt32BE(0, body); // reserved
        MUXLAppendUInt16BE(1, body); // frame_count
        uint8_t compressor[32] = {0};
        [body appendBytes:compressor length:32];
        MUXLAppendUInt16BE(0x0018, body); // depth
        MUXLAppendInt16BE(-1, body); // pre_defined
    } else {
        MUXLAppendUInt32BE(0, body);
        MUXLAppendUInt32BE(0, body);
        if (track->channelCount > UINT16_MAX) {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                             @"MUXL numberOfChannels exceeds uint16");
            return nil;
        }
        MUXLAppendUInt16BE((uint16_t)track->channelCount, body);
        MUXLAppendUInt16BE(16, body); // samplesize
        MUXLAppendUInt16BE(0, body); // pre_defined
        MUXLAppendUInt16BE(0, body); // reserved
        MUXLAppendUInt32BE(track->sampleRate << 16, body);
    }

    if (config) [body appendData:config];

    NSMutableData *entry = [NSMutableData dataWithCapacity:8 + body.length];
    MUXLWriteBoxHeader(entry, track->fourcc, body.length);
    [entry appendData:body];
    return entry;
}

static NSData *MUXLBuildEmptyTable(const char *type, NSUInteger contentLength,
                                   void (^writer)(NSMutableData *data)) {
    NSMutableData *box = [NSMutableData data];
    MUXLWriteFullBoxHeader(box, type, 0, 0, contentLength);
    if (writer) writer(box);
    return box;
}

static NSData *MUXLBuildSTBL(const MUXLFMP4Track *track, NSError **error) {
    NSData *sampleEntry = MUXLBuildSampleEntry(track, error);
    if (!sampleEntry) return nil;

    NSMutableData *stsdBody = [NSMutableData data];
    MUXLAppendUInt32BE(1, stsdBody); // entry_count
    [stsdBody appendData:sampleEntry];
    NSMutableData *stsd = [NSMutableData data];
    MUXLWriteFullBoxHeader(stsd, "stsd", 0, 0, stsdBody.length);
    [stsd appendData:stsdBody];

    NSData *stts = MUXLBuildEmptyTable("stts", 4, ^(NSMutableData *d) {
        MUXLAppendUInt32BE(0, d); // entry_count
    });
    NSData *stsc = MUXLBuildEmptyTable("stsc", 4, ^(NSMutableData *d) {
        MUXLAppendUInt32BE(0, d);
    });
    NSData *stsz = MUXLBuildEmptyTable("stsz", 8, ^(NSMutableData *d) {
        MUXLAppendUInt32BE(0, d); // sample_size
        MUXLAppendUInt32BE(0, d); // sample_count
    });
    NSData *stco = MUXLBuildEmptyTable("stco", 4, ^(NSMutableData *d) {
        MUXLAppendUInt32BE(0, d);
    });

    NSMutableData *stblBody = [NSMutableData data];
    [stblBody appendData:stsd];
    [stblBody appendData:stts];
    [stblBody appendData:stsc];
    [stblBody appendData:stsz];
    [stblBody appendData:stco];

    NSMutableData *stbl = [NSMutableData data];
    MUXLWriteBoxHeader(stbl, "stbl", stblBody.length);
    [stbl appendData:stblBody];
    return stbl;
}

static NSData *MUXLBuildDINF(void) {
    NSMutableData *url = [NSMutableData data];
    MUXLWriteFullBoxHeader(url, "url ", 0, 1, 0); // self-contained

    NSMutableData *drefBody = [NSMutableData data];
    MUXLAppendUInt32BE(1, drefBody);
    [drefBody appendData:url];
    NSMutableData *dref = [NSMutableData data];
    MUXLWriteFullBoxHeader(dref, "dref", 0, 0, drefBody.length);
    [dref appendData:drefBody];

    NSMutableData *dinf = [NSMutableData data];
    MUXLWriteBoxHeader(dinf, "dinf", dref.length);
    [dinf appendData:dref];
    return dinf;
}

static NSData *MUXLBuildMINF(const MUXLFMP4Track *track, NSError **error) {
    NSMutableData *mediaHeader = [NSMutableData data];
    if (track->video) {
        // vmhd: graphicsmode + opcolor[3]
        MUXLWriteFullBoxHeader(mediaHeader, "vmhd", 0, 1, 8);
        MUXLAppendUInt16BE(0, mediaHeader);
        MUXLAppendUInt16BE(0, mediaHeader);
        MUXLAppendUInt16BE(0, mediaHeader);
        MUXLAppendUInt16BE(0, mediaHeader);
    } else {
        MUXLWriteFullBoxHeader(mediaHeader, "smhd", 0, 0, 4);
        MUXLAppendUInt16BE(0, mediaHeader); // balance
        MUXLAppendUInt16BE(0, mediaHeader); // reserved
    }

    NSData *dinf = MUXLBuildDINF();
    NSData *stbl = MUXLBuildSTBL(track, error);
    if (!stbl) return nil;

    NSMutableData *minfBody = [NSMutableData data];
    [minfBody appendData:mediaHeader];
    [minfBody appendData:dinf];
    [minfBody appendData:stbl];

    NSMutableData *minf = [NSMutableData data];
    MUXLWriteBoxHeader(minf, "minf", minfBody.length);
    [minf appendData:minfBody];
    return minf;
}

static NSData *MUXLBuildMDIA(const MUXLFMP4Track *track, NSError **error) {
    NSMutableData *mdhd = [NSMutableData data];
    MUXLWriteFullBoxHeader(mdhd, "mdhd", 0, 0, 20);
    MUXLAppendUInt32BE(0, mdhd); // creation
    MUXLAppendUInt32BE(0, mdhd); // modification
    MUXLAppendUInt32BE(track->timescale, mdhd);
    MUXLAppendUInt32BE(0, mdhd); // duration
    MUXLAppendUInt16BE(kMUXLLanguageUnd, mdhd);
    MUXLAppendUInt16BE(0, mdhd); // pre_defined

    NSMutableData *hdlrBody = [NSMutableData data];
    MUXLAppendUInt32BE(0, hdlrBody); // pre_defined
    [hdlrBody appendBytes:(track->video ? "vide" : "soun") length:4];
    MUXLAppendUInt32BE(0, hdlrBody);
    MUXLAppendUInt32BE(0, hdlrBody);
    MUXLAppendUInt32BE(0, hdlrBody);
    uint8_t nameNul = 0;
    [hdlrBody appendBytes:&nameNul length:1];
    NSMutableData *hdlr = [NSMutableData data];
    MUXLWriteFullBoxHeader(hdlr, "hdlr", 0, 0, hdlrBody.length);
    [hdlr appendData:hdlrBody];

    NSData *minf = MUXLBuildMINF(track, error);
    if (!minf) return nil;

    NSMutableData *mdiaBody = [NSMutableData data];
    [mdiaBody appendData:mdhd];
    [mdiaBody appendData:hdlr];
    [mdiaBody appendData:minf];

    NSMutableData *mdia = [NSMutableData data];
    MUXLWriteBoxHeader(mdia, "mdia", mdiaBody.length);
    [mdia appendData:mdiaBody];
    return mdia;
}

static NSData *MUXLBuildTRAK(const MUXLFMP4Track *track, NSError **error) {
    NSMutableData *tkhd = [NSMutableData data];
    MUXLWriteFullBoxHeader(tkhd, "tkhd", 0, 3, 84); // enabled | in_movie
    MUXLAppendUInt32BE(0, tkhd); // creation
    MUXLAppendUInt32BE(0, tkhd); // modification
    MUXLAppendUInt32BE(track->trackID, tkhd);
    MUXLAppendUInt32BE(0, tkhd); // reserved
    MUXLAppendUInt32BE(0, tkhd); // duration
    MUXLAppendUInt32BE(0, tkhd); // reserved
    MUXLAppendUInt32BE(0, tkhd); // reserved
    MUXLAppendUInt16BE(0, tkhd); // layer
    MUXLAppendUInt16BE(0, tkhd); // alternate_group
    MUXLAppendUInt16BE(track->video ? 0 : 0x0100, tkhd); // volume
    MUXLAppendUInt16BE(0, tkhd); // reserved
    MUXLAppendIdentityMatrix(tkhd);
    MUXLAppendUInt32BE(track->video ? (track->codedWidth << 16) : 0, tkhd);
    MUXLAppendUInt32BE(track->video ? (track->codedHeight << 16) : 0, tkhd);

    NSData *mdia = MUXLBuildMDIA(track, error);
    if (!mdia) return nil;

    NSMutableData *trakBody = [NSMutableData data];
    [trakBody appendData:tkhd];
    [trakBody appendData:mdia];

    NSMutableData *trak = [NSMutableData data];
    MUXLWriteBoxHeader(trak, "trak", trakBody.length);
    [trak appendData:trakBody];
    return trak;
}

static NSData *MUXLBuildMVHD(uint32_t nextTrackID) {
    NSMutableData *mvhd = [NSMutableData data];
    MUXLWriteFullBoxHeader(mvhd, "mvhd", 0, 0, 96);
    MUXLAppendUInt32BE(0, mvhd); // creation
    MUXLAppendUInt32BE(0, mvhd); // modification
    MUXLAppendUInt32BE(1000, mvhd); // timescale
    MUXLAppendUInt32BE(0, mvhd); // duration
    MUXLAppendUInt32BE(0x00010000, mvhd); // rate
    MUXLAppendUInt16BE(0x0100, mvhd); // volume
    MUXLAppendUInt16BE(0, mvhd); // reserved
    MUXLAppendUInt32BE(0, mvhd);
    MUXLAppendUInt32BE(0, mvhd);
    MUXLAppendIdentityMatrix(mvhd);
    for (NSUInteger i = 0; i < 6; i++) {
        MUXLAppendUInt32BE(0, mvhd); // pre_defined
    }
    MUXLAppendUInt32BE(nextTrackID, mvhd);
    return mvhd;
}

static NSData *MUXLBuildMVEX(NSArray<NSValue *> *tracks) {
    NSMutableData *mvexBody = [NSMutableData data];
    for (NSValue *value in tracks) {
        MUXLFMP4Track track;
        [value getValue:&track];
        NSMutableData *trex = [NSMutableData data];
        MUXLWriteFullBoxHeader(trex, "trex", 0, 0, 20);
        MUXLAppendUInt32BE(track.trackID, trex);
        MUXLAppendUInt32BE(1, trex); // default_sample_description_index
        MUXLAppendUInt32BE(0, trex);
        MUXLAppendUInt32BE(0, trex);
        MUXLAppendUInt32BE(0, trex);
        [mvexBody appendData:trex];
    }
    NSMutableData *mvex = [NSMutableData data];
    MUXLWriteBoxHeader(mvex, "mvex", mvexBody.length);
    [mvex appendData:mvexBody];
    return mvex;
}

static NSData *MUXLBuildFTYP(void) {
    // major(4) + minor(4) + brands muxl/isom/iso2 (12) = 20
    NSMutableData *ftyp = [NSMutableData data];
    MUXLWriteBoxHeader(ftyp, "ftyp", 20);
    [ftyp appendBytes:"muxl" length:4];
    MUXLAppendUInt32BE(0, ftyp);
    [ftyp appendBytes:"muxl" length:4];
    [ftyp appendBytes:"isom" length:4];
    [ftyp appendBytes:"iso2" length:4];
    return ftyp;
}


typedef struct {
    uint32_t duration;
    uint32_t size;
    uint64_t payloadOffset;
    BOOL sync;
    int32_t compositionTimeOffset;
    uint64_t baseMediaDecodeTime;
} MUXLFlatSample;

static void MUXLAppendInt32BEFlat(int32_t value, NSMutableData *data) {
    MUXLAppendUInt32BE((uint32_t)value, data);
}

static void MUXLAppendUInt64BEFlat(uint64_t value, NSMutableData *data) {
    MUXLAppendUInt32BE((uint32_t)(value >> 32), data);
    MUXLAppendUInt32BE((uint32_t)value, data);
}

static int32_t MUXLReadInt32BEFlat(const uint8_t *bytes) {
    return (int32_t)MUXLReadUInt32BE(bytes);
}

static BOOL MUXLParseFlatFragment(NSData *payload, NSUInteger *ioOffset,
                                  MUXLFlatSample *outSample, uint32_t *outTrackID,
                                  NSError **error) {
    const uint8_t *bytes = payload.bytes;
    NSUInteger length = payload.length;
    NSUInteger offset = *ioOffset;
    if (offset + 16 > length) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                         @"MUXL flat MP4 fragment is truncated");
        return NO;
    }
    uint32_t moofSize = MUXLReadUInt32BE(bytes + offset);
    if (moofSize < 8 || offset + moofSize + 8 > length ||
        memcmp(bytes + offset + 4, "moof", 4) != 0) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                         @"MUXL flat MP4 expected moof");
        return NO;
    }
    uint32_t mdatSize = MUXLReadUInt32BE(bytes + offset + moofSize);
    if (mdatSize < 8 || offset + moofSize + mdatSize > length ||
        memcmp(bytes + offset + moofSize + 4, "mdat", 4) != 0) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                         @"MUXL flat MP4 expected mdat after moof");
        return NO;
    }
    NSData *fragment = [payload subdataWithRange:NSMakeRange(offset, moofSize + mdatSize)];
    if (![ATProtoMUXLFragment validateFragment:fragment error:error]) {
        if (error && *error) {
            NSString *message = (*error).localizedDescription ?: @"Invalid MUXL fragment";
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure, message);
        }
        return NO;
    }

    NSUInteger p = offset + 8 + 16;
    p += 8;
    uint32_t trackID = MUXLReadUInt32BE(bytes + p + 12);
    p += 16;
    // tfdt version 1: size(4) type(4) version/flags(4) baseMediaDecodeTime(8)
    uint64_t baseDecodeTime = 0;
    if (p + 20 <= length && memcmp(bytes + p + 4, "tfdt", 4) == 0) {
        baseDecodeTime = ((uint64_t)MUXLReadUInt32BE(bytes + p + 12) << 32) |
                         MUXLReadUInt32BE(bytes + p + 16);
    }
    p += 20;
    uint32_t trunFlags = ((uint32_t)bytes[p + 9] << 16) |
                         ((uint32_t)bytes[p + 10] << 8) |
                         bytes[p + 11];
    BOOL hasCTO = (trunFlags & 0x000800) != 0;
    NSUInteger trunBody = p + 12;
    uint32_t duration = MUXLReadUInt32BE(bytes + trunBody + 8);
    uint32_t size = MUXLReadUInt32BE(bytes + trunBody + 12);
    uint32_t flags = MUXLReadUInt32BE(bytes + trunBody + 16);
    int32_t cto = 0;
    if (hasCTO) {
        cto = MUXLReadInt32BEFlat(bytes + trunBody + 20);
    }

    memset(outSample, 0, sizeof(*outSample));
    outSample->duration = duration;
    outSample->size = size;
    outSample->payloadOffset = (uint64_t)(offset + moofSize + 8);
    outSample->sync = (flags == 0x02000000);
    outSample->compositionTimeOffset = cto;
    outSample->baseMediaDecodeTime = baseDecodeTime;
    *outTrackID = trackID;
    *ioOffset = offset + moofSize + mdatSize;
    return YES;
}

static BOOL MUXLScanFlatSegments(NSArray<NSData *> *segments,
                                 NSMutableData *payloadOut,
                                 NSMutableDictionary<NSNumber *, NSValue *> *tracksOut,
                                 NSMutableDictionary<NSNumber *, NSMutableArray *> *samplesOut,
                                 NSMutableArray<NSData *> *descriptionRetain,
                                 NSError **error) {
    for (NSData *segment in segments) {
        if (![segment isKindOfClass:[NSData class]] || segment.length < 24) {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                             @"MUXL flat MP4 requires non-empty canonical segments");
            return NO;
        }
        NSUInteger segBase = payloadOut.length;
        [payloadOut appendData:segment];

        NSUInteger offset = segBase;
        NSUInteger end = payloadOut.length;
        if (offset + 24 > end || memcmp((const uint8_t *)payloadOut.bytes + offset + 4, "uuid", 4) != 0) {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                             @"MUXL flat MP4 segment must start with uuid-muxl");
            return NO;
        }
        uint32_t uuidSize = MUXLReadUInt32BE((const uint8_t *)payloadOut.bytes + offset);
        if (uuidSize < 24 || offset + uuidSize > end) {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                             @"MUXL flat MP4 uuid box is truncated");
            return NO;
        }
        NSData *uuidBox = [payloadOut subdataWithRange:NSMakeRange(offset, uuidSize)];
        NSDictionary *catalog = [ATProtoMUXLBox catalogFromUUIDMuxlBox:uuidBox error:error];
        if (!catalog) {
            if (error && *error) {
                NSString *message = (*error).localizedDescription ?: @"Invalid uuid-muxl";
                MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument, message);
            }
            return NO;
        }
        MUXLFMP4Track track;
        if (!MUXLExtractTrack(catalog, &track, error)) return NO;
        if (track.description) [descriptionRetain addObject:track.description];
        NSNumber *tid = @(track.trackID);
        NSValue *existing = tracksOut[tid];
        if (existing) {
            MUXLFMP4Track prior;
            [existing getValue:&prior];
            if (prior.video != track.video || prior.timescale != track.timescale ||
                memcmp(prior.fourcc, track.fourcc, 4) != 0) {
                MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                                 @"MUXL flat MP4 track metadata changed across segments");
                return NO;
            }
        } else {
            tracksOut[tid] = [NSValue valueWithBytes:&track objCType:@encode(MUXLFMP4Track)];
            samplesOut[tid] = [NSMutableArray array];
        }
        offset += uuidSize;

        if (offset >= end) {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                             @"MUXL flat MP4 segment has no fragments");
            return NO;
        }
        while (offset < end) {
            if (offset + 8 <= end &&
                memcmp((const uint8_t *)payloadOut.bytes + offset + 4, "uuid", 4) == 0) {
                MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                                 @"MUXL flat MP4 forbids nested uuid inside a segment blob");
                return NO;
            }
            MUXLFlatSample sample;
            uint32_t sampleTrackID = 0;
            if (!MUXLParseFlatFragment(payloadOut, &offset, &sample, &sampleTrackID, error)) {
                return NO;
            }
            if (sampleTrackID != track.trackID) {
                MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                                 @"MUXL flat MP4 fragment track_id must match segment catalog");
                return NO;
            }
            [samplesOut[tid] addObject:[NSValue valueWithBytes:&sample
                                                      objCType:@encode(MUXLFlatSample)]];
        }
    }
    return tracksOut.count > 0;
}

static NSData *MUXLBuildRunLengthTable(const char *type, uint8_t version,
                                       NSArray<NSValue *> *samples,
                                       BOOL useDuration) {
    NSMutableArray<NSNumber *> *counts = [NSMutableArray array];
    NSMutableArray<NSNumber *> *values = [NSMutableArray array];
    uint32_t runCount = 0;
    int64_t runValue = 0;
    BOOL haveRun = NO;
    for (NSValue *value in samples) {
        MUXLFlatSample sample;
        [value getValue:&sample];
        int64_t v = useDuration ? (int64_t)sample.duration
                                : (int64_t)sample.compositionTimeOffset;
        if (!haveRun || v != runValue) {
            if (haveRun) {
                [counts addObject:@(runCount)];
                [values addObject:@(runValue)];
            }
            runCount = 1;
            runValue = v;
            haveRun = YES;
        } else {
            runCount++;
        }
    }
    if (haveRun) {
        [counts addObject:@(runCount)];
        [values addObject:@(runValue)];
    }

    NSUInteger entryCount = counts.count;
    NSUInteger content = 4 + entryCount * 8;
    NSMutableData *box = [NSMutableData data];
    MUXLWriteFullBoxHeader(box, type, version, 0, content);
    MUXLAppendUInt32BE((uint32_t)entryCount, box);
    for (NSUInteger i = 0; i < entryCount; i++) {
        MUXLAppendUInt32BE(counts[i].unsignedIntValue, box);
        if (useDuration) {
            MUXLAppendUInt32BE((uint32_t)values[i].unsignedLongLongValue, box);
        } else {
            MUXLAppendInt32BEFlat((int32_t)values[i].longLongValue, box);
        }
    }
    return box;
}

static NSData *MUXLBuildFlatSTBL(const MUXLFMP4Track *track,
                                 NSArray<NSValue *> *samples,
                                 uint64_t co64Base,
                                 NSError **error) {
    NSData *sampleEntry = MUXLBuildSampleEntry(track, error);
    if (!sampleEntry) return nil;

    NSMutableData *stsdBody = [NSMutableData data];
    MUXLAppendUInt32BE(1, stsdBody);
    [stsdBody appendData:sampleEntry];
    NSMutableData *stsd = [NSMutableData data];
    MUXLWriteFullBoxHeader(stsd, "stsd", 0, 0, stsdBody.length);
    [stsd appendData:stsdBody];

    NSData *stts = MUXLBuildRunLengthTable("stts", 0, samples, YES);

    BOOL anyCTO = NO;
    BOOL allSync = YES;
    BOOL allSameSize = YES;
    uint32_t firstSize = 0;
    NSUInteger idx = 0;
    for (NSValue *value in samples) {
        MUXLFlatSample sample;
        [value getValue:&sample];
        if (sample.compositionTimeOffset != 0) anyCTO = YES;
        if (!sample.sync) allSync = NO;
        if (idx == 0) firstSize = sample.size;
        else if (sample.size != firstSize) allSameSize = NO;
        idx++;
    }
    NSData *ctts = nil;
    if (anyCTO) {
        ctts = MUXLBuildRunLengthTable("ctts", 1, samples, NO);
    }

    NSMutableData *stsz = [NSMutableData data];
    if (allSameSize) {
        MUXLWriteFullBoxHeader(stsz, "stsz", 0, 0, 8);
        MUXLAppendUInt32BE(firstSize, stsz);
        MUXLAppendUInt32BE((uint32_t)samples.count, stsz);
    } else {
        MUXLWriteFullBoxHeader(stsz, "stsz", 0, 0, 8 + samples.count * 4);
        MUXLAppendUInt32BE(0, stsz);
        MUXLAppendUInt32BE((uint32_t)samples.count, stsz);
        for (NSValue *value in samples) {
            MUXLFlatSample sample;
            [value getValue:&sample];
            MUXLAppendUInt32BE(sample.size, stsz);
        }
    }

    NSMutableData *stsc = [NSMutableData data];
    MUXLWriteFullBoxHeader(stsc, "stsc", 0, 0, 16);
    MUXLAppendUInt32BE(1, stsc);
    MUXLAppendUInt32BE(1, stsc);
    MUXLAppendUInt32BE(1, stsc);
    MUXLAppendUInt32BE(1, stsc);

    NSMutableData *co64 = [NSMutableData data];
    MUXLWriteFullBoxHeader(co64, "co64", 0, 0, 4 + samples.count * 8);
    MUXLAppendUInt32BE((uint32_t)samples.count, co64);
    for (NSValue *value in samples) {
        MUXLFlatSample sample;
        [value getValue:&sample];
        MUXLAppendUInt64BEFlat(co64Base + sample.payloadOffset, co64);
    }

    NSData *stss = nil;
    if (track->video && !allSync) {
        NSMutableArray<NSNumber *> *syncIndices = [NSMutableArray array];
        NSUInteger sampleIndex = 1;
        for (NSValue *value in samples) {
            MUXLFlatSample sample;
            [value getValue:&sample];
            if (sample.sync) [syncIndices addObject:@(sampleIndex)];
            sampleIndex++;
        }
        NSMutableData *box = [NSMutableData data];
        MUXLWriteFullBoxHeader(box, "stss", 0, 0, 4 + syncIndices.count * 4);
        MUXLAppendUInt32BE((uint32_t)syncIndices.count, box);
        for (NSNumber *n in syncIndices) {
            MUXLAppendUInt32BE(n.unsignedIntValue, box);
        }
        stss = box;
    }

    NSMutableData *stblBody = [NSMutableData data];
    [stblBody appendData:stsd];
    [stblBody appendData:stts];
    if (ctts) [stblBody appendData:ctts];
    [stblBody appendData:stsz];
    [stblBody appendData:stsc];
    [stblBody appendData:co64];
    if (stss) [stblBody appendData:stss];

    NSMutableData *stbl = [NSMutableData data];
    MUXLWriteBoxHeader(stbl, "stbl", stblBody.length);
    [stbl appendData:stblBody];
    return stbl;
}

static NSData *MUXLBuildFlatTRAK(const MUXLFMP4Track *track,
                                 NSArray<NSValue *> *samples,
                                 uint64_t co64Base,
                                 NSError **error) {
    uint64_t mediaDuration = 0;
    uint64_t presentationOffsetMedia = 0;
    BOOL haveOffset = NO;
    for (NSValue *value in samples) {
        MUXLFlatSample sample;
        [value getValue:&sample];
        mediaDuration += sample.duration;
        if (!haveOffset) {
            presentationOffsetMedia = sample.baseMediaDecodeTime;
            haveOffset = YES;
        }
    }
    if (mediaDuration > UINT32_MAX) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                         @"MUXL flat MP4 track duration exceeds uint32");
        return nil;
    }
    uint32_t duration32 = (uint32_t)mediaDuration;
    uint64_t emptyDurationMovie = 0;
    if (presentationOffsetMedia > 0 && track->timescale > 0) {
        emptyDurationMovie = (presentationOffsetMedia * 1000ull) / track->timescale;
        if (emptyDurationMovie > UINT32_MAX) {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                             @"MUXL flat MP4 presentation offset exceeds uint32 movie timescale");
            return nil;
        }
    }
    uint64_t mediaDurationMovie = (mediaDuration * 1000ull) / track->timescale;
    uint64_t tkhdDuration = mediaDurationMovie + emptyDurationMovie;
    if (tkhdDuration > UINT32_MAX) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                         @"MUXL flat MP4 track movie duration exceeds uint32");
        return nil;
    }
    uint32_t tkhdDuration32 = (uint32_t)tkhdDuration;

    NSMutableData *tkhd = [NSMutableData data];
    MUXLWriteFullBoxHeader(tkhd, "tkhd", 0, 3, 84);
    MUXLAppendUInt32BE(0, tkhd);
    MUXLAppendUInt32BE(0, tkhd);
    MUXLAppendUInt32BE(track->trackID, tkhd);
    MUXLAppendUInt32BE(0, tkhd);
    MUXLAppendUInt32BE(tkhdDuration32, tkhd);
    MUXLAppendUInt32BE(0, tkhd);
    MUXLAppendUInt32BE(0, tkhd);
    MUXLAppendUInt16BE(0, tkhd);
    MUXLAppendUInt16BE(0, tkhd);
    MUXLAppendUInt16BE(track->video ? 0 : 0x0100, tkhd);
    MUXLAppendUInt16BE(0, tkhd);
    MUXLAppendIdentityMatrix(tkhd);
    MUXLAppendUInt32BE(track->video ? (track->codedWidth << 16) : 0, tkhd);
    MUXLAppendUInt32BE(track->video ? (track->codedHeight << 16) : 0, tkhd);

    NSData *edts = nil;
    if (emptyDurationMovie > 0) {
        NSMutableData *elst = [NSMutableData data];
        // FullBox version 0: entry_count + 2 * (segment_duration u32 + media_time i32 + rate)
        MUXLWriteFullBoxHeader(elst, "elst", 0, 0, 4 + 2 * 12);
        MUXLAppendUInt32BE(2, elst);
        MUXLAppendUInt32BE((uint32_t)emptyDurationMovie, elst);
        MUXLAppendInt32BEFlat(-1, elst);
        MUXLAppendUInt16BE(0x0001, elst);
        MUXLAppendUInt16BE(0, elst);
        MUXLAppendUInt32BE((uint32_t)mediaDurationMovie, elst);
        MUXLAppendInt32BEFlat(0, elst);
        MUXLAppendUInt16BE(0x0001, elst);
        MUXLAppendUInt16BE(0, elst);
        NSMutableData *edtsBox = [NSMutableData data];
        MUXLWriteBoxHeader(edtsBox, "edts", elst.length);
        [edtsBox appendData:elst];
        edts = edtsBox;
    }

    NSMutableData *mdhd = [NSMutableData data];
    MUXLWriteFullBoxHeader(mdhd, "mdhd", 0, 0, 20);
    MUXLAppendUInt32BE(0, mdhd);
    MUXLAppendUInt32BE(0, mdhd);
    MUXLAppendUInt32BE(track->timescale, mdhd);
    MUXLAppendUInt32BE(duration32, mdhd);
    MUXLAppendUInt16BE(kMUXLLanguageUnd, mdhd);
    MUXLAppendUInt16BE(0, mdhd);

    NSMutableData *hdlrBody = [NSMutableData data];
    MUXLAppendUInt32BE(0, hdlrBody);
    [hdlrBody appendBytes:(track->video ? "vide" : "soun") length:4];
    MUXLAppendUInt32BE(0, hdlrBody);
    MUXLAppendUInt32BE(0, hdlrBody);
    MUXLAppendUInt32BE(0, hdlrBody);
    uint8_t nameNul = 0;
    [hdlrBody appendBytes:&nameNul length:1];
    NSMutableData *hdlr = [NSMutableData data];
    MUXLWriteFullBoxHeader(hdlr, "hdlr", 0, 0, hdlrBody.length);
    [hdlr appendData:hdlrBody];

    NSMutableData *mediaHeader = [NSMutableData data];
    if (track->video) {
        MUXLWriteFullBoxHeader(mediaHeader, "vmhd", 0, 1, 8);
        MUXLAppendUInt16BE(0, mediaHeader);
        MUXLAppendUInt16BE(0, mediaHeader);
        MUXLAppendUInt16BE(0, mediaHeader);
        MUXLAppendUInt16BE(0, mediaHeader);
    } else {
        MUXLWriteFullBoxHeader(mediaHeader, "smhd", 0, 0, 4);
        MUXLAppendUInt16BE(0, mediaHeader);
        MUXLAppendUInt16BE(0, mediaHeader);
    }

    NSData *dinf = MUXLBuildDINF();
    NSData *stbl = MUXLBuildFlatSTBL(track, samples, co64Base, error);
    if (!stbl) return nil;

    NSMutableData *minfBody = [NSMutableData data];
    [minfBody appendData:mediaHeader];
    [minfBody appendData:dinf];
    [minfBody appendData:stbl];
    NSMutableData *minf = [NSMutableData data];
    MUXLWriteBoxHeader(minf, "minf", minfBody.length);
    [minf appendData:minfBody];

    NSMutableData *mdiaBody = [NSMutableData data];
    [mdiaBody appendData:mdhd];
    [mdiaBody appendData:hdlr];
    [mdiaBody appendData:minf];
    NSMutableData *mdia = [NSMutableData data];
    MUXLWriteBoxHeader(mdia, "mdia", mdiaBody.length);
    [mdia appendData:mdiaBody];

    NSMutableData *trakBody = [NSMutableData data];
    [trakBody appendData:tkhd];
    if (edts) [trakBody appendData:edts];
    [trakBody appendData:mdia];
    NSMutableData *trak = [NSMutableData data];
    MUXLWriteBoxHeader(trak, "trak", trakBody.length);
    [trak appendData:trakBody];
    return trak;
}

static NSData *MUXLBuildFlatMVHD(uint32_t nextTrackID, uint32_t durationMovie) {
    NSMutableData *mvhd = [NSMutableData data];
    MUXLWriteFullBoxHeader(mvhd, "mvhd", 0, 0, 96);
    MUXLAppendUInt32BE(0, mvhd);
    MUXLAppendUInt32BE(0, mvhd);
    MUXLAppendUInt32BE(1000, mvhd);
    MUXLAppendUInt32BE(durationMovie, mvhd);
    MUXLAppendUInt32BE(0x00010000, mvhd);
    MUXLAppendUInt16BE(0x0100, mvhd);
    MUXLAppendUInt16BE(0, mvhd);
    MUXLAppendUInt32BE(0, mvhd);
    MUXLAppendUInt32BE(0, mvhd);
    MUXLAppendIdentityMatrix(mvhd);
    for (NSUInteger i = 0; i < 6; i++) {
        MUXLAppendUInt32BE(0, mvhd);
    }
    MUXLAppendUInt32BE(nextTrackID, mvhd);
    return mvhd;
}

static NSData *MUXLBuildFlatMOOV(NSArray<NSNumber *> *sortedTrackIDs,
                                 NSDictionary<NSNumber *, NSValue *> *tracks,
                                 NSDictionary<NSNumber *, NSMutableArray *> *samples,
                                 uint64_t co64Base,
                                 NSError **error) {
    uint32_t maxTrackID = 0;
    uint32_t maxMovieDuration = 0;
    for (NSNumber *tid in sortedTrackIDs) {
        MUXLFMP4Track track;
        [tracks[tid] getValue:&track];
        if (track.trackID > maxTrackID) maxTrackID = track.trackID;
        uint64_t mediaDuration = 0;
        uint64_t presentationOffsetMedia = 0;
        BOOL haveOffset = NO;
        for (NSValue *value in samples[tid]) {
            MUXLFlatSample sample;
            [value getValue:&sample];
            mediaDuration += sample.duration;
            if (!haveOffset) {
                presentationOffsetMedia = sample.baseMediaDecodeTime;
                haveOffset = YES;
            }
        }
        uint64_t movieDuration = (mediaDuration * 1000ull) / track.timescale;
        if (presentationOffsetMedia > 0 && track.timescale > 0) {
            movieDuration += (presentationOffsetMedia * 1000ull) / track.timescale;
        }
        if (movieDuration > UINT32_MAX) {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                             @"MUXL flat MP4 movie duration exceeds uint32");
            return nil;
        }
        if ((uint32_t)movieDuration > maxMovieDuration) {
            maxMovieDuration = (uint32_t)movieDuration;
        }
    }

    NSMutableData *moovBody = [NSMutableData data];
    [moovBody appendData:MUXLBuildFlatMVHD(maxTrackID + 1, maxMovieDuration)];
    for (NSNumber *tid in sortedTrackIDs) {
        MUXLFMP4Track track;
        [tracks[tid] getValue:&track];
        NSData *trak = MUXLBuildFlatTRAK(&track, samples[tid], co64Base, error);
        if (!trak) return nil;
        [moovBody appendData:trak];
    }
    NSMutableData *moov = [NSMutableData data];
    MUXLWriteBoxHeader(moov, "moov", moovBody.length);
    [moov appendData:moovBody];
    return moov;
}

@implementation ATProtoMUXLFMP4

+ (nullable NSData *)initSegmentWithCatalogs:(NSArray<NSDictionary *> *)catalogs
                                       error:(NSError **)error {
    if (![catalogs isKindOfClass:[NSArray class]] || catalogs.count == 0) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                         @"MUXL fMP4 init requires at least one catalog");
        return nil;
    }

    NSMutableArray<NSValue *> *tracks = [NSMutableArray arrayWithCapacity:catalogs.count];
    NSMutableSet<NSNumber *> *seenIDs = [NSMutableSet set];
    uint32_t maxTrackID = 0;

    for (NSDictionary *catalog in catalogs) {
        MUXLFMP4Track track;
        if (!MUXLExtractTrack(catalog, &track, error)) return nil;
        NSNumber *tid = @(track.trackID);
        if ([seenIDs containsObject:tid]) {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorDuplicateTrackID,
                             @"MUXL fMP4 catalogs must use unique trackId values");
            return nil;
        }
        [seenIDs addObject:tid];
        if (track.trackID > maxTrackID) maxTrackID = track.trackID;
        [tracks addObject:[NSValue valueWithBytes:&track objCType:@encode(MUXLFMP4Track)]];
    }

    [tracks sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        MUXLFMP4Track ta, tb;
        [a getValue:&ta];
        [b getValue:&tb];
        if (ta.trackID < tb.trackID) return NSOrderedAscending;
        if (ta.trackID > tb.trackID) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    // Retain description NSData while building (struct holds unretained ptr).
    NSMutableArray<NSData *> *descriptionRetain = [NSMutableArray array];
    for (NSValue *value in tracks) {
        MUXLFMP4Track track;
        [value getValue:&track];
        if (track.description) [descriptionRetain addObject:track.description];
    }

    NSMutableData *moovBody = [NSMutableData data];
    [moovBody appendData:MUXLBuildMVHD(maxTrackID + 1)];
    for (NSValue *value in tracks) {
        MUXLFMP4Track track;
        [value getValue:&track];
        NSData *trak = MUXLBuildTRAK(&track, error);
        if (!trak) return nil;
        [moovBody appendData:trak];
    }
    [moovBody appendData:MUXLBuildMVEX(tracks)];

    NSMutableData *moov = [NSMutableData data];
    MUXLWriteBoxHeader(moov, "moov", moovBody.length);
    [moov appendData:moovBody];

    NSMutableData *init = [NSMutableData data];
    [init appendData:MUXLBuildFTYP()];
    [init appendData:moov];
    (void)descriptionRetain;
    return init;
}


+ (nullable NSData *)flatMP4WithSegments:(NSArray<NSData *> *)segments
                                   error:(NSError **)error {
    if (![segments isKindOfClass:[NSArray class]] || segments.count == 0) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                         @"MUXL flat MP4 requires at least one segment");
        return nil;
    }

    NSMutableData *payload = [NSMutableData data];
    NSMutableDictionary<NSNumber *, NSValue *> *tracks = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSMutableArray *> *samples = [NSMutableDictionary dictionary];
    NSMutableArray<NSData *> *descriptionRetain = [NSMutableArray array];
    if (!MUXLScanFlatSegments(segments, payload, tracks, samples, descriptionRetain, error)) {
        return nil;
    }

    NSArray<NSNumber *> *sortedIDs =
        [[tracks allKeys] sortedArrayUsingSelector:@selector(compare:)];

    NSData *ftyp = MUXLBuildFTYP();
    // First pass: size-stable moov with base 0; second pass with real co64 base.
    NSData *moovProbe = MUXLBuildFlatMOOV(sortedIDs, tracks, samples, 0, error);
    if (!moovProbe) return nil;
    uint64_t co64Base = (uint64_t)ftyp.length + (uint64_t)moovProbe.length + 16ull;
    NSData *moov = MUXLBuildFlatMOOV(sortedIDs, tracks, samples, co64Base, error);
    if (!moov) return nil;
    if (moov.length != moovProbe.length) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                         @"MUXL flat MP4 moov size changed after co64 rebasing");
        return nil;
    }

    // Outer mdat uses 64-bit largesize form (size==1, type, largesize).
    uint64_t mdatBoxSize = 16ull + (uint64_t)payload.length;
    NSMutableData *mdat = [NSMutableData dataWithCapacity:(NSUInteger)mdatBoxSize];
    MUXLAppendUInt32BE(1, mdat); // size == 1 signals largesize
    [mdat appendBytes:"mdat" length:4];
    MUXLAppendUInt64BEFlat(mdatBoxSize, mdat);
    [mdat appendData:payload];

    NSMutableData *out = [NSMutableData dataWithCapacity:ftyp.length + moov.length + mdat.length];
    [out appendData:ftyp];
    [out appendData:moov];
    [out appendData:mdat];
    (void)descriptionRetain;
    return out;
}

+ (nullable NSData *)presentationWithInit:(NSData *)initSegment
                                 segments:(NSArray<NSData *> *)segments
                                    error:(NSError **)error {
    if (![initSegment isKindOfClass:[NSData class]] || initSegment.length == 0 ||
        ![self validateInitSegment:initSegment error:error]) {
        if (error && !*error) {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                             @"MUXL fMP4 presentation requires a valid init segment");
        }
        return nil;
    }
    if (![segments isKindOfClass:[NSArray class]] || segments.count == 0) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                         @"MUXL fMP4 presentation requires at least one segment");
        return nil;
    }
    NSMutableData *out = [initSegment mutableCopy];
    for (NSData *segment in segments) {
        if (![segment isKindOfClass:[NSData class]] || segment.length == 0) {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidArgument,
                             @"MUXL fMP4 segments must be non-empty data");
            return nil;
        }
        [out appendData:segment];
    }
    return out;
}

+ (BOOL)validateInitSegment:(NSData *)initSegment error:(NSError **)error {
    if (![initSegment isKindOfClass:[NSData class]] || initSegment.length < 16) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                         @"MUXL fMP4 init is truncated");
        return NO;
    }
    const uint8_t *bytes = initSegment.bytes;
    NSUInteger length = initSegment.length;
    NSUInteger offset = 0;
    BOOL sawFtyp = NO;
    BOOL sawMoov = NO;
    NSUInteger trakCount = 0;
    BOOL sawMvhd = NO;
    BOOL sawMvex = NO;

    while (offset + 8 <= length) {
        uint32_t size = MUXLReadUInt32BE(bytes + offset);
        if (size < 8 || offset + size > length) {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                             @"MUXL fMP4 init has an invalid box size");
            return NO;
        }
        const char *type = (const char *)(bytes + offset + 4);
        if (memcmp(type, "free", 4) == 0 || memcmp(type, "skip", 4) == 0 ||
            memcmp(type, "udta", 4) == 0 || memcmp(type, "meta", 4) == 0 ||
            memcmp(type, "iods", 4) == 0) {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                             @"MUXL fMP4 init forbids free/skip/udta/meta/iods");
            return NO;
        }
        if (memcmp(type, "ftyp", 4) == 0) {
            if (sawFtyp || offset != 0 || size < 20) {
                MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                                 @"MUXL fMP4 requires a leading ftyp");
                return NO;
            }
            if (memcmp(bytes + offset + 8, "muxl", 4) != 0 ||
                MUXLReadUInt32BE(bytes + offset + 12) != 0 ||
                memcmp(bytes + offset + 16, "muxl", 4) != 0 ||
                memcmp(bytes + offset + 20, "isom", 4) != 0 ||
                memcmp(bytes + offset + 24, "iso2", 4) != 0) {
                MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                                 @"MUXL fMP4 ftyp brands must be muxl/isom/iso2");
                return NO;
            }
            sawFtyp = YES;
        } else if (memcmp(type, "moov", 4) == 0) {
            if (!sawFtyp || sawMoov) {
                MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                                 @"MUXL fMP4 requires exactly one moov after ftyp");
                return NO;
            }
            sawMoov = YES;
            NSUInteger inner = offset + 8;
            NSUInteger end = offset + size;
            while (inner + 8 <= end) {
                uint32_t isize = MUXLReadUInt32BE(bytes + inner);
                if (isize < 8 || inner + isize > end) {
                    MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                                     @"MUXL fMP4 moov child size is invalid");
                    return NO;
                }
                const char *itype = (const char *)(bytes + inner + 4);
                if (memcmp(itype, "mvhd", 4) == 0) {
                    if (sawMvhd || isize < 108) {
                        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                                         @"MUXL fMP4 mvhd missing or malformed");
                        return NO;
                    }
                    // timescale at fullbox+8+8 = inner+12+8 = inner+20
                    if (MUXLReadUInt32BE(bytes + inner + 20) != 1000 ||
                        MUXLReadUInt32BE(bytes + inner + 24) != 0) {
                        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                                         @"MUXL fMP4 mvhd must use timescale 1000 and duration 0");
                        return NO;
                    }
                    sawMvhd = YES;
                } else if (memcmp(itype, "trak", 4) == 0) {
                    if (!sawMvhd || sawMvex) {
                        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                                         @"MUXL fMP4 trak must follow mvhd and precede mvex");
                        return NO;
                    }
                    // Require empty stts (entry_count == 0) somewhere in trak.
                    BOOL foundEmptyStts = NO;
                    NSUInteger tend = inner + isize;
                    for (NSUInteger s = inner + 8; s + 16 <= tend; s++) {
                        if (memcmp(bytes + s, "stts", 4) == 0 && s >= 4) {
                            uint32_t sttsSize = MUXLReadUInt32BE(bytes + s - 4);
                            if (sttsSize >= 16 && s - 4 + sttsSize <= tend &&
                                MUXLReadUInt32BE(bytes + s + 8) == 0) {
                                foundEmptyStts = YES;
                                break;
                            }
                        }
                    }
                    if (!foundEmptyStts) {
                        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                                         @"MUXL fMP4 trak must contain empty stts");
                        return NO;
                    }
                    trakCount++;
                } else if (memcmp(itype, "mvex", 4) == 0) {
                    if (!sawMvhd || trakCount == 0 || sawMvex) {
                        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                                         @"MUXL fMP4 mvex must follow all trak boxes");
                        return NO;
                    }
                    sawMvex = YES;
                } else if (memcmp(itype, "udta", 4) == 0 || memcmp(itype, "meta", 4) == 0 ||
                           memcmp(itype, "iods", 4) == 0 || memcmp(itype, "free", 4) == 0 ||
                           memcmp(itype, "skip", 4) == 0) {
                    MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                                     @"MUXL fMP4 moov forbids udta/meta/iods/free/skip");
                    return NO;
                }
                inner += isize;
            }
            if (!sawMvhd || !sawMvex || trakCount == 0 || inner != end) {
                MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                                 @"MUXL fMP4 moov must be mvhd + trak+ + mvex");
                return NO;
            }
        } else {
            MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                             @"MUXL fMP4 init may only contain ftyp and moov");
            return NO;
        }
        offset += size;
    }
    if (!sawFtyp || !sawMoov || offset != length) {
        MUXLFMP4SetError(error, ATProtoMUXLFMP4ErrorInvalidStructure,
                         @"MUXL fMP4 init must be exactly ftyp + moov");
        return NO;
    }
    return YES;
}

@end
