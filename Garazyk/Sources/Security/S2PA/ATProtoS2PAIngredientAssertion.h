// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoS2PAIngredientAssertion.h

 @abstract Bounded C2PA @c c2pa.ingredient.v3 assertion (WS10 Phase 10).

 @discussion Encodes/decodes ingredient-map-v3 with required @c relationship and
 optional title/format/instanceID/description/digitalSourceType plus optional
 @c activeManifest / @c claimSignature hashed URIs. Does not implement
 @c validationResults, thumbnails, or embedded ingredient manifests.
 @c activeManifest and @c digitalSourceType are mutually exclusive per C2PA.
 */

#import <Foundation/Foundation.h>
#import "Security/S2PA/ATProtoS2PAClaim.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoS2PAIngredientAssertionErrorDomain;
FOUNDATION_EXPORT NSString * const ATProtoS2PAIngredientAssertionLabel; // @"c2pa.ingredient.v3"

FOUNDATION_EXPORT NSString * const ATProtoS2PAIngredientRelationshipParentOf;
FOUNDATION_EXPORT NSString * const ATProtoS2PAIngredientRelationshipComponentOf;
FOUNDATION_EXPORT NSString * const ATProtoS2PAIngredientRelationshipInputTo;

typedef NS_ENUM(NSInteger, ATProtoS2PAIngredientAssertionErrorCode) {
    ATProtoS2PAIngredientAssertionErrorInvalidArgument = 1,
    ATProtoS2PAIngredientAssertionErrorInvalidStructure = 2,
};

@interface ATProtoS2PAIngredientAssertion : NSObject

@property (nonatomic, copy, readonly) NSString *relationship;
@property (nonatomic, copy, readonly, nullable) NSString *title;
@property (nonatomic, copy, readonly, nullable) NSString *format;
@property (nonatomic, copy, readonly, nullable) NSString *instanceID;
@property (nonatomic, copy, readonly, nullable) NSString *descriptionText;
@property (nonatomic, copy, readonly, nullable) NSString *digitalSourceType;
@property (nonatomic, strong, readonly, nullable) ATProtoS2PAHashedURI *activeManifest;
@property (nonatomic, strong, readonly, nullable) ATProtoS2PAHashedURI *claimSignature;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithRelationship:(NSString *)relationship
                               title:(nullable NSString *)title
                              format:(nullable NSString *)format
                          instanceID:(nullable NSString *)instanceID
                     descriptionText:(nullable NSString *)descriptionText
                   digitalSourceType:(nullable NSString *)digitalSourceType
                      activeManifest:(nullable ATProtoS2PAHashedURI *)activeManifest
                      claimSignature:(nullable ATProtoS2PAHashedURI *)claimSignature
    NS_DESIGNATED_INITIALIZER;

/**
 Convenience: @c parentOf ingredient with optional title/format and hashed URI
 references to an ingredient manifest + claim signature.
 */
+ (nullable instancetype)parentOfWithTitle:(nullable NSString *)title
                                    format:(nullable NSString *)format
                                instanceID:(nullable NSString *)instanceID
                            activeManifest:(nullable ATProtoS2PAHashedURI *)activeManifest
                            claimSignature:(nullable ATProtoS2PAHashedURI *)claimSignature
                                     error:(NSError **)error;

/** Convenience: @c inputTo ingredient with @c digitalSourceType (no activeManifest). */
+ (nullable instancetype)inputToWithDigitalSourceType:(NSString *)digitalSourceType
                                                title:(nullable NSString *)title
                                               format:(nullable NSString *)format
                                                error:(NSError **)error;

- (nullable NSData *)encodeCBOR:(NSError **)error;
+ (nullable instancetype)assertionFromCBOR:(NSData *)cbor error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
