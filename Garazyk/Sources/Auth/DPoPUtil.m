// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  DPoPUtil.m
//  ATProtoPDS
//
//  DPoP utility wrapper. This file uses SecKeyRef which is only available on macOS.
//  For cross-platform DPoP support, use AuthCryptoDPoP directly with protocol-based keys.
//
//  Copyright (c) 2025-2026 Jack Valinsky. All rights reserved.
//

#if defined(__APPLE__) && !defined(GNUSTEP)

#import "Auth/DPoPUtil.h"
#import "Auth/Crypto/AuthCryptoDPoP.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"
#import "Auth/Crypto/AuthCryptoJWK.h"
#import "Auth/Crypto/AuthCryptoECDSA.h"
#import "Auth/PDSReplayCache.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

NSString * const DPoPErrorDomain = @"com.atproto.pds.dpop";


@implementation DPoPToken

+ (nullable instancetype)createWithMethod:(NSString *)htm
                                      uri:(NSString *)htu
                                    nonce:(nullable NSString *)nonce
                                    error:(NSError **)error {
    NSString *canonicalHTU = [AuthCryptoDPoP canonicalHTUFromString:htu];
    if (canonicalHTU.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.dpop"
                                         code:-17
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP URI"}];
        }
        return nil;
    }
    DPoPToken *token = [[DPoPToken alloc] init];
    token.htm = htm;
    token.htu = canonicalHTU;
    token.iat = [NSDate date];
    token.exp = [NSDate dateWithTimeIntervalSinceNow:300];
    token.jti = [[NSUUID UUID] UUIDString];
    token.nonce = nonce;
    return token;
}

- (NSDictionary *)header {
    // Note: This returns a dummy JWK as coordinates are normally added during signing.
    // DPoPUtil clients expect this structure.
    return @{
        @"typ": @"dpop+jwt",
        @"alg": @"ES256",
        @"jwk": @{
            @"kty": @"EC",
            @"crv": @"P-256",
            @"x": @"",
            @"y": @""
        }
    };
}

- (NSDictionary *)payload {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"htm"] = self.htm;
    payload[@"htu"] = self.htu;
    payload[@"iat"] = @([self.iat timeIntervalSince1970]);
    payload[@"jti"] = self.jti;

    if (self.exp) {
        payload[@"exp"] = @([self.exp timeIntervalSince1970]);
    }

    if (self.ath) {
        payload[@"ath"] = self.ath;
    }

    if (self.nonce) {
        payload[@"nonce"] = self.nonce;
    }

    return payload;
}

@end

@implementation DPoPUtil

+ (nullable DPoPToken *)createDPoPForMethod:(NSString *)htm
                                         uri:(NSString *)htu
                                       nonce:(nullable NSString *)nonce
                                         key:(SecKeyRef)privateKey
                                       error:(NSError **)error {
    NSURL *url = [NSURL URLWithString:htu];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.dpop"
                                         code:-17
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP URI"}];
        }
        return nil;
    }

    // Use AuthCryptoJWK to get the JWK representation from SecKeyRef
    NSDictionary *jwk = [AuthCryptoJWK publicJWKFromSecKey:privateKey error:error];
    if (!jwk) return nil;

    // AuthCryptoDPoP expects the full JWK including private material if it's going to sign
    // but it can also take a jwk dictionary and we can inject the private key if needed.
    // However, AuthCryptoDPoP's createProofForURL currently expects a jwk dictionary
    // and handles SecKey creation internally from it.

    // To maintain DPoPUtil's API (which takes SecKeyRef), we'll do a slightly different path
    // or update AuthCryptoDPoP to be more flexible.
    // For now, let's use the underlying components.

    NSString *canonicalHTU = [AuthCryptoDPoP canonicalHTUFromURL:url];
    DPoPToken *token = [[DPoPToken alloc] init];
    token.htm = htm;
    token.htu = canonicalHTU;
    token.iat = [NSDate date];
    token.jti = [[NSUUID UUID] UUIDString];
    token.nonce = nonce;
    token.exp = [NSDate dateWithTimeIntervalSinceNow:300];

    // Build JWT
    NSDictionary *header = @{
        @"typ": @"dpop+jwt",
        @"alg": @"ES256",
        @"jwk": jwk
    };

    NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:error];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:[token payload] options:0 error:error];
    if (!headerData || !payloadData) return nil;

    NSString *headerB64 = [AuthCryptoBase64URL encode:headerData];
    NSString *payloadB64 = [AuthCryptoBase64URL encode:payloadData];
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerB64, payloadB64];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

    CFErrorRef signError = NULL;
    NSData *derSignature = CFBridgingRelease(SecKeyCreateSignature(privateKey,
                                                                 kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                                 (__bridge CFDataRef)signingData,
                                                                 &signError));
    if (!derSignature) {
        if (error) *error = CFBridgingRelease(signError);
        return nil;
    }

    NSData *rawSignature = [AuthCryptoECDSA rawSignatureFromDER:derSignature expectedSize:32 error:error];
    if (!rawSignature) return nil;

    // Normalize to low-S form per PLC spec (AT Protocol requires low-S canonicalization)
    rawSignature = [AuthCryptoECDSA normalizeLowS:rawSignature error:error];
    if (!rawSignature) return nil;

    token.jwt = [NSString stringWithFormat:@"%@.%@.%@", headerB64, payloadB64, [AuthCryptoBase64URL encode:rawSignature]];
    return token;
}

