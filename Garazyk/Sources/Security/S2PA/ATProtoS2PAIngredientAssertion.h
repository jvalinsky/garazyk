// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoS2PAIngredientAssertion.h

 @abstract Bounded C2PA @c c2pa.ingredient.v3 assertion (WS10 Phase 10 / phase 31).

 @discussion Encodes/decodes ingredient-map-v3 with required @c relationship,
 optional metadata, @c activeManifest / @c claimSignature hashed URIs, and
 bounded @c validationResults. When @c activeManifest is present,
 @c validationResults is required. Embed/verify helpers hash nested manifest
 boxes under @c self#jumbf=/c2pa/<instanceID>. Does not implement ingredient
 deltas, thumbnails, or gathered/redacted assertions.
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
    ATProtoS2PAIngredientAssertionErrorHashMismatch = 3,
    ATProtoS2PAIngredientAssertionErrorMissingTarget = 4,
};

/** One validation status entry: @c code plus optional @c url. */
@interface ATProtoS2PAIngredientValidationStatus : NSObject
@property (nonatomic, copy, readonly) NSString *code;
@property (nonatomic, copy, readonly, nullable) NSString *url;
+ (instancetype)statusWithCode:(NSString *)code url:(nullable NSString *)url;
@end

/**
 Bounded @c validationResults.activeManifest lists (success / informational /
 failure).
 */
@interface ATProtoS2PAIngredientValidationResults : NSObject
@property (nonatomic, copy, readonly) NSArray<ATProtoS2PAIngredientValidationStatus *> *success;
@property (nonatomic, copy, readonly) NSArray<ATProtoS2PAIngredientValidationStatus *> *informational;
@property (nonatomic, copy, readonly) NSArray<ATProtoS2PAIngredientValidationStatus *> *failure;
+ (instancetype)resultsWithSuccess:(nullable NSArray<ATProtoS2PAIngredientValidationStatus *> *)success
                    informational:(nullable NSArray<ATProtoS2PAIngredientValidationStatus *> *)informational
                          failure:(nullable NSArray<ATProtoS2PAIngredientValidationStatus *> *)failure;
/** Convenience: one success code (optionally with url). */
+ (instancetype)resultsWithSingleSuccessCode:(NSString *)code url:(nullable NSString *)url;
@end

@interface ATProtoS2PAIngredientAssertion : NSObject

@property (nonatomic, copy, readonly) NSString *relationship;
@property (nonatomic, copy, readonly, nullable) NSString *title;
@property (nonatomic, copy, readonly, nullable) NSString *format;
@property (nonatomic, copy, readonly, nullable) NSString *instanceID;
@property (nonatomic, copy, readonly, nullable) NSString *descriptionText;
@property (nonatomic, copy, readonly, nullable) NSString *digitalSourceType;
@property (nonatomic, strong, readonly, nullable) ATProtoS2PAHashedURI *activeManifest;
@property (nonatomic, strong, readonly, nullable) ATProtoS2PAHashedURI *claimSignature;
@property (nonatomic, strong, readonly, nullable) ATProtoS2PAIngredientValidationResults *validationResults;

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
                  validationResults:(nullable ATProtoS2PAIngredientValidationResults *)validationResults
    NS_DESIGNATED_INITIALIZER;

/**
 @c parentOf ingredient. When @c activeManifest is non-nil, @c validationResults
 is required.
 */
+ (nullable instancetype)parentOfWithTitle:(nullable NSString *)title
                                    format:(nullable NSString *)format
                                instanceID:(nullable NSString *)instanceID
                            activeManifest:(nullable ATProtoS2PAHashedURI *)activeManifest
                            claimSignature:(nullable ATProtoS2PAHashedURI *)claimSignature
                        validationResults:(nullable ATProtoS2PAIngredientValidationResults *)validationResults
                                     error:(NSError **)error;

/** Convenience: @c inputTo ingredient with @c digitalSourceType (no activeManifest). */
+ (nullable instancetype)inputToWithDigitalSourceType:(NSString *)digitalSourceType
                                                title:(nullable NSString *)title
                                               format:(nullable NSString *)format
                                                error:(NSError **)error;

/**
 Builds a @c parentOf ingredient whose hashed URIs point at an embedded child
 claim-bound store labeled @c instanceID (@c self#jumbf=/c2pa/<instanceID> and
 @c …/c2pa.signature). @c childStore must be a Manifest Store from
 @c ATProtoS2PAJUMBF (outer @c c2pa wrap). Also returns the relabeled child
 active-manifest JUMBF via @c outEmbeddedManifestJUMBF for parent-store assembly.
 */
+ (nullable instancetype)parentOfEmbeddingChildStore:(NSData *)childStore
                                          instanceID:(NSString *)instanceID
                                               title:(nullable NSString *)title
                                              format:(nullable NSString *)format
                               outEmbeddedManifestJUMBF:(NSData * _Nullable * _Nullable)outEmbeddedManifestJUMBF
                                               error:(NSError **)error;

/**
 Verifies @c activeManifest / @c claimSignature digests against boxes inside
 @c manifestStore (a claim-bound Manifest Store that embeds the child).
 */
- (BOOL)verifyEmbeddedManifestsInStore:(NSData *)manifestStore error:(NSError **)error;

- (nullable NSData *)encodeCBOR:(NSError **)error;
+ (nullable instancetype)assertionFromCBOR:(NSData *)cbor error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
