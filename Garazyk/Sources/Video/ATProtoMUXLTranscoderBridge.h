// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMUXLTranscoderBridge.h

 @abstract Bridge ffmpeg CMAF / HLS fMP4 output into MUXL segments.

 @discussion Parses a CMAF init segment (`ftyp`+`moov`) for catalog fields,
 wraps each `[moof][mdat]` media segment with a canonical `uuid-muxl` catalog,
 and optionally synthesizes MUXL fMP4 / Flat MP4 presentations. Default HLS
 transcoder output is unchanged unless a caller opts in.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoMUXLTranscoderBridgeErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoMUXLTranscoderBridgeErrorCode) {
    ATProtoMUXLTranscoderBridgeErrorInvalidArgument = 1,
    ATProtoMUXLTranscoderBridgeErrorUnsupportedInit = 2,
    ATProtoMUXLTranscoderBridgeErrorInvalidFragment = 3,
};

/**
 Converts CMAF init + media segments into MUXL packaging.
 */
@interface ATProtoMUXLTranscoderBridge : NSObject

/**
 Builds a single-track MUXL catalog from a CMAF init segment (`init.mp4`).

 Supports `avc1` (with `avcC`), `av01` (with `av1C`), and `mp4a` (with `esds`).
 */
+ (nullable NSDictionary *)catalogFromCMAFInit:(NSData *)initSegment
                                         error:(NSError **)error;

/**
 Wraps each CMAF `[moof][mdat]` fragment with @c catalog into a MUXL segment.
 */
+ (nullable NSArray<NSData *> *)muxlSegmentsWithCatalog:(NSDictionary *)catalog
                                          cmafFragments:(NSArray<NSData *> *)fragments
                                                  error:(NSError **)error;

/**
 Packages one HLS variant directory that contains `init.mp4` and
 `segment_*.m4s` files into MUXL segments plus an fMP4 presentation.

 Keys: @c catalog, @c segments, @c init, @c presentation. @c flat is included
 only when every wrapped fragment satisfies MUXL minting rules (ffmpeg CMAF
 often omits it).
 */
+ (nullable NSDictionary<NSString *, id> *)packageHLSVariantDirectory:(NSString *)directory
                                                                error:(NSError **)error;

/**
 Writes a packaged result under @c directory/muxl/: @c init.mp4,
 @c presentation.mp4, optional @c flat.mp4, and @c segment_NNNNN.m4s files.

 Returns path metadata (@c directory, @c init, @c presentation, optional
 @c flat, and @c segments as an array of absolute paths), or nil on I/O failure.
 */
+ (nullable NSDictionary<NSString *, id> *)writePackage:(NSDictionary<NSString *, id> *)package
                                            toDirectory:(NSString *)directory
                                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
