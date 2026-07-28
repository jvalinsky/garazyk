// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSPhoneOTPRegistrationGate.m

 @abstract Phone OTP registration gate implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Registration/PDSPhoneOTPRegistrationGate.h"
#import "Registration/PDSRegistrationGate.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Services/Core/PDSPhoneVerificationProvider.h"

@interface PDSPhoneOTPRegistrationGate ()
@property (nonatomic, strong, nullable) id<PDSPhoneVerificationProvider> provider;
@end

@implementation PDSPhoneOTPRegistrationGate

- (instancetype)initWithPhoneVerificationProvider:(nullable id<PDSPhoneVerificationProvider>)provider {
    self = [super init];
    if (self) {
        _provider = provider;
    }
    return self;
}

- (NSString *)gateIdentifier {
    return @"phone_otp";
}

- (BOOL)validateRegistrationRequest:(NSDictionary *)body
                       configuration:(ATProtoServiceConfiguration *)configuration
                               error:(NSError **)error {
    id phoneCodeValue = body[@"phoneVerificationCode"];
    if (![phoneCodeValue isKindOfClass:[NSString class]] || ((NSString *)phoneCodeValue).length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorPhoneVerificationRequired
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Phone verification code required"
                                     }];
        }
        return NO;
    }

    NSString *phoneCode = (NSString *)phoneCodeValue;

    id phoneNumberValue = body[@"phoneNumber"];
    if (![phoneNumberValue isKindOfClass:[NSString class]] || ((NSString *)phoneNumberValue).length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorInvalidPhoneVerification
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Phone number required for verification"
                                     }];
        }
        return NO;
    }

    NSString *phoneNumber = (NSString *)phoneNumberValue;

    // E.164 validation: must start with + followed by 7-15 digits, no other characters (ADR 0020, phase-23 slice 5).
    if (![phoneNumber hasPrefix:@"+"] || phoneNumber.length < 8 || phoneNumber.length > 16) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorInvalidPhoneVerification
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Phone number must be in E.164 format (e.g. +1234567890)"
                                     }];
        }
        return NO;
    }
    NSString *afterPlus = [phoneNumber substringFromIndex:1];
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([afterPlus rangeOfCharacterFromSet:nonDigits].location != NSNotFound ||
        afterPlus.length < 7 || afterPlus.length > 15) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorInvalidPhoneVerification
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Phone number must contain only digits after + in E.164 format"
                                     }];
        }
        return NO;
    }

    // If a phone verification provider is available and supports
    // verifyCode:forPhoneNumber:sessionID:error:, use it for server-side validation.
    id sessionIDValue = body[@"verificationSessionID"];
    NSString *sessionID = [sessionIDValue isKindOfClass:[NSString class]] ? (NSString *)sessionIDValue : nil;
    if (_provider && [_provider respondsToSelector:@selector(verifyCode:forPhoneNumber:sessionID:error:)]) {
        NSError *verifyError = nil;
        BOOL verified = [(id<PDSPhoneVerificationProvider>)_provider verifyCode:phoneCode
                                                                forPhoneNumber:phoneNumber
                                                                     sessionID:sessionID
                                                                          error:&verifyError];
        if (!verified) {
            if (error) {
                *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                             code:PDSRegistrationGateErrorInvalidPhoneVerification
                                         userInfo:@{
                                             NSLocalizedDescriptionKey:
                                                 verifyError.localizedDescription ?: @"Phone verification code is invalid"
                                         }];
            }
            return NO;
        }
        return YES;
    }

    // Fallback: try the legacy verifyCode:forPhoneNumber:error: method
    if (_provider && [_provider respondsToSelector:@selector(verifyCode:forPhoneNumber:error:)]) {
        NSError *verifyError = nil;
        BOOL verified = [(id<PDSPhoneVerificationProvider>)_provider verifyCode:phoneCode
                                                                forPhoneNumber:phoneNumber
                                                                          error:&verifyError];
        if (!verified) {
            if (error) {
                *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                             code:PDSRegistrationGateErrorInvalidPhoneVerification
                                         userInfo:@{
                                             NSLocalizedDescriptionKey:
                                                 verifyError.localizedDescription ?: @"Phone verification code is invalid"
                                         }];
            }
            return NO;
        }
        return YES;
    }

    // No provider available — fail closed (ADR 0020). A nil provider
    // means the phone gate is misconfigured (provider failed to construct
    // or was set to "none"), and silently accepting registration would
    // defeat the gate entirely.
    if (error) {
        *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                     code:PDSRegistrationGateErrorPhoneVerificationProviderUnavailable
                                 userInfo:@{
                                     NSLocalizedDescriptionKey:
                                         @"Phone verification service unavailable"
                                 }];
    }
    return NO;
}

@end
