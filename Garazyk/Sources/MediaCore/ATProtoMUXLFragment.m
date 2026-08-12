// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoMUXLFragment.h"
#include <string.h>

NSString * const ATProtoMUXLFragmentErrorDomain = @"com.atproto.muxl.fragment";

static const uint32_t kMUXLTFHDDefaultBaseIsMoof = 0x020000;
static const uint32_t kMUXLTrunDataOffset = 0x000001;
static const uint32_t kMUXLTrunSampleDuration = 0x000100;
static const uint32_t kMUXLTrunSampleSize = 0x000200;
static const uint32_t kMUXLTrunSampleFlags = 0x000400;
static const uint32_t kMUXLTrunCompositionOffset = 0x000800;
static const uint32_t kMUXLSampleFlagsSync = 0x02000000;
static const uint32_t kMUXLSampleFlagsNonSync = 0x01010000;

static NSError *MUXLFragmentError(ATProtoMUXLFragmentErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoMUXLFragmentErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void MUXLFragmentSetError(NSError **error, ATProtoMUXLFragmentErrorCode code,
                                 NSString *message) {
    if (error) *error = MUXLFragmentError(code, message);
}

static void MUXLAppendUInt32BE(uint32_t value, NSMutableData *data) {
    uint8_t bytes[4] = {
        (uint8_t)(value >> 24), (uint8_t)(value >> 16),
        (uint8_t)(value >> 8), (uint8_t)value
    };
    [data appendBytes:bytes length:sizeof(bytes)];
}

static void MUXLAppendUInt64BE(uint64_t value, NSMutableData *data) {
    uint8_t bytes[8] = {
        (uint8_t)(value >> 56), (uint8_t)(value >> 48),
        (uint8_t)(value >> 40), (uint8_t)(value >> 32),
        (uint8_t)(value >> 24), (uint8_t)(value >> 16),
        (uint8_t)(value >> 8), (uint8_t)value
    };
    [data appendBytes:bytes length:sizeof(bytes)];
}

static void MUXLAppendInt32BE(int32_t value, NSMutableData *data) {
    MUXLAppendUInt32BE((uint32_t)value, data);
}

static uint32_t MUXLReadUInt32BE(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) | bytes[3];
}

static void MUXLWriteBoxHeader(NSMutableData *data, const char *type, NSUInteger bodyLength) {
    MUXLAppendUInt32BE((uint32_t)(8 + bodyLength), data);
    [data appendBytes:type length:4];
}

