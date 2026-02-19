// LAContext stub implementation for GNUstep/Linux
#import "LocalAuthentication.h"

#ifndef __APPLE__

NSString * const LAErrorDomain = @"com.apple.LocalAuthentication";

@implementation LAContext

- (instancetype)init {
    self = [super init];
    return self;
}

- (BOOL)canEvaluatePolicy:(LAPolicy)policy error:(NSError **)error {
    // Biometrics not available on Linux
    if (error) {
        *error = [NSError errorWithDomain:LAErrorDomain
                                     code:LAErrorBiometryNotAvailable
                                 userInfo:@{NSLocalizedDescriptionKey: @"Biometric authentication not available on this platform"}];
    }
    return NO;
}

- (void)evaluatePolicy:(LAPolicy)policy
       localizedReason:(NSString *)localizedReason
                 reply:(void(^)(BOOL success, NSError * _Nullable error))reply {
    if (reply) {
        NSError *error = [NSError errorWithDomain:LAErrorDomain
                                             code:LAErrorBiometryNotAvailable
                                         userInfo:@{NSLocalizedDescriptionKey: @"Biometric authentication not available on this platform"}];
        reply(NO, error);
    }
}

- (LABiometryType)biometryType {
    return LABiometryTypeNone;
}

@end

#endif // __APPLE__
