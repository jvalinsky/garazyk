// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMUXLBox.h

 @abstract Deterministic MUXL catalog atom primitives.

 @discussion Implements the canonical MUXL segment prefix from
 https://dasl.ing/muxl.html: a `uuid` BMFF box with the fixed MUXL UUID and a
 DRISL catalog body, followed by unchanged one-sample `moof`+`mdat` fragments.
 This bounded slice does not synthesize MP4 presentation headers.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoMUXLErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoMUXLErrorCode) {
    ATProtoMUXLErrorInvalidCatalog = 1,
    ATProtoMUXLErrorInvalidTrack = 2,
    ATProtoMUXLErrorInvalidContainer = 3,
    ATProtoMUXLErrorInvalidBox = 4,
    ATProtoMUXLErrorOversizedBox = 5,
    ATProtoMUXLErrorTrailingData = 6,
};

/**
 Deterministic MUXL catalog and segment helpers.
 */
@interface ATProtoMUXLBox : NSObject

/** The 16-byte UUID identifying the MUXL catalog box. */
+ (NSData *)muxlUUID;

/** Encodes and validates the required shape of a single-track catalog in a `uuid-muxl` box. Optional catalog fields are preserved but not semantically interpreted. */
+ (nullable NSData *)uuidMuxlBoxWithCatalog:(NSDictionary *)catalog
                                      error:(NSError **)error;

/** Decodes and validates exactly one `uuid-muxl` box. */
+ (nullable NSDictionary *)catalogFromUUIDMuxlBox:(NSData *)boxData
                                            error:(NSError **)error;

/**
 Builds `[uuid-muxl][moof][mdat]...` while preserving every fragment byte.

 Each fragment must contain exactly one standard-size `moof` box followed by
 one standard-size `mdat` box. The nested `mfhd`/`traf`/`trun` sample structure
 remains opaque to this bounded primitive and is not claimed to be validated.
 */
+ (nullable NSData *)segmentWithCatalog:(NSDictionary *)catalog
                              fragments:(NSArray<NSData *> *)fragments
                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
