// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSCaptchaRegistrationGate.m

 @abstract CAPTCHA registration gate implementation.

 @discussion
    Server-side siteverify is performed via ATProtoSafeHTTPClient
    (the same client used by PDSEmailHTTPClient and the phone
    providers). The gate fails closed when no secret key is
    configured and when siteverify cannot be reached.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Registration/PDSCaptchaRegistrationGate.h"
#import "Registration/PDSRegistrationGate.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Debug/GZLogger.h"

@interface PDSCaptchaRegistrationGate ()
@property (nonatomic, copy) NSString *provider;
@property (nonatomic, copy, nullable) NSString *siteKey;
@property (nonatomic, copy, nullable) NSString *secretKey;
@property (nonatomic, strong) ATProtoSafeHTTPClient *safeHTTPClient;
@property (nonatomic, assign) NSTimeInterval siteverifyTimeout;
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
        _safeHTTPClient = [ATProtoSafeHTTPClient sharedClient];
        _siteverifyTimeout = 12.0;
    }
    return self;
}

- (NSString *)gateIdentifier {
    return @"captcha";
}

- (BOOL)validateRegistrationRequest:(NSDictionary *)body
                       configuration:(ATProtoServiceConfiguration *)configuration
                               error:(NSError **)error {
    return [self validateRegistrationRequest:body
                               configuration:configuration
                               remoteAddress:nil
                                       error:error];
}

- (BOOL)validateRegistrationRequest:(NSDictionary *)body
                       configuration:(ATProtoServiceConfiguration *)configuration
                       remoteAddress:(nullable NSString *)remoteAddress
                               error:(NSError **)error {
    NSString *captchaToken = body[@"captchaToken"];
    if (![captchaToken isKindOfClass:[NSString class]] || captchaToken.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorCaptchaRequired
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"CAPTCHA verification required"
                                     }];
        }
        return NO;
    }

    // Fail closed when no secret key is configured. An operator who enables
    // captchaRequired without a secret key has a misconfiguration; accepting
    // token presence would give a false sense of verification.
    if (!_secretKey || _secretKey.length == 0) {
        GZ_LOG_WARN(@"[CaptchaGate] Gate enabled but no secret key configured; "
                     @"registration will fail until PDS_CAPTCHA_SECRET_KEY is set");
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorInvalidCaptcha
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"CAPTCHA gate enabled but no secret key configured"
                                     }];
        }
        return NO;
    }

    return [self verifyTokenWithSiteverify:captchaToken remoteAddress:remoteAddress error:error];
}

