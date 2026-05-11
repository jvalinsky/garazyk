// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#include "LocalAuthentication.h"

#if !defined(__APPLE__)

NSString *const LAErrorDomain = @"com.apple.LocalAuthentication";

@implementation LAContext

- (instancetype)init {
    self = [super init];
    if (self) {
        _biometryType = LABiometryTypeNone;
    }
    return self;
}

- (BOOL)canEvaluatePolicy:(LAPolicy)policy error:(NSError **)error {
    if (policy == LAPolicyDeviceOwnerAuthenticationWithBiometrics) {
        if (error) {
            *error = [NSError errorWithDomain:LAErrorDomain
                                        code:LAErrorBiometryNotAvailable
                                    userInfo:@{NSLocalizedDescriptionKey: @"Biometric authentication is not available on this platform"}];
        }
        return NO;
    }
    return NO;
}

- (void)evaluatePolicy:(LAPolicy)policy 
       localizedReason:(NSString *)localizedReason 
                 reply:(void (^)(BOOL success, NSError * _Nullable error))reply {
    if (reply) {
        NSError *error = [NSError errorWithDomain:LAErrorDomain
                                             code:LAErrorBiometryNotAvailable
                                         userInfo:@{NSLocalizedDescriptionKey: @"Biometric authentication is not available on this platform"}];
        reply(NO, error);
    }
}

- (BOOL)invalidate {
    return YES;
}

@end

#endif
