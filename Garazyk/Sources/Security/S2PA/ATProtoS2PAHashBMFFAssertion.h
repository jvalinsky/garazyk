// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoS2PAHashBMFFAssertion.h

 @abstract Bounded C2PA @c c2pa.hash.bmff.v3 hard-binding assertion (WS10 Phase 10 / phase 32).

 @discussion Encodes/decodes the BMFF hash assertion used for ISO BMFF assets
 (MP4/fMP4). Root-box v3 hashing uses @c offset_be64 || box_bytes (minus subset
 exclusions). When @c merkle is present with @c hash, mdat payload is covered by
 a C2PA Merkle tree (leaf digests over payload blocks; no per-leaf file offset)
 and the mandatory @c /mdat subset exclusion (offset 16, length 0) applies.
 Nested xpath beyond a single root 4cc is out of profile — use root paths +
 @c subset. Does not implement fragmented initHash / aux merkle boxes.
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
 Bounded @c merkle-map. This profile stores the leaf row in @c hashes
 (@c hashes.count == @c count). @c initHash is accepted on decode but unused
 (fragmented fMP4 is out of scope for this slice).
 */
@interface ATProtoS2PAMerkleMap : NSObject
@property (nonatomic, assign, readonly) NSInteger uniqueId;
@property (nonatomic, assign, readonly) NSInteger localId;
@property (nonatomic, assign, readonly) NSUInteger count;
@property (nonatomic, copy, readonly) NSArray<NSData *> *hashes;
@property (nonatomic, copy, readonly, nullable) NSString *alg;
@property (nonatomic, strong, readonly, nullable) NSNumber *fixedBlockSize;
@property (nonatomic, copy, readonly, nullable) NSArray<NSNumber *> *variableBlockSizes;
/** CBOR key @c initHash (fragmented fMP4); unused by this non-fragmented profile. */
@property (nonatomic, copy, readonly, nullable) NSData *initializationHash;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithUniqueId:(NSInteger)uniqueId
                         localId:(NSInteger)localId
                           count:(NSUInteger)count
                          hashes:(NSArray<NSData *> *)hashes
                             alg:(nullable NSString *)alg
                  fixedBlockSize:(nullable NSNumber *)fixedBlockSize
             variableBlockSizes:(nullable NSArray<NSNumber *> *)variableBlockSizes
            initializationHash:(nullable NSData *)initializationHash
    NS_DESIGNATED_INITIALIZER;

- (nullable NSData *)encodeCBORMap:(NSError **)error;
+ (nullable instancetype)merkleMapFromCBORMap:(id)cborMap error:(NSError **)error;
@end

/**
 C2PA BMFF hash assertion: required @c exclusions; @c alg/@c hash/@c merkle/@c name
 optional per CDDL (this implementation always sets alg=sha256 when hashing).
 */
@interface ATProtoS2PAHashBMFFAssertion : NSObject

@property (nonatomic, copy, readonly) NSString *alg; // @"sha256"
@property (nonatomic, copy, readonly, nullable) NSData *digest;
@property (nonatomic, copy, readonly) NSArray<ATProtoS2PAHashBMFFExclusion *> *exclusions;
@property (nonatomic, copy, readonly, nullable) NSArray<ATProtoS2PAMerkleMap *> *merkle;
@property (nonatomic, copy, readonly, nullable) NSString *name;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithDigest:(nullable NSData *)digest
                    exclusions:(NSArray<ATProtoS2PAHashBMFFExclusion *> *)exclusions
                        merkle:(nullable NSArray<ATProtoS2PAMerkleMap *> *)merkle
                          name:(nullable NSString *)name
    NS_DESIGNATED_INITIALIZER;

/** Convenience without merkle. */
- (instancetype)initWithDigest:(NSData *)digest
                    exclusions:(NSArray<ATProtoS2PAHashBMFFExclusion *> *)exclusions
                          name:(nullable NSString *)name;

/**
 Default exclusion for an embedded C2PA Manifest Store uuid box: xpath @c /uuid
 with data match of the C2PA BMFF user-type UUID at relative offset 8.
 */
+ (ATProtoS2PAHashBMFFExclusion *)c2paUUIDBoxExclusion;

/**
 Mandatory exclusion when both @c hash and @c merkle are present: xpath @c /mdat
 with subset @c {offset=16, length=0} (hash header; exclude payload).
 */
+ (ATProtoS2PAHashBMFFExclusion *)mdatMerklePayloadExclusion;

/**
 SHA-256 over BMFF @c data using v3 root-box @c offset||bytes hashing with
 @c exclusions applied.
 */
+ (nullable NSData *)sha256DigestForBMFFData:(NSData *)data
                                  exclusions:(NSArray<ATProtoS2PAHashBMFFExclusion *> *)exclusions
                                       error:(NSError **)error;

/**
 Leaf digests (SHA-256 of each payload block) for an @c mdat payload.
 Pass neither block-size mode for a single leaf over the whole payload;
 @c fixedBlockSize alone for fixed chunks; @c variableBlockSizes alone for
 variable chunks (@c count must match array length and sum must equal payload).
 */
+ (nullable NSArray<NSData *> *)leafDigestsForMDATPayload:(NSData *)payload
                                           fixedBlockSize:(nullable NSNumber *)fixedBlockSize
                                      variableBlockSizes:(nullable NSArray<NSNumber *> *)variableBlockSizes
                                                    error:(NSError **)error;

/**
 Builds parent layers from already-hashed leaves (C2PA unbalanced promote:
 odd last node copies up; pairs are SHA-256(left||right)). Index 0 is the leaf
 row.
 */
+ (NSArray<NSArray<NSData *> *> *)merkleLayersFromLeafHashes:(NSArray<NSData *> *)leafHashes;

/**
 Builds an assertion that excludes the C2PA uuid box and hashes the rest of the
 BMFF file (typical post-embed verify path).
 */
+ (nullable instancetype)assertionExcludingC2PAUUIDForBMFFData:(NSData *)bmffData
                                                          name:(nullable NSString *)name
                                                         error:(NSError **)error;

/**
 Non-fragmented Merkle profile: uuid exclusion + mandatory mdat subset exclusion,
 top-level @c hash over the file, and one @c merkle-map storing the leaf row for
 the @c localId-th @c mdat (0-based).
 */
+ (nullable instancetype)assertionExcludingC2PAUUIDWithMerkleForBMFFData:(NSData *)bmffData
                                                                uniqueId:(NSInteger)uniqueId
                                                                 localId:(NSInteger)localId
                                                          fixedBlockSize:(nullable NSNumber *)fixedBlockSize
                                                     variableBlockSizes:(nullable NSArray<NSNumber *> *)variableBlockSizes
                                                                    name:(nullable NSString *)name
                                                                   error:(NSError **)error;

/** Canonical CBOR map encoding of this assertion. */
- (nullable NSData *)encodeCBOR:(NSError **)error;

/** Parse a canonical CBOR assertion map. */
+ (nullable instancetype)assertionFromCBOR:(NSData *)cbor error:(NSError **)error;

/**
 Recomputes the top-level digest (when present) and verifies each merkle leaf
 row against the corresponding @c mdat payload.
 */
- (BOOL)verifyAgainstBMFFData:(NSData *)bmffData error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
