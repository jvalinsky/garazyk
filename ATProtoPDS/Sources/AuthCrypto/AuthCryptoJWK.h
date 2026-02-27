/*!
 @file AuthCryptoJWK.h

 @abstract JWK (JSON Web Key) utilities for key operations and thumbprints.

 @discussion Provides JWK thumbprint calculation (RFC 7638), public key
 extraction, and Security framework key creation from JWK dictionaries.
 Extracted from duplicated implementations in OAuth2DPoPProof and DPoPUtil.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class AuthCryptoJWK

 @abstract JWK key operations and RFC 7638 thumbprint calculation.
 */
@interface AuthCryptoJWK : NSObject

/*! Computes RFC 7638 JWK thumbprint (SHA-256, base64url). Supports EC and RSA keys. */
+ (nullable NSString *)thumbprint:(NSDictionary *)jwk error:(NSError **)error;

/*! Returns a copy of the JWK with private key material removed. */
+ (NSDictionary *)publicJWKFromJWK:(NSDictionary *)jwk;

/*! Creates a SecKeyRef public key from an EC P-256 JWK. Caller must CFRelease. */
+ (nullable SecKeyRef)createPublicKeyFromJWK:(NSDictionary *)jwk error:(NSError **)error;

/*! Creates a SecKeyRef private key from an EC P-256 JWK. Caller must CFRelease. */
+ (nullable SecKeyRef)createPrivateKeyFromJWK:(NSDictionary *)jwk error:(NSError **)error;

/*! Returns a public JWK dictionary representation of a SecKeyRef. */
+ (nullable NSDictionary *)publicJWKFromKey:(SecKeyRef)key error:(NSError **)error;

/*! Returns a JWK dictionary representation of a SecKeyRef. Currently supports EC P-256. */
+ (nullable NSDictionary *)jwkFromKey:(SecKeyRef)key error:(NSError **)error;

/*! Computes RFC 7638 thumbprint directly from a SecKeyRef. */
+ (nullable NSString *)thumbprintForKey:(SecKeyRef)key error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
