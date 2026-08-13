// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoS2PAJUMBF.h

 @abstract Minimal C2PA/S2PA JUMBF manifest-store primitives.

 @discussion Builds and parses a bounded JUMBF Manifest Store that carries an
 attached ES256K COSE_Sign1 envelope and the S2PA leaf certificate. The store
 is suitable as the payload of a BMFF `uuid` box using the C2PA user-type UUID
 (`d8fec3d6-1b0e-483c-9297-5828877ec481`), matching MUXL's `[uuid-c2pa]…`
 prepend pattern. Hard-binding helpers hash canonical media bytes (SHA-256)
 and use that digest as the COSE payload so the uuid carrier can be prepended
 without invalidating the binding. Full C2PA claim/assertion schema remains
 out of scope.
 */

#import <Foundation/Foundation.h>
#import "Auth/Crypto/Secp256k1.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoS2PAJUMBFErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoS2PAJUMBFErrorCode) {
    ATProtoS2PAJUMBFErrorInvalidArgument = 1,
    ATProtoS2PAJUMBFErrorInvalidStructure = 2,
    ATProtoS2PAJUMBFErrorVerificationFailed = 3,
};

/**
 Bounded S2PA JUMBF store + BMFF uuid carrier.
 */
@interface ATProtoS2PAJUMBF : NSObject

/** C2PA BMFF user-type UUID (16 bytes). */
+ (NSData *)c2paBMFFUUID;

/**
 Builds a JUMBF Manifest Store containing `signature` (COSE_Sign1) and
 `certificate` (DER leaf) as nested content boxes.
 */
+ (nullable NSData *)manifestStoreWithSignature:(NSData *)signature
                                   certificate:(NSData *)certificate
                                         error:(NSError **)error;

/**
 Wraps a JUMBF store in a standard-size BMFF `uuid` box with the C2PA UUID.
 */
+ (nullable NSData *)bmffUUIDBoxWithManifestStore:(NSData *)store
                                            error:(NSError **)error;

/** Extracts the JUMBF store body from a C2PA BMFF `uuid` box. */
+ (nullable NSData *)manifestStoreFromBMFFUUIDBox:(NSData *)box
                                            error:(NSError **)error;

/**
 Parses signature and leaf certificate bytes from a JUMBF store produced by
 `manifestStoreWithSignature:certificate:error:`.
 */
+ (BOOL)extractSignature:(NSData * _Nullable * _Nonnull)outSignature
            certificate:(NSData * _Nullable * _Nonnull)outCertificate
      fromManifestStore:(NSData *)store
                  error:(NSError **)error;

/**
 Signs `payload` with ES256K, mints an S2PA leaf, builds the JUMBF store, and
 returns the BMFF `uuid` box.
 */
+ (nullable NSData *)uuidBoxSigningPayload:(NSData *)payload
                              withKeyPair:(ATProtoSecp256k1KeyPair *)keyPair
                                      did:(nullable NSString *)did
                                notBefore:(NSDate *)notBefore
                                 notAfter:(NSDate *)notAfter
                                    error:(NSError **)error;

/**
 Verifies a BMFF uuid box: extracts COSE + leaf, verifies the leaf, and
 verifies the COSE envelope against the leaf public key / supplied key.
 */
+ (BOOL)verifyUUIDBox:(NSData *)box
       expectedPayload:(NSData *)payload
           expectedDID:(nullable NSString *)expectedDID
                 error:(NSError **)error;

/**
 Prepends a C2PA uuid box to unchanged media bytes (e.g. a MUXL segment).
 */
+ (nullable NSData *)presentationWithUUIDBox:(NSData *)uuidBox
                                   mediaData:(NSData *)mediaData
                                       error:(NSError **)error;

/**
 SHA-256 hard-binding digest over canonical media bytes (MUXL segment body).
 The uuid/JUMBF carrier is excluded by hashing media alone before prepend.
 */
+ (nullable NSData *)hardBindingSHA256ForMediaData:(NSData *)mediaData
                                            error:(NSError **)error;

/**
 Signs the SHA-256 hard-binding digest of @c mediaData as the COSE payload and
 returns the BMFF uuid box (does not prepend).
 */
+ (nullable NSData *)uuidBoxHardBindingMediaData:(NSData *)mediaData
                                    withKeyPair:(ATProtoSecp256k1KeyPair *)keyPair
                                            did:(nullable NSString *)did
                                      notBefore:(NSDate *)notBefore
                                       notAfter:(NSDate *)notAfter
                                          error:(NSError **)error;

/**
 Verifies a uuid box whose COSE payload is either a raw SHA-256 digest or a
 @c c2pa.hash.data assertion CBOR map hard-bound to @c mediaData.
 */
+ (BOOL)verifyUUIDBox:(NSData *)box
 hardBoundToMediaData:(NSData *)mediaData
          expectedDID:(nullable NSString *)expectedDID
                error:(NSError **)error;

/**
 Signs a @c c2pa.hash.data assertion (empty exclusions over @c mediaData) and
 returns the BMFF uuid box.
 */
+ (nullable NSData *)uuidBoxSigningHashDataAssertionForMediaData:(NSData *)mediaData
                                                     withKeyPair:(ATProtoSecp256k1KeyPair *)keyPair
                                                             did:(nullable NSString *)did
                                                       notBefore:(NSDate *)notBefore
                                                        notAfter:(NSDate *)notAfter
                                                           error:(NSError **)error;

/**
 Hard-binds + prepends: uuid box over SHA-256(media) then media bytes.
 */
+ (nullable NSData *)presentationHardBindingMediaData:(NSData *)mediaData
                                          withKeyPair:(ATProtoSecp256k1KeyPair *)keyPair
                                                  did:(nullable NSString *)did
                                            notBefore:(NSDate *)notBefore
                                             notAfter:(NSDate *)notAfter
                                                error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
