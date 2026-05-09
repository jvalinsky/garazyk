/*!
 @file PDSPhoneOTPRegistrationGate.m

 @abstract Phone OTP registration gate implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Registration/PDSPhoneOTPRegistrationGate.h"
#import "Registration/PDSRegistrationGate.h"
#import "App/PDSConfiguration.h"
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
                       configuration:(PDSConfiguration *)configuration
                               error:(NSError **)error {
    NSString *phoneCode = body[@"phoneVerificationCode"];
    if (!phoneCode || phoneCode.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorPhoneVerificationRequired
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Phone verification code required"
                                     }];
        }
        return NO;
    }

    NSString *phoneNumber = body[@"phoneNumber"];
    if (!phoneNumber || phoneNumber.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorInvalidPhoneVerification
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Phone number required for verification"
                                     }];
        }
        return NO;
    }

    // If a phone verification provider is available and supports
    // verifyCode:forPhoneNumber:sessionID:error:, use it for server-side validation.
    NSString *sessionID = body[@"verificationSessionID"];
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

    // No provider available — accept the presence of a non-empty code.
    // This is the fallback for mock/none providers that only send codes
    // but don't validate them server-side.
    return YES;
}

@end
