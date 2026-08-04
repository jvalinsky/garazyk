// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoS2PACOSE.h

 @abstract Strict COSE_Sign1 ES256K primitives for S2PA.

 @discussion Implements the cryptographic core of S2PA's COSE binding: an
 attached COSE_Sign1 message using ES256K (COSE algorithm -47), the canonical
 Sig_structure, and 64-byte low-S secp256k1 signatures. This bounded primitive
 deliberately does not claim to implement the C2PA manifest store, JUMBF
 embedding, or S2PA's self-signed X.509 leaf certificate.

 @see https://dasl.ing/s2pa.html
 @see https://www.rfc-editor.org/rfc/rfc9052
 */

#import <Foundation/Foundation.h>
#import "Auth/Crypto/Secp256k1.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoS2PAErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoS2PAErrorCode) {
    ATProtoS2PAErrorInvalidInput = 1,
    ATProtoS2PAErrorInvalidEnvelope = 2,
    ATProtoS2PAErrorUnsupportedAlgorithm = 3,
    ATProtoS2PAErrorNonCanonicalEncoding = 4,
    ATProtoS2PAErrorInvalidSignature = 5,
    ATProtoS2PAErrorVerificationFailed = 6,
};

/**
 Strict attached COSE_Sign1 operations for S2PA's ES256K signature core.

 The protected header is exactly `{1: -47}` (the COSE `alg` parameter set to
 ES256K), the unprotected header is empty, and the payload is attached. The
 certificate and identity layers remain outside this bounded type.
 */
@interface ATProtoS2PACOSE : NSObject

/**
 Returns the canonical protected-header bytes for `{1: -47}`.
 */
+ (NSData *)canonicalProtectedHeaders;

/**
 Constructs the canonical COSE `Sig_structure` for an attached payload.

 The returned bytes are the message whose SHA-256 digest is signed by
 `signPayload:withKeyPair:error:`.
 */
+ (nullable NSData *)sigStructureForPayload:(NSData *)payload
                                      error:(NSError **)error;

/**
 Signs a payload as an attached ES256K COSE_Sign1 message.
 */
+ (nullable NSData *)signPayload:(NSData *)payload
                    withKeyPair:(Secp256k1KeyPair *)keyPair
                           error:(NSError **)error;

/**
 Extracts the attached payload after strict structural and canonical checks.

 This method does not verify the signature; use `verifyEnvelope:withPublicKey:error:`
 when authenticity is required.
 */
+ (nullable NSData *)payloadFromEnvelope:(NSData *)envelope
                                   error:(NSError **)error;

/**
 Verifies an attached ES256K COSE_Sign1 message against a secp256k1 public key.

 No X.509 chain or trust anchor is consulted. Identity binding is an explicit
 responsibility of the caller until the S2PA certificate slice is added.
 */
+ (BOOL)verifyEnvelope:(NSData *)envelope
         withPublicKey:(NSData *)publicKey
                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
