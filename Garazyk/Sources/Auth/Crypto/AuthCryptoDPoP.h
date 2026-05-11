// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AuthCryptoDPoP.h

 @abstract Canonical DPoP proof verification and creation (RFC 9449).

 @discussion Unified DPoP implementation shared between OAuth Provider
 (authorization server) and Auth Verifier (resource server). Nonce management
 and replay detection are injected via protocols to avoid coupling to
 specific storage implementations.

 Cross-platform: Works on both macOS and GNUstep.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for DPoP-specific failures. */
extern NSString * const AuthCryptoDPoPErrorDomain;

/*!
 @protocol AuthCryptoDPoPNonceValidator

 @abstract Validates DPoP nonces against server-issued values.
 */
@protocol AuthCryptoDPoPNonceValidator <NSObject>

/*! Returns YES if the nonce is currently valid. */
- (BOOL)validateNonce:(NSString *)nonce;

@end

/*!
 @protocol AuthCryptoDPoPReplayChecker

 @abstract Detects DPoP proof replay by tracking JTI values.
 */
@protocol AuthCryptoDPoPReplayChecker <NSObject>

/*! Returns YES if the JTI has not been seen before (and records it). */
- (BOOL)checkAndAddJTI:(NSString *)jti expiration:(NSDate *)expiration;

@end

/*!
 @class AuthCryptoDPoPResult

 @abstract Parsed DPoP proof contents after successful verification.
 */
@interface AuthCryptoDPoPResult : NSObject

/*! JWK thumbprint of the proof key. */
@property (nonatomic, copy) NSString *jkt;

/*! Unique proof identifier. */
@property (nonatomic, copy) NSString *jti;

/*! HTTP method the proof binds to. */
@property (nonatomic, copy) NSString *htm;

/*! HTTP target URI the proof binds to. */
@property (nonatomic, copy) NSString *htu;

/*! The JWK from the proof header. */
@property (nonatomic, strong) NSDictionary *jwk;

@end

/*!
 @class AuthCryptoDPoP

 @abstract DPoP proof verification and creation.
 */
@interface AuthCryptoDPoP : NSObject

/*! Returns the canonical HTTP target URI (scheme + authority + path, no query/fragment). */
+ (NSString *)canonicalHTUFromURL:(NSURL *)url;

/*! Parses a URL string and returns its canonical HTU form. */
+ (nullable NSString *)canonicalHTUFromString:(NSString *)urlString;

/*! Verifies a DPoP proof JWT against request parameters.
    @param dpopJwt The DPoP proof JWT string.
    @param method HTTP method (GET, POST, etc.).
    @param url Request URL to verify against.
    @param nonce Expected nonce value (may be nil if not required).
    @param requireNonce If YES, proof must contain a nonce.
    @param nonceValidator Optional validator for nonce freshness.
    @param replayChecker Optional replay detection.
    @param thumbprint On success, receives the JWK thumbprint.
    @param error Set on verification failure.
    @return YES if the proof is valid. */
+ (BOOL)verifyProof:(NSString *)dpopJwt
              method:(NSString *)method
                 url:(NSURL *)url
               nonce:(nullable NSString *)nonce
        requireNonce:(BOOL)requireNonce
      nonceValidator:(nullable id<AuthCryptoDPoPNonceValidator>)nonceValidator
       replayChecker:(nullable id<AuthCryptoDPoPReplayChecker>)replayChecker
       outThumbprint:(NSString * _Nullable * _Nullable)thumbprint
               error:(NSError **)error;

/*! Creates a signed DPoP proof JWT.
    @param url Target URL for the proof.
    @param method HTTP method.
    @param jwk EC P-256 JWK with private key material.
    @param error Set on failure.
    @return Signed DPoP JWT string, or nil on error. */
+ (nullable NSString *)createProofForURL:(NSURL *)url
                                  method:(NSString *)method
                                     key:(NSDictionary *)jwk
                                   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
