/*!
 @file TutorialDPoPHandler.h

 @abstract DPoP (Demonstration of Proof-of-Possession) handler for tutorials.

 @discussion Implements RFC 9449 DPoP proof generation and verification using
 real ES256 (ECDSA P-256 with SHA-256) signatures.

 This is the educational version of the production AuthCryptoDPoP in
 Garazyk/Sources/Auth/Crypto/AuthCryptoDPoP.h.

 Key concepts:
 - DPoP proof JWT structure (typ: dpop+jwt)
 - JWK header with public key
 - htm (HTTP method), htu (HTTP URI), iat (issued at), jti (JWT ID)
 - Replay protection via nonce
 - JWK thumbprint for key binding

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class TutorialECDSAKeyPair;

NS_ASSUME_NONNULL_BEGIN

@interface TutorialDPoPHandler : NSObject

/*!
 @method generateDPoPProof:uri:nonce:keyPair:error:

 @abstract Generates a DPoP proof JWT signed with ES256.

 @param method The HTTP method (e.g., "POST").
 @param uri The HTTP URI (e.g., "https://pds.example.com/xrpc/...").
 @param nonce Optional server-provided nonce for replay protection.
 @param keyPair The ECDSA key pair to sign with.
 @param error On failure, contains error details.
 @return The signed DPoP proof JWT string, or nil on failure.
 */
+ (nullable NSString *)generateDPoPProof:(NSString *)method
                                      uri:(NSString *)uri
                                    nonce:(nullable NSString *)nonce
                                  keyPair:(TutorialECDSAKeyPair *)keyPair
                                    error:(NSError **)error;

/*!
 @method verifyDPoPProof:method:uri:publicJWK:nonce:allowedClockSkew:error:

 @abstract Verifies a DPoP proof JWT.

 @param proof The DPoP proof JWT string.
 @param method The expected HTTP method.
 @param uri The expected HTTP URI.
 @param publicJWK The public JWK to verify the signature.
 @param nonce Optional expected nonce.
 @param allowedClockSkew Maximum allowed clock skew in seconds.
 @param error On failure, contains error details.
 @return YES if the proof is valid, NO otherwise.
 */
+ (BOOL)verifyDPoPProof:(NSString *)proof
                  method:(NSString *)method
                     uri:(NSString *)uri
              publicJWK:(NSDictionary *)publicJWK
                   nonce:(nullable NSString *)nonce
       allowedClockSkew:(NSTimeInterval)allowedClockSkew
                   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