static void MUXLWriteFullBoxHeader(NSMutableData *data, const char *type,
                                   uint8_t version, uint32_t flags,
                                   NSUInteger bodyAfterFullHeader) {
    // size covers header(8) + version/flags(4) + remaining body
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

@implementation ATProtoMUXLFragmentSample
@end

@implementation ATProtoMUXLFragment

+ (nullable NSData *)fragmentWithSample:(ATProtoMUXLFragmentSample *)sample
                                  error:(NSError **)error {
    if (![sample isKindOfClass:[ATProtoMUXLFragmentSample class]] ||
        sample.trackID == 0 ||
        sample.sequenceNumber == 0 ||
        sample.sampleDuration == 0 ||
        ![sample.sampleBytes isKindOfClass:[NSData class]] ||
        sample.sampleBytes.length == 0 ||
        sample.sampleBytes.length > UINT32_MAX) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidArgument,
                             @"MUXL fragment requires positive track/sequence/duration and sample bytes");
        return nil;
    }

    BOOL includeCTO = sample.compositionTimeOffset != 0;
    uint32_t trunFlags = kMUXLTrunDataOffset | kMUXLTrunSampleDuration |
                         kMUXLTrunSampleSize | kMUXLTrunSampleFlags;
    if (includeCTO) {
        trunFlags |= kMUXLTrunCompositionOffset;
    }

    NSMutableData *mfhd = [NSMutableData data];
    MUXLWriteFullBoxHeader(mfhd, "mfhd", 0, 0, 4);
    MUXLAppendUInt32BE(sample.sequenceNumber, mfhd);

    NSMutableData *tfhd = [NSMutableData data];
    MUXLWriteFullBoxHeader(tfhd, "tfhd", 0, kMUXLTFHDDefaultBaseIsMoof, 4);
    MUXLAppendUInt32BE(sample.trackID, tfhd);

    NSMutableData *tfdt = [NSMutableData data];
    MUXLWriteFullBoxHeader(tfdt, "tfdt", 1, 0, 8);
    MUXLAppendUInt64BE(sample.baseMediaDecodeTime, tfdt);

    // sample_count(4) + data_offset(4) + duration(4) + size(4) + flags(4) [+ cto(4)]
    NSUInteger trunContentLength = 4 + 4 + 4 + 4 + 4 + (includeCTO ? 4 : 0);
    NSUInteger trunBoxLength = 12 + trunContentLength;
    NSUInteger trafBodyLength = tfhd.length + tfdt.length + trunBoxLength;
    NSUInteger trafBoxLength = 8 + trafBodyLength;
    NSUInteger moofBodyLength = mfhd.length + trafBoxLength;
    NSUInteger moofBoxLength = 8 + moofBodyLength;
    uint32_t dataOffset = (uint32_t)moofBoxLength;

    NSMutableData *trun = [NSMutableData data];
    MUXLWriteFullBoxHeader(trun, "trun", includeCTO ? 1 : 0, trunFlags, trunContentLength);
    MUXLAppendUInt32BE(1, trun);
    MUXLAppendUInt32BE(dataOffset, trun);
    MUXLAppendUInt32BE(sample.sampleDuration, trun);
    MUXLAppendUInt32BE((uint32_t)sample.sampleBytes.length, trun);
    MUXLAppendUInt32BE(sample.syncSample ? kMUXLSampleFlagsSync : kMUXLSampleFlagsNonSync, trun);
    if (includeCTO) {
        MUXLAppendInt32BE(sample.compositionTimeOffset, trun);
    }

    NSMutableData *traf = [NSMutableData data];
    MUXLWriteBoxHeader(traf, "traf", tfhd.length + tfdt.length + trun.length);
    [traf appendData:tfhd];
    [traf appendData:tfdt];
    [traf appendData:trun];

    NSMutableData *moof = [NSMutableData data];
    MUXLWriteBoxHeader(moof, "moof", mfhd.length + traf.length);
    [moof appendData:mfhd];
    [moof appendData:traf];

    if (moof.length != moofBoxLength) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"Internal MUXL moof size mismatch");
        return nil;
    }

    NSMutableData *mdat = [NSMutableData data];
    MUXLWriteBoxHeader(mdat, "mdat", sample.sampleBytes.length);
    [mdat appendData:sample.sampleBytes];

    NSMutableData *fragment = [NSMutableData dataWithCapacity:moof.length + mdat.length];
    [fragment appendData:moof];
    [fragment appendData:mdat];
    return fragment;
}