- (BOOL)verifyTokenWithSiteverify:(NSString *)token
                     remoteAddress:(nullable NSString *)remoteAddress
                            error:(NSError **)error {
    NSString *verifyURLString = nil;
    if ([_provider isEqualToString:@"hcaptcha"]) {
        verifyURLString = @"https://hcaptcha.com/siteverify";
    } else {
        // Default: Cloudflare Turnstile
        verifyURLString = @"https://challenges.cloudflare.com/turnstile/v0/siteverify";
    }

    NSURL *verifyURL = [NSURL URLWithString:verifyURLString];
    if (!verifyURL) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorInvalidCaptcha
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Invalid CAPTCHA siteverify URL"
                                     }];
        }
        return NO;
    }

    // Build form-encoded body: secret=<key>&response=<token>&remoteip=<ip>
    NSMutableDictionary<NSString *, NSString *> *formData = [NSMutableDictionary dictionary];
    formData[@"secret"] = _secretKey;
    formData[@"response"] = token;
    if (remoteAddress.length > 0) {
        formData[@"remoteip"] = remoteAddress;
    }

    NSMutableString *formBody = [NSMutableString string];
    NSUInteger fieldIndex = 0;
    for (NSString *key in @[@"secret", @"response", @"remoteip"]) {
        NSString *value = formData[key];
        if (!value) continue;
        if (fieldIndex > 0) [formBody appendString:@"&"];
        [formBody appendFormat:@"%@=%@", key, [self percentEncode:value]];
        fieldIndex++;
    }

    NSData *bodyData = [formBody dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:verifyURL];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = bodyData;
    request.timeoutInterval = 10.0;

    ATProtoSafeHTTPClientOptions *options = [ATProtoSafeHTTPClientOptions defaultOptions];
    options.timeout = 10.0;
    options.maxResponseBytes = 64 * 1024; // siteverify responses are small

    __block NSDictionary *responseJSON = nil;
    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSError *requestError = nil;
    __block BOOL completed = NO;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [self.safeHTTPClient performSafeDataTaskWithRequest:request
                                                options:options
                                             completion:^(NSData * _Nullable data,
                                                          NSHTTPURLResponse * _Nullable resp,
                                                          NSError * _Nullable taskError) {
        httpResponse = resp;
        requestError = taskError;
        if (!taskError && data && data.length > 0) {
            id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([parsed isKindOfClass:[NSDictionary class]]) {
                responseJSON = parsed;
            }
        }
        completed = YES;
        dispatch_semaphore_signal(semaphore);
    }];

    long waitResult = dispatch_semaphore_wait(semaphore,
                                               dispatch_time(DISPATCH_TIME_NOW,
                                                              (int64_t)(self.siteverifyTimeout * NSEC_PER_SEC)));

    // Timeout — the completion block did not fire in time. Fail closed with
    // a 503-equivalent error so the client retries rather than believing the
    // signup succeeded.
    if (waitResult != 0 || !completed) {
        GZ_LOG_WARN(@"[CaptchaGate] siteverify timed out for provider %@", _provider);
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorInvalidCaptcha
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"CAPTCHA verification service unavailable",
                                         @"httpStatus": @(503),
                                     }];
        }
        return NO;
    }

    // Network error (DNS failure, connection refused, SSRF block, etc.) —
    // fail closed. Do not accept the token on network failure.
    if (requestError) {
        GZ_LOG_WARN(@"[CaptchaGate] siteverify network error for provider %@: %@",
                     _provider, requestError.localizedDescription);
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorInvalidCaptcha
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"CAPTCHA verification service unreachable",
                                         @"httpStatus": @(503),
                                         NSUnderlyingErrorKey: requestError,
                                     }];
        }
        return NO;
    }

    // Non-200 HTTP status — fail closed with 503 (service error, not client error).
    if (!httpResponse || httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
        NSInteger status = httpResponse ? httpResponse.statusCode : 0;
        GZ_LOG_WARN(@"[CaptchaGate] siteverify returned HTTP %ld for provider %@",
                     (long)status, _provider);
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorInvalidCaptcha
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"CAPTCHA verification service error",
                                         @"httpStatus": @(503),
                                     }];
        }
        return NO;
    }

    // Parse the JSON response. The siteverify response shape for both
    // Turnstile and hCaptcha is { "success": true/false, ... }.
    if (!responseJSON) {
        GZ_LOG_WARN(@"[CaptchaGate] siteverify returned unparseable response for provider %@", _provider);
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorInvalidCaptcha
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"CAPTCHA verification returned an invalid response",
                                         @"httpStatus": @(503),
                                     }];
        }
        return NO;
    }

    id successValue = responseJSON[@"success"];
    BOOL success = NO;
    if ([successValue isKindOfClass:[NSNumber class]]) {
        success = [(NSNumber *)successValue boolValue];
    } else if ([successValue isKindOfClass:[NSString class]]) {
        success = [(NSString *)successValue isEqualToString:@"true"];
    }

    if (!success) {
        // The provider explicitly rejected the token. This is a client error
        // (400), not a service error.
        NSString *errorCodes = nil;
        id errorCodesValue = responseJSON[@"error-codes"];
        if ([errorCodesValue isKindOfClass:[NSArray class]]) {
            errorCodes = [(NSArray *)errorCodesValue componentsJoinedByString:@", "];
        }
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorInvalidCaptcha
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"CAPTCHA verification failed",
                                         @"httpStatus": @(400),
                                         @"providerErrorCodes": errorCodes ?: @"",
                                     }];
        }
        return NO;
    }

    // success: true — token is valid
    return YES;
}

- (NSString *)percentEncode:(NSString *)string {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                                @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [string stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

@end
