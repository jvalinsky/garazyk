// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSCaptchaRegistrationGate.h

 @abstract CAPTCHA registration gate (Turnstile/hCaptcha).

 @discussion
    Validates that a createAccount request includes a valid CAPTCHA
    token. Supports Cloudflare Turnstile and hCaptcha verification
    via server-side siteverify endpoint.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Registration/PDSRegistrationGate.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSCaptchaRegistrationGate

 @abstract Requires a valid CAPTCHA token for account registration.

 @warning Server-side CAPTCHA verification is **not implemented**. When a
          secret key is configured, the token is accepted without contacting
          the Turnstile/hCaptcha siteverify endpoint. Without a secret key,
          only token presence is checked. Full server-side verification will
          be added when outbound HTTP client infrastructure is available.
 */
@interface PDSCaptchaRegistrationGate : NSObject <PDSRegistrationGate>

/*! Initialize with CAPTCHA provider and site/secret keys. */
- (instancetype)initWithProvider:(NSString *)provider
                         siteKey:(nullable NSString *)siteKey
                       secretKey:(nullable NSString *)secretKey;

@end

NS_ASSUME_NONNULL_END
