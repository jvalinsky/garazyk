// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PKCEUtil.h

 @abstract PKCE (Proof Key for Code Exchange) utilities for OAuth 2.0.

 @discussion Implements RFC 7636 PKCE for public OAuth clients. Generates
 code verifiers and S256 code challenges to secure authorization code flows.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PKCEUtil

 @abstract PKCE code challenge utilities.
 */
@interface PKCEUtil : NSObject

/*! Generates a cryptographically random code verifier (43-128 chars). */
+ (NSString *)generateCodeVerifier;

/*! Creates a S256 code challenge from a verifier. */
+ (NSString *)generateCodeChallengeWithVerifier:(NSString *)verifier;

/*! Verifies that a challenge matches a verifier. */
+ (BOOL)verifyCodeChallenge:(NSString *)challenge withVerifier:(NSString *)verifier;

@end

NS_ASSUME_NONNULL_END
