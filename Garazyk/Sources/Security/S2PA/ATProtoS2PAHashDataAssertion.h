// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoS2PAHashDataAssertion.h

 @abstract Bounded C2PA @c c2pa.hash.data hard-binding assertion (WS10 Phase 10).

 @discussion Encodes/decodes the data-hash assertion used to bind a manifest to
 asset bytes: SHA-256 digest plus optional exclusion ranges (byte offsets
 skipped while hashing). For MUXL-style prepend, either hash the media alone
 (empty exclusions) or hash the full presentation while excluding the leading
 C2PA uuid box. Does not implement soft bindings, bmffHash, or the full claim
 generator / assertion store graph.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoS2PAHashDataAssertionErrorDomain;
FOUNDATION_EXPORT NSString * const ATProtoS2PAHashDataAssertionLabel;

typedef NS_ENUM(NSInteger, ATProtoS2PAHashDataAssertionErrorCode) {
    ATProtoS2PAHashDataAssertionErrorInvalidArgument = 1,
    ATProtoS2PAHashDataAssertionErrorInvalidStructure = 2,
    ATProtoS2PAHashDataAssertionErrorHashMismatch = 3,
};

/** One exclusion range: [start, start+length). */
@interface ATProtoS2PAHashDataExclusion : NSObject
@property (nonatomic, assign) NSUInteger start;
@property (nonatomic, assign) NSUInteger length;
+ (instancetype)exclusionWithStart:(NSUInteger)start length:(NSUInteger)length;
@end

/**
 C2PA data-hash assertion: @c alg, @c hash, optional @c exclusions / @c name.
 */
@interface ATProtoS2PAHashDataAssertion : NSObject

@property (nonatomic, copy, readonly) NSString *alg; // @"sha256"
/** SHA-256 digest bytes (CBOR map key @c hash). */
@property (nonatomic, copy, readonly) NSData *digest;
@property (nonatomic, copy, readonly) NSArray<ATProtoS2PAHashDataExclusion *> *exclusions;
@property (nonatomic, copy, readonly, nullable) NSString *name;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithDigest:(NSData *)digest
                    exclusions:(nullable NSArray<ATProtoS2PAHashDataExclusion *> *)exclusions
                          name:(nullable NSString *)name
    NS_DESIGNATED_INITIALIZER;

/** SHA-256 over @c data with exclusion ranges zeroed out of the digest input. */
+ (nullable NSData *)sha256DigestForData:(NSData *)data
                              exclusions:(nullable NSArray<ATProtoS2PAHashDataExclusion *> *)exclusions
                                   error:(NSError **)error;

/**
 Builds an assertion whose hash is SHA-256(media) with empty exclusions
 (MUXL “hash then prepend” model).
 */
+ (nullable instancetype)assertionHardBindingMediaData:(NSData *)mediaData
                                                  name:(nullable NSString *)name
                                                 error:(NSError **)error;

/**
 Builds an assertion for a full presentation that excludes a leading uuid box
 of @c excludedPrefixLength bytes (start=0).
 */
+ (nullable instancetype)assertionForPresentation:(NSData *)presentation
                            excludedPrefixLength:(NSUInteger)excludedPrefixLength
                                            name:(nullable NSString *)name
                                           error:(NSError **)error;

/** Canonical CBOR map encoding of this assertion. */
- (nullable NSData *)encodeCBOR:(NSError **)error;

/** Parse a canonical CBOR assertion map. */
+ (nullable instancetype)assertionFromCBOR:(NSData *)cbor error:(NSError **)error;

/**
 Recomputes the digest for @c data with this assertion's exclusions and
 compares to @c digest.
 */
- (BOOL)verifyAgainstData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
