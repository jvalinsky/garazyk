/*!
 @file PDSCaptchaRegistrationGate.m

 @abstract CAPTCHA registration gate implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Registration/PDSCaptchaRegistrationGate.h"
#import "Registration/PDSRegistrationGate.h"
#import "App/PDSConfiguration.h"

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
    // TODO: Implement server-side siteverify HTTP call.
    // The current implementation accepts the presence of a non-empty token.
    // Full verification will be added when the HTTP client infrastructure
    // is available for outbound verification requests.

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

    // TODO: Implement HTTP POST to verifyURL with secret + token
    // For now, accept the token if a secret key is configured
    #pragma unused(verifyURL)
    return YES;
}

@end
