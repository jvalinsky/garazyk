// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMUXLFragment.h

 @abstract Deterministic MUXL one-sample fragment minting.

 @discussion Mints exactly `[moof][mdat]` per https://dasl.ing/muxl.html:
 one `mfhd` + one `traf` (`tfhd`/`tfdt`/`trun`) carrying a single sample, then
 one `mdat` with that sample's bytes. Sequence numbers are 1-based. Sync samples
 use sample_flags `0x02000000`; non-sync use `0x01010000`. Composition-time
 offsets are omitted from `trun` when zero.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoMUXLFragmentErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoMUXLFragmentErrorCode) {
    ATProtoMUXLFragmentErrorInvalidArgument = 1,
    ATProtoMUXLFragmentErrorInvalidStructure = 2,
};

/**
 Parameters for minting one MUXL fragment.
 */
@interface ATProtoMUXLFragmentSample : NSObject

@property (nonatomic, assign) uint32_t trackID;
/** Per-track, 1-based sequence number. */
@property (nonatomic, assign) uint32_t sequenceNumber;
/** Absolute decode time in the track media timescale. */
@property (nonatomic, assign) uint64_t baseMediaDecodeTime;
@property (nonatomic, assign) uint32_t sampleDuration;
@property (nonatomic, copy) NSData *sampleBytes;
@property (nonatomic, assign) BOOL syncSample;
/** Omitted from `trun` when zero. */
@property (nonatomic, assign) int32_t compositionTimeOffset;

@end

/**
 Mints and validates MUXL CMAF fragments.
 */
@interface ATProtoMUXLFragment : NSObject

/** Mints `[moof][mdat]` for one sample. */
+ (nullable NSData *)fragmentWithSample:(ATProtoMUXLFragmentSample *)sample
                                  error:(NSError **)error;

/**
 Validates a minted fragment's nested `mfhd`/`traf`/`tfhd`/`tfdt`/`trun`/`mdat`
 shape against the MUXL rules (not the opaque envelope check in ATProtoMUXLBox).
 */
+ (BOOL)validateFragment:(NSData *)fragment error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
