// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoS2PAClaim.h

 @abstract Bounded C2PA claim-map-v2 + assertion-store helpers (WS10 Phase 10).

 @discussion Builds a labelled assertion store and a @c c2pa.claim.v2 CBOR map
 with @c created_assertions hashed URIs (SHA-256 over each assertion JUMBF
 body). Does not implement ingredient claims, redaction, or gathered
 assertions. Soft-binding / Merkle remain separate.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoS2PAClaimErrorDomain;
FOUNDATION_EXPORT NSString * const ATProtoS2PAClaimLabel; // @"c2pa.claim.v2"
FOUNDATION_EXPORT NSString * const ATProtoS2PAAssertionStoreLabel; // @"c2pa.assertions"
FOUNDATION_EXPORT NSString * const ATProtoS2PAClaimSignatureURI; // @"self#jumbf=c2pa.signature"

typedef NS_ENUM(NSInteger, ATProtoS2PAClaimErrorCode) {
    ATProtoS2PAClaimErrorInvalidArgument = 1,
    ATProtoS2PAClaimErrorInvalidStructure = 2,
    ATProtoS2PAClaimErrorHashMismatch = 3,
};

/** One hashed_uri entry. */
@interface ATProtoS2PAHashedURI : NSObject
@property (nonatomic, copy, readonly) NSString *url;
@property (nonatomic, copy, readonly) NSData *digest;
@property (nonatomic, copy, readonly, nullable) NSString *alg;
+ (instancetype)hashedURIWithURL:(NSString *)url
                          digest:(NSData *)digest
                             alg:(nullable NSString *)alg;
@end

/** One assertion placed in the store: label + CBOR payload. */
@interface ATProtoS2PAStoredAssertion : NSObject
@property (nonatomic, copy, readonly) NSString *label;
@property (nonatomic, copy, readonly) NSData *cbor;
+ (instancetype)assertionWithLabel:(NSString *)label cbor:(NSData *)cbor;
@end

/** claim_generator_info map (name required). */
@interface ATProtoS2PAClaimGeneratorInfo : NSObject
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly, nullable) NSString *version;
@property (nonatomic, copy, readonly, nullable) NSString *specVersion;
+ (instancetype)infoWithName:(NSString *)name
                     version:(nullable NSString *)version
                 specVersion:(nullable NSString *)specVersion;
@end

@interface ATProtoS2PAClaim : NSObject

@property (nonatomic, copy, readonly) NSString *instanceID;
@property (nonatomic, strong, readonly) ATProtoS2PAClaimGeneratorInfo *generatorInfo;
@property (nonatomic, copy, readonly) NSString *signatureURI;
@property (nonatomic, copy, readonly) NSArray<ATProtoS2PAHashedURI *> *createdAssertions;
@property (nonatomic, copy, readonly) NSString *alg; // @"sha256"
@property (nonatomic, copy, readonly, nullable) NSString *title;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithInstanceID:(NSString *)instanceID
                    generatorInfo:(ATProtoS2PAClaimGeneratorInfo *)generatorInfo
                     signatureURI:(NSString *)signatureURI
               createdAssertions:(NSArray<ATProtoS2PAHashedURI *> *)createdAssertions
                             alg:(NSString *)alg
                           title:(nullable NSString *)title
    NS_DESIGNATED_INITIALIZER;

/** Canonical claim-map-v2 CBOR. */
- (nullable NSData *)encodeCBOR:(NSError **)error;

+ (nullable instancetype)claimFromCBOR:(NSData *)cbor error:(NSError **)error;

/**
 Builds hashed URIs and a claim for @c assertions. Hashes each assertion's
 JUMBF body (jumd + content, excluding the outer @c jumb header).
 */
+ (nullable instancetype)claimWithAssertions:(NSArray<ATProtoS2PAStoredAssertion *> *)assertions
                                  instanceID:(NSString *)instanceID
                              generatorInfo:(ATProtoS2PAClaimGeneratorInfo *)generatorInfo
                                      title:(nullable NSString *)title
                                      error:(NSError **)error;

/**
 Builds the @c c2pa.assertions JUMBF superbox containing one CBOR assertion
 box per entry.
 */
+ (nullable NSData *)assertionStoreJUMBFWithAssertions:(NSArray<ATProtoS2PAStoredAssertion *> *)assertions
                                                 error:(NSError **)error;

/** Builds the @c c2pa.claim.v2 JUMBF superbox wrapping claim CBOR. */
+ (nullable NSData *)claimJUMBFWithCBOR:(NSData *)claimCBOR error:(NSError **)error;

/**
 SHA-256 of an assertion JUMBF body's contents (bytes after the 8-byte jumb
 header), matching the hashed_uri construction used by this claim builder.
 */
+ (nullable NSData *)sha256HashForAssertionJUMBF:(NSData *)assertionJUMB
                                          error:(NSError **)error;

/** Looks up an assertion CBOR payload by exact label inside an assertion-store JUMBF. */
+ (nullable NSData *)assertionCBORWithLabel:(NSString *)label
                          inAssertionStore:(NSData *)assertionStoreJUMBF
                                     error:(NSError **)error;

/**
 Verifies each @c created_assertions hashed URI against assertion boxes in
 @c assertionStoreJUMBF.
 */
- (BOOL)verifyHashedURIsAgainstAssertionStore:(NSData *)assertionStoreJUMBF
                                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
