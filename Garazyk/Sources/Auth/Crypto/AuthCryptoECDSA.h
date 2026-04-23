/*!
 @file AuthCryptoECDSA.h

 @abstract ECDSA signature format conversion utilities.

 @discussion Converts between ASN.1 DER and raw (r||s) ECDSA signature formats.
 DER is used by Security framework, raw is used in JWS/JWT (RFC 7515 §A.3).
 Extracted from duplicated implementations in OAuth2DPoPProof and DPoPUtil.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class AuthCryptoECDSA

 @abstract ECDSA DER ↔ raw signature conversion.
 */
@interface AuthCryptoECDSA : NSObject

/*! Converts DER-encoded ECDSA signature to raw (r||s) format.
    @param der DER-encoded signature from Security framework.
    @param expectedSize Component size in bytes (32 for P-256, 48 for P-384).
    @param error Set on parse failure.
    @return Raw signature of length expectedSize*2, or nil on error. */
+ (nullable NSData *)rawSignatureFromDER:(NSData *)der expectedSize:(size_t)expectedSize error:(NSError **)error;

/*! Converts raw (r||s) ECDSA signature to DER format.
    @param raw Raw signature with r and s concatenated.
    @param error Set on invalid input.
    @return DER-encoded signature for Security framework, or nil on error. */
+ (nullable NSData *)derSignatureFromRaw:(NSData *)raw error:(NSError **)error;

/*! Checks if a raw P-256 signature is in low-S form.
    @param rawSignature Raw 64-byte signature.
    @param error Set on failure.
    @return YES if low-S, NO otherwise. */
+ (BOOL)isLowS:(NSData *)rawSignature error:(NSError **)error;

/*! Normalizes a raw P-256 signature to low-S form.
    @discussion If s > N/2, replaces s with N - s (per PLC spec low-S canonicalization).
    https://web.plc.directory/spec/v0.1/did-plc
    @param rawSignature Raw 64-byte signature.
    @param error Set on failure.
    @return Normalized 64-byte signature (may be same object if already low-S). */
+ (nullable NSData *)normalizeLowS:(NSData *)rawSignature error:(NSError **)error;

/*! Converts a low-S P-256 signature back to high-S form.
    @discussion Inverse of normalizeLowS: — replaces s with N - s.
    Used during verification because Apple's SecKeyVerifySignature may only
    accept the original (high-S) form produced by SecKeyCreateSignature.
    @param rawSignature Raw 64-byte low-S signature.
    @param error Set on failure.
    @return High-S 64-byte signature, or nil on error. */
+ (nullable NSData *)denormalizeLowS:(NSData *)rawSignature error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
