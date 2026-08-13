// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoS2PAHashBMFFAssertion.h

 @abstract Bounded C2PA @c c2pa.hash.bmff.v3 hard-binding assertion (WS10 Phase 10).

 @discussion Encodes/decodes the BMFF hash assertion used for ISO BMFF assets
 (MP4/fMP4). Computes SHA-256 over root boxes as @c offset_be64 || box_bytes
 (minus subset exclusions), skipping boxes that match exclusion xpath / data
 filters. Does not implement Merkle trees, soft bindings, or the full claim
 graph. Nested xpath is limited to simple container walks (child boxes only).
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoS2PAHashBMFFAssertionErrorDomain;
FOUNDATION_EXPORT NSString * const ATProtoS2PAHashBMFFAssertionLabel;

typedef NS_ENUM(NSInteger, ATProtoS2PAHashBMFFAssertionErrorCode) {
    ATProtoS2PAHashBMFFAssertionErrorInvalidArgument = 1,
    ATProtoS2PAHashBMFFAssertionErrorInvalidStructure = 2,
    ATProtoS2PAHashBMFFAssertionErrorHashMismatch = 3,
};

/** Optional byte match at a relative offset within a candidate box. */
@interface ATProtoS2PAHashBMFFDataMatch : NSObject
@property (nonatomic, assign) NSUInteger offset;
@property (nonatomic, copy) NSData *value;
+ (instancetype)matchWithOffset:(NSUInteger)offset value:(NSData *)value;
@end

/** Relative subset of a box to exclude (offsets from box start including header). */
@interface ATProtoS2PAHashBMFFSubset : NSObject
@property (nonatomic, assign) NSUInteger offset;
@property (nonatomic, assign) NSUInteger length; // 0 = remainder of box
+ (instancetype)subsetWithOffset:(NSUInteger)offset length:(NSUInteger)length;
@end

/** One exclusions-map entry (xpath + optional filters / subsets). */
@interface ATProtoS2PAHashBMFFExclusion : NSObject
@property (nonatomic, copy) NSString *xpath;
@property (nonatomic, copy, nullable) NSArray<ATProtoS2PAHashBMFFDataMatch *> *dataMatches;
@property (nonatomic, copy, nullable) NSArray<ATProtoS2PAHashBMFFSubset *> *subsets;
+ (instancetype)exclusionWithXPath:(NSString *)xpath
                       dataMatches:(nullable NSArray<ATProtoS2PAHashBMFFDataMatch *> *)dataMatches
                           subsets:(nullable NSArray<ATProtoS2PAHashBMFFSubset *> *)subsets;
@end

/**
 C2PA BMFF hash assertion: required @c exclusions, @c alg/@c hash/@c name optional
 per CDDL (this implementation always sets alg=sha256 and hash).
 */
@interface ATProtoS2PAHashBMFFAssertion : NSObject

@property (nonatomic, copy, readonly) NSString *alg; // @"sha256"
@property (nonatomic, copy, readonly) NSData *digest;
@property (nonatomic, copy, readonly) NSArray<ATProtoS2PAHashBMFFExclusion *> *exclusions;
@property (nonatomic, copy, readonly, nullable) NSString *name;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithDigest:(NSData *)digest
                    exclusions:(NSArray<ATProtoS2PAHashBMFFExclusion *> *)exclusions
                          name:(nullable NSString *)name
    NS_DESIGNATED_INITIALIZER;

/**
 Default exclusion for an embedded C2PA Manifest Store uuid box: xpath @c /uuid
 with data match of the C2PA BMFF user-type UUID at relative offset 8.
 */
+ (ATProtoS2PAHashBMFFExclusion *)c2paUUIDBoxExclusion;

/**
 SHA-256 over BMFF @c data using v3 root-box @c offset||bytes hashing with
 @c exclusions applied.
 */
+ (nullable NSData *)sha256DigestForBMFFData:(NSData *)data
                                  exclusions:(NSArray<ATProtoS2PAHashBMFFExclusion *> *)exclusions
                                       error:(NSError **)error;

/**
 Builds an assertion that excludes the C2PA uuid box and hashes the rest of the
 BMFF file (typical post-embed verify path).
 */
+ (nullable instancetype)assertionExcludingC2PAUUIDForBMFFData:(NSData *)bmffData
                                                          name:(nullable NSString *)name
                                                         error:(NSError **)error;

/** Canonical CBOR map encoding of this assertion. */
- (nullable NSData *)encodeCBOR:(NSError **)error;

/** Parse a canonical CBOR assertion map. */
+ (nullable instancetype)assertionFromCBOR:(NSData *)cbor error:(NSError **)error;

/** Recomputes the digest for @c bmffData and compares to @c digest. */
- (BOOL)verifyAgainstBMFFData:(NSData *)bmffData error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
