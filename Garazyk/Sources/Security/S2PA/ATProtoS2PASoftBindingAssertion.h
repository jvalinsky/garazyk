// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoS2PASoftBindingAssertion.h

 @abstract Bounded C2PA @c c2pa.soft-binding assertion (WS10 Phase 10).

 @discussion Encodes/decodes the soft-binding assertion map (algorithm id +
 one or more value blocks with optional timespan scope). Does not compute or
 verify perceptual hashes / watermarks — callers supply @c value bytes from an
 external soft-binding algorithm. Region-of-interest scope, pad fields, and
 bindingMetadata are out of scope for this slice.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoS2PASoftBindingAssertionErrorDomain;
FOUNDATION_EXPORT NSString * const ATProtoS2PASoftBindingAssertionLabel;

typedef NS_ENUM(NSInteger, ATProtoS2PASoftBindingAssertionErrorCode) {
    ATProtoS2PASoftBindingAssertionErrorInvalidArgument = 1,
    ATProtoS2PASoftBindingAssertionErrorInvalidStructure = 2,
};

/** Optional millisecond timespan scope for one soft-binding block. */
@interface ATProtoS2PASoftBindingTimespan : NSObject
@property (nonatomic, assign) NSUInteger start;
@property (nonatomic, assign) NSUInteger end;
+ (instancetype)timespanWithStart:(NSUInteger)start end:(NSUInteger)end;
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

/** Canonical CBOR map encoding. */
- (nullable NSData *)encodeCBOR:(NSError **)error;

/** Parse a canonical CBOR soft-binding map. */
+ (nullable instancetype)assertionFromCBOR:(NSData *)cbor error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
