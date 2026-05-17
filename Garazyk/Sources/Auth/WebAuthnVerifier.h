// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file WebAuthnVerifier.h

 @abstract WebAuthn credential verification.

 @discussion Verifies WebAuthn registration and authentication responses
 per W3C WebAuthn specification. Validates attestations, signatures, and
 authenticator data.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class WebAuthnVerifier

 @abstract WebAuthn response verification utilities.

 @discussion Provides cryptographic verification of WebAuthn registration
 (attestation) and authentication (assertion) responses. Validates challenge,
 origin, signature, and sign count.
 */
@interface WebAuthnVerifier : NSObject

/*!
 @method verifyRegistrationResponse:challenge:origin:error:

 @abstract Verify WebAuthn registration response (attestation).

 @discussion Validates registration response from navigator.credentials.create().
 Checks challenge, origin, and attestation statement. Returns credential info
 including public key and credential ID.

 @param response Registration response from client.
 @param expectedChallenge Challenge sent to client.
 @param expectedOrigin Expected origin (e.g., "https://example.com").
 @param error Error pointer for validation failures.
 @return Dictionary with credentialId, publicKey, signCount, or nil on failure.
 */
/**
 * @abstract Performs the verifyRegistrationResponse operation.
 */
+ (nullable NSDictionary *)verifyRegistrationResponse:(NSDictionary *)response
                                           challenge:(NSData *)expectedChallenge
                                              origin:(NSString *)expectedOrigin
                                               error:(NSError **)error;

/*!
 @method verifyAssertionResponse:challenge:origin:publicKey:signCount:newSignCount:error:

 @abstract Verify WebAuthn authentication response (assertion).

 @discussion Validates authentication response from navigator.credentials.get().
 Checks challenge, origin, signature, and sign count. Sign count must increase
 to prevent cloned authenticator attacks.

 @param response Authentication response from client.
 @param expectedChallenge Challenge sent to client.
 @param expectedOrigin Expected origin (e.g., "https://example.com").
 @param publicKey Stored public key in COSE or raw format.
 @param storedSignCount Previously stored sign count.
 @param outSignCount Pointer to receive new sign count.
 @param error Error pointer for validation failures.
 @return YES if valid, NO on validation failure.
 */
/**
 * @abstract Performs the verifyAssertionResponse operation.
 */
+ (BOOL)verifyAssertionResponse:(NSDictionary *)response
                      challenge:(NSData *)expectedChallenge
                         origin:(NSString *)expectedOrigin
                      publicKey:(NSData *)publicKey
                   signCount:(uint32_t)storedSignCount
                    newSignCount:(uint32_t *)outSignCount
                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
