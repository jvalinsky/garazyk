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

@end

NS_ASSUME_NONNULL_END