+ (BOOL)verifyDPoP:(NSString *)dpopJwt
     withPublicKey:(nullable SecKeyRef)publicKey
              method:(NSString *)htm
                 uri:(NSString *)htu
               nonce:(nullable NSString *)nonce
                error:(NSError **)error {
    NSURL *url = [NSURL URLWithString:htu];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.dpop"
                                         code:-17
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DPoP URI"}];
        }
        return NO;
    }

    // AuthCryptoDPoP handles verification. If publicKey is nil, it can still verify structure
    // if we pass a dummy/extracted key, but AuthCryptoDPoP's verifyProof currently extracts
    // the key from the JWK in the header.

    // If a publicKey is PROVIDED to verifyDPoP, we should ensure it MATCHES the one in the proof.

    NSString *thumbprint = nil;
    BOOL valid = [AuthCryptoDPoP verifyProof:dpopJwt
                                      method:htm
                                         url:url
                                       nonce:nonce
                                requireNonce:NO
                              nonceValidator:nil
                               replayChecker:(id<AuthCryptoDPoPReplayChecker>)[PDSReplayCache sharedCache]
                               outThumbprint:&thumbprint
                                       error:error];
    if (!valid) return NO;

    if (publicKey) {
        // Extra check: ensure provided publicKey matches the one in the DPoP header
        NSString *expectedThumbprint = [AuthCryptoJWK thumbprintForSecKey:publicKey error:error];
        if (!expectedThumbprint || ![thumbprint isEqualToString:expectedThumbprint]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.pds.dpop"
                                             code:-14
                                         userInfo:@{NSLocalizedDescriptionKey: @"Public key mismatch"}];
            }
            return NO;
        }
    }

    return YES;
}

@end

#else // GNUstep

// Stub implementations for GNUstep
// DPoPUtil uses SecKeyRef from compat headers on GNUstep.
// Use AuthCryptoDPoP directly with the protocol-based key interfaces.

#import "Auth/DPoPUtil.h"
#import "Security/SecKey.h"  // Compat SecKeyRef definition

NSString * const DPoPErrorDomain = @"com.atproto.pds.dpop";

@implementation DPoPToken

+ (nullable instancetype)createWithMethod:(NSString *)htm uri:(NSString *)htu nonce:(nullable NSString *)nonce error:(NSError **)error {
    return nil; // Not available on GNUstep
}

- (NSDictionary *)header { return @{}; }
- (NSDictionary *)payload { return @{}; }

@end

@implementation DPoPUtil

+ (nullable DPoPToken *)createDPoPForMethod:(NSString *)htm uri:(NSString *)htu nonce:(nullable NSString *)nonce key:(SecKeyRef)privateKey error:(NSError **)error {
    if (error) {
        *error = [NSError errorWithDomain:DPoPErrorDomain
                                     code:-99
                                 userInfo:@{NSLocalizedDescriptionKey: @"DPoPUtil not available on this platform. Use AuthCryptoDPoP instead."}];
    }
    return nil;
}

+ (BOOL)verifyDPoP:(NSString *)dpopJwt withPublicKey:(nullable SecKeyRef)publicKey method:(NSString *)htm uri:(NSString *)htu nonce:(nullable NSString *)nonce error:(NSError **)error {
    if (error) {
        *error = [NSError errorWithDomain:DPoPErrorDomain
                                     code:-99
                                 userInfo:@{NSLocalizedDescriptionKey: @"DPoPUtil not available on this platform. Use AuthCryptoDPoP instead."}];
    }
    return NO;
}

@end

#endif // __APPLE__ && !GNUSTEP