+ (BOOL)validateFragment:(NSData *)fragment error:(NSError **)error {
    if (![fragment isKindOfClass:[NSData class]] || fragment.length < 16) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL fragment is truncated");
        return NO;
    }
    const uint8_t *bytes = fragment.bytes;
    NSUInteger length = fragment.length;
    NSUInteger offset = 0;

    uint32_t moofSize = MUXLReadUInt32BE(bytes + offset);
    if (moofSize < 8 || moofSize > length || memcmp(bytes + offset + 4, "moof", 4) != 0) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL fragment must start with moof");
        return NO;
    }
    NSUInteger moofEnd = offset + moofSize;
    offset += 8;

    // mfhd
    if (offset + 16 > moofEnd || MUXLReadUInt32BE(bytes + offset) != 16 ||
        memcmp(bytes + offset + 4, "mfhd", 4) != 0 ||
        bytes[offset + 8] != 0) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL moof requires version-0 mfhd");
        return NO;
    }
    uint32_t sequence = MUXLReadUInt32BE(bytes + offset + 12);
    if (sequence == 0) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL mfhd sequence_number must be 1-based");
        return NO;
    }
    offset += 16;

    // traf
    if (offset + 8 > moofEnd) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL moof is missing traf");
        return NO;
    }
    uint32_t trafSize = MUXLReadUInt32BE(bytes + offset);
    if (trafSize < 8 || offset + trafSize > moofEnd ||
        memcmp(bytes + offset + 4, "traf", 4) != 0) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL moof requires exactly one traf");
        return NO;
    }
    NSUInteger trafEnd = offset + trafSize;
    offset += 8;

    // tfhd
    if (offset + 16 > trafEnd || MUXLReadUInt32BE(bytes + offset) != 16 ||
        memcmp(bytes + offset + 4, "tfhd", 4) != 0 || bytes[offset + 8] != 0) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL traf requires version-0 tfhd");
        return NO;
    }
    uint32_t tfhdFlags = ((uint32_t)bytes[offset + 9] << 16) |
                         ((uint32_t)bytes[offset + 10] << 8) |
                         bytes[offset + 11];
    if (tfhdFlags != kMUXLTFHDDefaultBaseIsMoof ||
        MUXLReadUInt32BE(bytes + offset + 12) == 0) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL tfhd requires default-base-is-moof and positive track_id");
        return NO;
    }
    offset += 16;

    // tfdt version 1
    if (offset + 20 > trafEnd || MUXLReadUInt32BE(bytes + offset) != 20 ||
        memcmp(bytes + offset + 4, "tfdt", 4) != 0 || bytes[offset + 8] != 1) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL traf requires version-1 tfdt");
        return NO;
    }
    offset += 20;

    // trun
    if (offset + 12 > trafEnd) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL traf is missing trun");
        return NO;
    }
    uint32_t trunSize = MUXLReadUInt32BE(bytes + offset);
    if (trunSize < 12 || offset + trunSize > trafEnd ||
        memcmp(bytes + offset + 4, "trun", 4) != 0) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL traf requires trun");
        return NO;
    }
    uint8_t trunVersion = bytes[offset + 8];
    uint32_t trunFlags = ((uint32_t)bytes[offset + 9] << 16) |
                         ((uint32_t)bytes[offset + 10] << 8) |
                         bytes[offset + 11];
    uint32_t requiredFlags = kMUXLTrunDataOffset | kMUXLTrunSampleDuration |
                             kMUXLTrunSampleSize | kMUXLTrunSampleFlags;
    if ((trunFlags & requiredFlags) != requiredFlags) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL trun is missing required sample fields");
        return NO;
    }
    BOOL hasCTO = (trunFlags & kMUXLTrunCompositionOffset) != 0;
    if (hasCTO && trunVersion != 1) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL trun with composition offsets must be version 1");
        return NO;
    }
    NSUInteger trunBody = offset + 12;
    if (trunBody + 4 > offset + trunSize) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL trun is truncated");
        return NO;
    }
    uint32_t sampleCount = MUXLReadUInt32BE(bytes + trunBody);
    if (sampleCount != 1) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL trun must carry exactly one sample");
        return NO;
    }
    uint32_t dataOffset = MUXLReadUInt32BE(bytes + trunBody + 4);
    if (dataOffset != moofSize) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL trun data_offset must equal moof size");
        return NO;
    }
    uint32_t sampleSize = MUXLReadUInt32BE(bytes + trunBody + 12);
    uint32_t sampleFlags = MUXLReadUInt32BE(bytes + trunBody + 16);
    if (sampleFlags != kMUXLSampleFlagsSync && sampleFlags != kMUXLSampleFlagsNonSync) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL sample_flags must be the normative sync/non-sync values");
        return NO;
    }
    if (offset + trunSize != trafEnd) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL traf has trailing boxes after trun");
        return NO;
    }
    if (trafEnd != moofEnd) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL moof has trailing boxes after traf");
        return NO;
    }

    // mdat
    offset = moofEnd;
    if (offset + 8 > length || memcmp(bytes + offset + 4, "mdat", 4) != 0) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL fragment requires trailing mdat");
        return NO;
    }
    uint32_t mdatSize = MUXLReadUInt32BE(bytes + offset);
    if (mdatSize < 8 || offset + mdatSize != length ||
        mdatSize - 8 != sampleSize) {
        MUXLFragmentSetError(error, ATProtoMUXLFragmentErrorInvalidStructure,
                             @"MUXL mdat size must match trun sample_size with no trailing data");
        return NO;
    }
    return YES;
}

@end
