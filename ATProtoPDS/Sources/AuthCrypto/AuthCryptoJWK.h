/*!
 @file AuthCryptoJWK.h

 @abstract JWK (JSON Web Key) utilities for key operations and thumbprints.

 @discussion Provides JWK thumbprint calculation (RFC 7638), public key
 extraction, and key creation from JWK dictionaries.
 Cross-platform: macOS uses Apple Security framework, GNUstep uses OpenSSL.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Auth/PDSKeyProtocol.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class AuthCryptoJWK

 @abstract JWK key operations and RFC 7638 thumbprint calculation.
 */
@interface AuthCryptoJWK : NSObject

#pragma mark - JWK Thumbprint Operations

/*! Computes RFC 7638 JWK thumbprint (SHA-256, base64url). Supports EC and RSA keys. */
+ (nullable NSString *)thumbprint:(NSDictionary *)jwk error:(NSError **)error;

/*! Returns a copy of the JWK with private key material removed. */
+ (NSDictionary *)publicJWKFromJWK:(NSDictionary *)jwk;

#pragma mark - Protocol-based Key Operations (Cross-platform)

/*! Creates a public key from an EC P-256 JWK. */
+ (nullable id<PDSPublicKeyProtocol>)publicKeyFromJWK:(NSDictionary *)jwk
                                                 error:(NSError **)error;

/*! Creates a private key from an EC P-256 JWK. */
+ (nullable id<PDSPrivateKeyProtocol>)privateKeyFromJWK:(NSDictionary *)jwk
                                                   error:(NSError **)error;

/*! Returns a public JWK dictionary representation of a key. */
+ (nullable NSDictionary *)publicJWKFromKey:(id<PDSKeyProtocol>)key
                                      error:(NSError **)error;

/*! Returns a JWK dictionary representation of a key. */
+ (nullable NSDictionary *)jwkFromKey:(id<PDSKeyProtocol>)key
                               error:(NSError **)error;

/*! Computes RFC 7638 thumbprint directly from a key. */
+ (nullable NSString *)thumbprintForKey:(id<PDSKeyProtocol>)key
                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#pragma mark - SecKeyRef Operations (macOS only, deprecated)

#if defined(__APPLE__) && !defined(GNUSTEP)
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

@interface AuthCryptoJWK (Deprecated)

/*! Creates a SecKeyRef public key from an EC P-256 JWK. Caller must CFRelease. */
+ (nullable SecKeyRef)createPublicKeyFromJWK:(NSDictionary *)jwk error:(NSError **)error
    __attribute__((deprecated("Use publicKeyFromJWK:error: instead")));

/*! Creates a SecKeyRef private key from an EC P-256 JWK. Caller must CFRelease. */
+ (nullable SecKeyRef)createPrivateKeyFromJWK:(NSDictionary *)jwk error:(NSError **)error
    __attribute__((deprecated("Use privateKeyFromJWK:error: instead")));

/*! Returns a public JWK dictionary representation of a SecKeyRef. */
+ (nullable NSDictionary *)publicJWKFromSecKey:(SecKeyRef)key error:(NSError **)error
    __attribute__((deprecated("Use publicJWKFromKey:error: instead")));

/*! Returns a JWK dictionary representation of a SecKeyRef. */
+ (nullable NSDictionary *)jwkFromSecKey:(SecKeyRef)key error:(NSError **)error
    __attribute__((deprecated("Use jwkFromKey:error: instead")));

/*! Computes RFC 7638 thumbprint directly from a SecKeyRef. */
+ (nullable NSString *)thumbprintForSecKey:(SecKeyRef)key error:(NSError **)error
    __attribute__((deprecated("Use thumbprintForKey:error: instead")));

@end

NS_ASSUME_NONNULL_END

#endif
