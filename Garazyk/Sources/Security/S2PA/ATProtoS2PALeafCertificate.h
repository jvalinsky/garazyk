// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoS2PALeafCertificate.h

 @abstract Deterministic S2PA self-signed X.509 leaf certificates.

 @discussion Mints and verifies the S2PA leaf described by
 https://dasl.ing/s2pa.html: a self-issued X.509 v3 certificate whose
 `commonName` carries a DID, whose `subjectPublicKeyInfo` is secp256k1, and
 whose extensions are the normative basicConstraints / keyUsage /
 extendedKeyUsage / subjectKeyIdentifier / authorityKeyIdentifier set. Verifiers
 must not chain this certificate to any trust anchor.
 */

#import <Foundation/Foundation.h>
#import "Auth/Crypto/Secp256k1.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoS2PALeafErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoS2PALeafErrorCode) {
    ATProtoS2PALeafErrorInvalidArgument = 1,
    ATProtoS2PALeafErrorEncodingFailed = 2,
    ATProtoS2PALeafErrorInvalidCertificate = 3,
    ATProtoS2PALeafErrorVerificationFailed = 4,
};

/**
 S2PA leaf certificate minting and self-signature verification.
 */
@interface ATProtoS2PALeafCertificate : NSObject

/**
 Mints a DER-encoded S2PA leaf certificate.

 If `did` is nil or empty, the certificate binds `keyPair.didKeyString`.
 `notBefore` / `notAfter` are encoded per RFC 5280 (UTCTime through 2049,
 GeneralizedTime thereafter). The serial number is a stable positive integer
 derived from the subject key identifier.
 */
+ (nullable NSData *)certificateWithKeyPair:(ATProtoSecp256k1KeyPair *)keyPair
                                        did:(nullable NSString *)did
                                  notBefore:(NSDate *)notBefore
                                   notAfter:(NSDate *)notAfter
                                      error:(NSError **)error;

/**
 Verifies a DER S2PA leaf: self-signature, secp256k1 SPKI, DID `commonName`,
 and matching subject/authority key identifiers. No trust-anchor chain is
 consulted. When `expectedDID` is non-nil it must equal the certificate CN.
 */
+ (BOOL)verifyCertificate:(NSData *)derCertificate
              expectedDID:(nullable NSString *)expectedDID
                    error:(NSError **)error;

/** SHA-1 of the 65-byte uncompressed SEC1 public key (RFC 5280 method 1). */
+ (NSData *)subjectKeyIdentifierForPublicKey:(NSData *)uncompressedPublicKey;

@end

NS_ASSUME_NONNULL_END
