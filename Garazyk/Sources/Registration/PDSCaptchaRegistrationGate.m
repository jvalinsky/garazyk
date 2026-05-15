// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSCaptchaRegistrationGate.m

 @abstract CAPTCHA registration gate implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Registration/PDSCaptchaRegistrationGate.h"
#import "Registration/PDSRegistrationGate.h"
#import "App/PDSConfiguration.h"

#pragma message "CAPTCHA server-side verification is not implemented — tokens are accepted without siteverify"

@interface PDSCaptchaRegistrationGate ()
@property (nonatomic, copy) NSString *provider;
@property (nonatomic, copy, nullable) NSString *siteKey;
@property (nonatomic, copy, nullable) NSString *secretKey;
@end

@implementation PDSCaptchaRegistrationGate

- (instancetype)initWithProvider:(NSString *)provider
                         siteKey:(nullable NSString *)siteKey
                       secretKey:(nullable NSString *)secretKey {
    self = [super init];
    if (self) {
        _provider = [provider copy] ?: @"turnstile";
        _siteKey = [siteKey copy];
        _secretKey = [secretKey copy];
    }
    return self;
}

- (NSString *)gateIdentifier {
    return @"captcha";
}

- (BOOL)validateRegistrationRequest:(NSDictionary *)body
                       configuration:(PDSConfiguration *)configuration
                               error:(NSError **)error {
    NSString *captchaToken = body[@"captchaToken"];
    if (!captchaToken || captchaToken.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorCaptchaRequired
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"CAPTCHA verification required"
                                     }];
        }
        return NO;
    }

    // Server-side CAPTCHA verification.
    // For Turnstile: POST https://challenges.cloudflare.com/turnstile/v0/siteverify
    // For hCaptcha: POST https://hcaptcha.com/siteverify
    //
    // FIXME: Server-side siteverify HTTP call not implemented.
    // The current implementation accepts the presence of a non-empty token
    // without verifying it against the provider's siteverify endpoint.
    // This is a security gap — tokens could be fabricated. Full verification
    // requires an outbound HTTP client, which is not yet available in the
    // infrastructure layer.

    if (!_secretKey || _secretKey.length == 0) {
        // No secret key configured — accept token presence only
        return YES;
    }

    // When secret key is configured, perform server-side verification
    return [self verifyTokenWithSiteverify:captchaToken error:error];
}

- (BOOL)verifyTokenWithSiteverify:(NSString *)token error:(NSError **)error {
    NSString *verifyURL = nil;
    if ([_provider isEqualToString:@"hcaptcha"]) {
        verifyURL = @"https://hcaptcha.com/siteverify";
    } else {
        // Default: Turnstile
        verifyURL = @"https://challenges.cloudflare.com/turnstile/v0/siteverify";
    }

    // FIXME: HTTP POST to verifyURL with secret + token not implemented.
    // Currently accepts any token when a secret key is configured.
    // Must POST to the provider's siteverify endpoint with
    //   { secret: <secretKey>, response: <token> }
    // and check the success field in the JSON response.
    #pragma unused(verifyURL)
    return YES;
}

@end
