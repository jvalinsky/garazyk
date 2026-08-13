// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoS2PASoftBindingAssertion.h

 @abstract Bounded C2PA @c c2pa.soft-binding assertion (WS10 Phase 10 / phase 33).

 @discussion Encodes/decodes the soft-binding assertion map and computes /
 verifies the Soft Binding Algorithm List entry @c com.joinmonolith.sha256
 (exact SHA-256 fingerprint over supplied media bytes). Soft bindings must not
 replace hard bindings. Region-of-interest @c scope.region and watermark
 embedding are out of scope; optional @c timespan selects which block to match
 against (caller supplies the scoped bytes).
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoS2PASoftBindingAssertionErrorDomain;
FOUNDATION_EXPORT NSString * const ATProtoS2PASoftBindingAssertionLabel;

/** Soft Binding Algorithm List identifier for SHA-256 content fingerprints. */
FOUNDATION_EXPORT NSString * const ATProtoS2PASoftBindingAlgorithmMonolithSHA256;

typedef NS_ENUM(NSInteger, ATProtoS2PASoftBindingAssertionErrorCode) {
    ATProtoS2PASoftBindingAssertionErrorInvalidArgument = 1,
    ATProtoS2PASoftBindingAssertionErrorInvalidStructure = 2,
    ATProtoS2PASoftBindingAssertionErrorUnsupportedAlgorithm = 3,
    ATProtoS2PASoftBindingAssertionErrorMismatch = 4,
};

/** Optional millisecond timespan scope for one soft-binding block. */
@interface ATProtoS2PASoftBindingTimespan : NSObject
@property (nonatomic, assign) NSUInteger start;
@property (nonatomic, assign) NSUInteger end;
+ (instancetype)timespanWithStart:(NSUInteger)start end:(NSUInteger)end;
/** Equal start/end (used when matching scoped blocks). */
- (BOOL)isEqualToTimespan:(nullable ATProtoS2PASoftBindingTimespan *)other;
@end

/** One soft-binding block: algorithm-specific @c value plus optional timespan. */
@interface ATProtoS2PASoftBindingBlock : NSObject
@property (nonatomic, copy) NSData *value;
@property (nonatomic, strong, nullable) ATProtoS2PASoftBindingTimespan *timespan;
+ (instancetype)blockWithValue:(NSData *)value
                      timespan:(nullable ATProtoS2PASoftBindingTimespan *)timespan;
@end

@interface ATProtoS2PASoftBindingAssertion : NSObject

@property (nonatomic, copy, readonly) NSString *alg;
@property (nonatomic, copy, readonly) NSArray<ATProtoS2PASoftBindingBlock *> *blocks;
@property (nonatomic, copy, readonly, nullable) NSString *name;
@property (nonatomic, copy, readonly, nullable) NSData *algParams;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithAlg:(NSString *)alg
                     blocks:(NSArray<ATProtoS2PASoftBindingBlock *> *)blocks
                       name:(nullable NSString *)name
                  algParams:(nullable NSData *)algParams
    NS_DESIGNATED_INITIALIZER;

/**
 SHA-256 digest of @c data as a soft-binding block value.
 Only @c ATProtoS2PASoftBindingAlgorithmMonolithSHA256 is supported; @c algParams
 is ignored (none required).
 */
+ (nullable NSData *)computeValueForData:(NSData *)data
                                     alg:(NSString *)alg
                               algParams:(nullable NSData *)algParams
                                   error:(NSError **)error;

/**
 Builds an assertion whose single block is the SHA-256 fingerprint of @c data
 (optional timespan metadata only).
 */
+ (nullable instancetype)assertionMonolithSHA256ForData:(NSData *)data
                                               timespan:(nullable ATProtoS2PASoftBindingTimespan *)timespan
                                                   name:(nullable NSString *)name
                                                  error:(NSError **)error;

/**
 Exact-match verify: recomputes the fingerprint over @c data and compares to
 the first block whose timespan equals @c timespan (both nil = whole-asset block).
 */
- (BOOL)verifyAgainstData:(NSData *)data
                 timespan:(nullable ATProtoS2PASoftBindingTimespan *)timespan
                    error:(NSError **)error;

/** Canonical CBOR map encoding. */
- (nullable NSData *)encodeCBOR:(NSError **)error;

/** Parse a canonical CBOR soft-binding map. */
+ (nullable instancetype)assertionFromCBOR:(NSData *)cbor error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
