// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoPFP.h

 @abstract Strict DASL perceptual fingerprint identifiers.

 @discussion Implements the identifier grammar from https://dasl.ing/pfp.html.
 Identifier parsing, JSON boundary, and PDQ Hamming-distance comparison are
 included. No perceptual-hash producer or Ozone storage integration is
 invented here. PDQ carries a 32-byte inline hash. TMK+PDQF carries a 36-byte
 strict DASL ATProtoCID that addresses the potentially large fingerprint data.
 */

#import <Foundation/Foundation.h>

@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoPFPErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoPFPErrorCode) {
    ATProtoPFPErrorInvalidType = 1,
    ATProtoPFPErrorInvalidPrefix = 2,
    ATProtoPFPErrorInvalidBase32 = 3,
    ATProtoPFPErrorNonCanonicalVarint = 4,
    ATProtoPFPErrorUnsupportedAlgorithm = 5,
    ATProtoPFPErrorInvalidLength = 6,
    ATProtoPFPErrorTruncatedData = 7,
    ATProtoPFPErrorTrailingData = 8,
    ATProtoPFPErrorInvalidCID = 9,
};

/** Registered DASL PFP algorithm identifiers. */
typedef NS_ENUM(NSUInteger, ATProtoPFPAlgorithm) {
    /** PDQ image perceptual hash, inline 32-byte output. */
    ATProtoPFPAlgorithmPDQ = 0x01,
    /** TMK+PDQF video fingerprint, addressed by a 36-byte ATProtoCID. */
    ATProtoPFPAlgorithmTMKPDQF = 0x02,
};

/**
 An immutable, validated PFP identifier.
 */
@interface ATProtoPFP : NSObject <NSCopying>

/** Registered algorithm identifier. */
@property (nonatomic, assign, readonly) ATProtoPFPAlgorithm algorithm;
/** Raw algorithm data: the PDQ hash or the ATProtoCID bytes for TMK+PDQF. */
@property (nonatomic, copy, readonly) NSData *data;
/** Parsed ATProtoCID for TMK+PDQF; nil for inline PDQ data. */
@property (nonatomic, strong, readonly, nullable) ATProtoCID *dataCID;

/** Parses PFP bytes containing varint algorithm, varint length, and data. */
+ (nullable instancetype)pfpFromBytes:(NSData *)data error:(NSError **)error;

/** Parses a `p`-prefixed lowercase RFC4648 base32 PFP string. */
+ (nullable instancetype)pfpFromString:(NSString *)string error:(NSError **)error;

/** Parses exactly `{"__pfp": "p..."}` at the JSON pseudo-type boundary. */
+ (nullable instancetype)pfpFromJSONObject:(id)object error:(NSError **)error;

/** Canonical PFP bytes. */
- (NSData *)bytes;

/** Canonical `p`-prefixed lowercase RFC4648 base32 string. */
- (NSString *)stringValue;

/** JSON pseudo-type representation: `{"__pfp": "p..."}`. */
- (NSDictionary<NSString *, NSString *> *)JSONObjectRepresentation;

/**
 Hamming distance between two PDQ (32-byte) hashes.

 @discussion Matches the ThreatExchange PDQ metric (recommended match threshold
 ≤ 31). Both identifiers must use `ATProtoPFPAlgorithmPDQ`.
 */
+ (BOOL)hammingDistanceBetweenPDQ:(ATProtoPFP *)left
                            andPDQ:(ATProtoPFP *)right
                          distance:(NSUInteger *)outDistance
                             error:(NSError **)error;

/** ThreatExchange-recommended PDQ match threshold (inclusive). */
+ (NSUInteger)recommendedPDQMatchDistance;

@end

NS_ASSUME_NONNULL_END
