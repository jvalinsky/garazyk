// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMUXLPlayback.h

 @abstract Playback-sanity checks for MUXL presentation formats.

 @discussion Validates that an fMP4 or Flat MP4 presentation prepends a
 synthesized header onto recoverable canonical MUXL segments, and that every
 fragment inside those segments obeys the MUXL minting rules. Does not decode
 codecs or invoke a media player.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoMUXLPlaybackErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoMUXLPlaybackErrorCode) {
    ATProtoMUXLPlaybackErrorInvalidArgument = 1,
    ATProtoMUXLPlaybackErrorInvalidPresentation = 2,
    ATProtoMUXLPlaybackErrorInvalidSegment = 3,
};

/**
 Playback-oriented structural validation for MUXL presentations.
 */
@interface ATProtoMUXLPlayback : NSObject

/**
 Locates the first `uuid-muxl` box and returns the canonical segment stream
 that follows (including that box). Suitable for stripping either an fMP4
 init header or a Flat MP4 `ftyp`+`moov`(+outer `mdat` header) prefix.
 */
+ (nullable NSData *)canonicalSegmentsFromPresentation:(NSData *)presentation
                                                 error:(NSError **)error;

/**
 Validates an fMP4 presentation: init segment passes
 @c +[ATProtoMUXLFMP4 validateInitSegment:error:], remaining bytes split into
 MUXL segments, each fragment validates via @c ATProtoMUXLFragment.
 */
+ (BOOL)validateFMP4Presentation:(NSData *)presentation error:(NSError **)error;

/**
 Validates a Flat MP4 presentation produced by
 @c +[ATProtoMUXLFMP4 flatMP4WithSegments:error:]: recovers the verbatim
 segment stream from the outer 64-bit @c mdat and validates those segments.
 */
+ (BOOL)validateFlatMP4Presentation:(NSData *)presentation error:(NSError **)error;

/**
 Splits a concatenated MUXL segment stream into individual
 @c [uuid-muxl][moof][mdat]… segments (one catalog box per segment).
 */
+ (nullable NSArray<NSData *> *)splitSegments:(NSData *)segmentStream
                                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
