// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoPFPProducer.h

 @abstract PDQ perceptual-hash producer for DASL PFP identifiers.

 @discussion Selected producer contract for workstream 10 Phase 8:
 - Algorithm: Meta PDQ (registry 0x01) over float luma in row-major order.
 - Decode / colorspace / resize of compressed images is caller-owned.
 - Output is a DASL PFP (`ATProtoPFP`) plus a 0–100 quality score.
 - TMK+PDQF video fingerprints are out of scope for this producer.
 */

#import <Foundation/Foundation.h>

@class ATProtoPFP;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoPFPProducerErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoPFPProducerErrorCode) {
    ATProtoPFPProducerErrorInvalidArgument = 1,
    ATProtoPFPProducerErrorHashFailed = 2,
};

/** Result of a PDQ hash: DASL PFP + quality metric. */
@interface ATProtoPFPHashResult : NSObject
@property (nonatomic, strong, readonly) ATProtoPFP *pfp;
/** Heuristic 0–100 quality from image-domain gradients (Meta PDQ). */
@property (nonatomic, assign, readonly) NSInteger quality;
@end

/**
 Produces DASL PDQ PFPs from luma or packed RGB8 buffers.

 Follows Meta ThreatExchange PDQ float-luma hashing (Jarosz downsample →
 64×64 → 16×16 DCT → median bit packing). Byte packing of the 256-bit digest
 is little-endian uint16 words in Hash256 slot order (w[0]…w[15]).
 */
@interface ATProtoPFPProducer : NSObject

/**
 Hashes a float luma buffer (`samples[row * width + col]`, typically 0–255).
 */
+ (nullable ATProtoPFPHashResult *)hashFloatLumaWidth:(NSUInteger)width
                                               height:(NSUInteger)height
                                              samples:(const float *)samples
                                                error:(NSError **)error;

/**
 Hashes packed 8-bit RGB (`R,G,B` triples) using standard luma coefficients.
 @param bytesPerRow Row stride in bytes; must be ≥ width * 3.
 */
+ (nullable ATProtoPFPHashResult *)hashRGB8Width:(NSUInteger)width
                                          height:(NSUInteger)height
                                     bytesPerRow:(NSUInteger)bytesPerRow
                                          pixels:(const uint8_t *)pixels
                                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
