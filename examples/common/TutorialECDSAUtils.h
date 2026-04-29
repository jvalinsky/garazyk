/*!
 @file TutorialECDSAUtils.h

 @abstract Cross-platform ECDSA P-256 key generation, signing, and verification.

 @discussion Provides real ES256 (ECDSA P-256 with SHA-256) operations for
 tutorial examples. Uses Apple Security framework on macOS and OpenSSL on
 GNUstep/Linux.

 This is a simplified, educational version of the production code in
 Garazyk/Sources/Auth/Crypto/AuthCryptoECDSA.h and AuthCryptoJWK.h.

 Key concepts:
 - EC P-256 key pair generation
 - ES256 signing (DER → raw r||s conversion for JWT)
 - ES256 verification (raw r||s → DER conversion for Security/OpenSSL)
 - JWK (JSON Web Key) import/export
 - JWK thumbprint (RFC 7638)

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const TutorialECDSAErrorDomain;

typedef NS_ENUM(NSInteger, TutorialECDSAError) {
    TutorialECDSAErrorKeyGenerationFailed = 1,
    TutorialECDSAErrorSigningFailed = 2,
    TutorialECDSAErrorVerificationFailed = 3,
    TutorialECDSAErrorInvalidKeyData = 4,
    TutorialECDSAErrorInvalidSignature = 5,
    TutorialECDSAErrorInvalidJWK = 6,
};

/*!
 @class TutorialECDSAKeyPair

 @abstract Holds a generated EC P-256 key pair with JWK export.
 */
@interface TutorialECDSAKeyPair : NSObject

/*! The key identifier (UUID). */
@property (nonatomic, copy, readonly) NSString *keyID;

/*! Public key as uncompressed point (0x04 || x || y), 65 bytes. */
@property (nonatomic, strong, readonly) NSData *publicKeyData;

/*! Public JWK (kty, crv, x, y — no private key material). */
@property (nonatomic, copy, readonly) NSDictionary *publicJWK;

/*! Private JWK (kty, crv, x, y, d — includes private key material). */
@property (nonatomic, copy, readonly) NSDictionary *privateJWK;

/*! RFC 7638 JWK thumbprint (SHA-256 of canonical JWK, base64url). */
@property (nonatomic, copy, readonly) NSString *thumbprint;

@end

/*!
 @class TutorialECDSAUtils

 @abstract Cross-platform ECDSA P-256 operations for tutorials.
 */
@interface TutorialECDSAUtils : NSObject

/*!
 @method generateKeyPairWithError:

 @abstract Generates a new EC P-256 key pair.

 @param error On failure, contains error details.
 @return A new key pair, or nil on failure.
 */
+ (nullable TutorialECDSAKeyPair *)generateKeyPairWithError:(NSError **)error;

/*!
 @method signData:withPrivateKey:error:

 @abstract Signs data using ES256 (ECDSA P-256 with SHA-256).

 @param data The data to sign (will be hashed internally with SHA-256).
 @param privateKeyJWK The private JWK dictionary (must contain kty, crv, x, y, d).
 @param error On failure, contains error details.
 @return The raw signature in r||s format (64 bytes), or nil on failure.
 */
+ (nullable NSData *)signData:(NSData *)data
                withPrivateKey:(NSDictionary *)privateKeyJWK
                         error:(NSError **)error;

/*!
 @method verifySignature:forData:withPublicKey:error:

 @abstract Verifies an ES256 signature.

 @param signature The raw signature in r||s format (64 bytes).
 @param data The original data that was signed.
 @param publicKeyJWK The public JWK dictionary (must contain kty, crv, x, y).
 @param error On failure, contains error details.
 @return YES if the signature is valid, NO otherwise.
 */
+ (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
          withPublicKey:(NSDictionary *)publicKeyJWK
                  error:(NSError **)error;

/*!
 @method rawSignatureFromDER:expectedSize:error:

 @abstract Converts DER-encoded ECDSA signature to raw (r||s) format.

 @discussion DER is used by Security framework and OpenSSL. Raw format is
 used in JWT/JWS (RFC 7515 §A.3).

 @param der DER-encoded signature from Security framework.
 @param expectedSize Component size in bytes (32 for P-256).
 @param error On parse failure.
 @return Raw signature of length expectedSize*2, or nil on error.
 */
+ (nullable NSData *)rawSignatureFromDER:(NSData *)der
                            expectedSize:(size_t)expectedSize
                                   error:(NSError **)error;

/*!
 @method derSignatureFromRaw:error:

 @abstract Converts raw (r||s) ECDSA signature to DER format.

 @param raw Raw signature with r and s concatenated (64 bytes for P-256).
 @param error On invalid input.
 @return DER-encoded signature for Security framework, or nil on error.
 */
+ (nullable NSData *)derSignatureFromRaw:(NSData *)raw
                                    error:(NSError **)error;

/*!
 @method thumbprintForJWK:error:

 @abstract Computes RFC 7638 JWK thumbprint.

 @discussion The thumbprint is the base64url-encoded SHA-256 hash of the
 canonical JWK JSON (keys sorted lexicographically, no whitespace).

 @param jwk The public JWK dictionary.
 @param error On failure.
 @return The thumbprint string, or nil on error.
 */
+ (nullable NSString *)thumbprintForJWK:(NSDictionary *)jwk
                                   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
