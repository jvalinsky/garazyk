// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMUXLFMP4.h

 @abstract Deterministic MUXL fMP4 init-header synthesis.

 @discussion Builds the presentation init segment from one or more canonical
 single-track MUXL catalogs per https://dasl.ing/muxl.html:

   Init = [ftyp][moov]

 where `ftyp` uses brands `muxl`/`isom`/`iso2`, and `moov` carries empty sample
 tables plus `mvex`/`trex` so minted `[moof][mdat]` fragments remain intelligible
 as a CMAF stream. Canonical MUXL segment bytes are never rewritten; callers
 prepend this header via `presentationWithInit:segments:error:`.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoMUXLFMP4ErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoMUXLFMP4ErrorCode) {
    ATProtoMUXLFMP4ErrorInvalidArgument = 1,
    ATProtoMUXLFMP4ErrorUnsupportedCodec = 2,
    ATProtoMUXLFMP4ErrorInvalidStructure = 3,
    ATProtoMUXLFMP4ErrorDuplicateTrackID = 4,
};

/**
 Synthesizes MUXL fMP4 presentation headers from catalogs.
 */
@interface ATProtoMUXLFMP4 : NSObject

/**
 Builds `ftyp` + `moov` for the given catalogs.

 Each catalog must be a canonical single-track MUXL catalog (video xor audio,
 exactly one rendition). Tracks are ordered by ascending `trackId`. Supported
 sample-entry fourccs derived from WebCodecs codec strings: `avc1`, `av01`,
 `mp4a`. Optional `description` (avcC/av1C/esds/dOps bytes) is wrapped in the
 matching codec-config box when present.
 */
+ (nullable NSData *)initSegmentWithCatalogs:(NSArray<NSDictionary *> *)catalogs
                                       error:(NSError **)error;

/**
 Builds a Flat MP4 presentation from concatenated canonical MUXL segments.

 Same `ftyp` as the init segment; `moov` reuses init boxes with populated
 sample tables and no `mvex`; an outer 64-bit `mdat` envelope carries the
 segment stream verbatim. `co64` offsets point at sample payloads inside that
 envelope. When a track's first `tfdt.base_media_decode_time` is non-zero,
 Flat MP4 emits `edts`/`elst` (empty edit + media) between `tkhd` and `mdia`.
 Segment bytes are never rewritten.
 */
+ (nullable NSData *)flatMP4WithSegments:(NSArray<NSData *> *)segments
                                   error:(NSError **)error;

/**
 Prepends an init segment to unchanged MUXL segments (`[uuid-muxl][moof][mdat]…`).
 */
+ (nullable NSData *)presentationWithInit:(NSData *)initSegment
                                 segments:(NSArray<NSData *> *)segments
                                    error:(NSError **)error;

/**
 Validates a synthesized init: `ftyp` brands, `moov` = `mvhd` + sorted `trak` +
 `mvex`, empty sample tables, no `udta`/`meta`/`iods`/`free`/`skip`.
 */
+ (BOOL)validateInitSegment:(NSData *)initSegment error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
