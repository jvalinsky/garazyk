// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoAuthCryptoBase64URL.h

 @abstract Base64URL encoding and decoding utilities.

 @discussion Provides RFC 4648 §5 base64url encoding without padding, shared
 between OAuth Provider and Auth Verifier components. Extracted from duplicated
 implementations in ATProtoDPoPUtil and ATProtoOAuth2DPoPProof.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for AuthCrypto operations. */
extern NSString * const AuthCryptoErrorDomain;

/*!
 @class ATProtoAuthCryptoBase64URL

 @abstract Base64URL encode/decode without padding.
 */
@interface ATProtoAuthCryptoBase64URL : NSObject

/*! Encodes data to base64url string (no padding). */
+ (NSString *)encode:(NSData *)data;

/*! Decodes base64url string to data. Returns nil on invalid input. */
+ (nullable NSData *)decode:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
