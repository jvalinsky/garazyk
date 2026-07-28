// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSCaptchaRegistrationGate.h

 @abstract CAPTCHA registration gate (Turnstile/hCaptcha).

 @discussion
    Validates that a createAccount request includes a valid CAPTCHA
    token. Supports Cloudflare Turnstile and hCaptcha verification
    via server-side siteverify endpoint. The gate fails closed when
    no secret key is configured (the operator enabled the gate but
    did not provide credentials) and when siteverify cannot be reached
    (network error or timeout). A `success: false` response from the
    provider is a hard rejection.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Registration/PDSRegistrationGate.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSCaptchaRegistrationGate

 @abstract Requires a valid CAPTCHA token for account registration.

 @discussion
    Server-side CAPTCHA verification is performed via the provider's
    siteverify endpoint using ATProtoSafeHTTPClient. The gate accepts
    an optional remoteAddress passed through from the XRPC handler for
    the `remoteip` siteverify field.
 */
@interface PDSCaptchaRegistrationGate : NSObject <PDSRegistrationGate>

/*! Initialize with CAPTCHA provider and site/secret keys. */
- (instancetype)initWithProvider:(NSString *)provider
                         siteKey:(nullable NSString *)siteKey
                       secretKey:(nullable NSString *)secretKey;

@end

NS_ASSUME_NONNULL_END
