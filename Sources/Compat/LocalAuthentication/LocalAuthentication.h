// LocalAuthentication stub for GNUstep/Linux
// LAContext and related APIs are macOS-only
#ifndef LOCAL_AUTHENTICATION_H
#define LOCAL_AUTHENTICATION_H

#if defined(__APPLE__)
#import <LocalAuthentication/LocalAuthentication.h>
#else

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, LAPolicy) {
    LAPolicyDeviceOwnerAuthenticationWithBiometrics = 1,
    LAPolicyDeviceOwnerAuthentication = 2
};

typedef NS_ENUM(NSInteger, LAError) {
    LAErrorAuthenticationFailed = -1,
    LAErrorUserCancel = -2,
    LAErrorUserFallback = -3,
    LAErrorSystemCancel = -4,
    LAErrorPasscodeNotSet = -5,
    LAErrorBiometryNotAvailable = -6,
    LAErrorBiometryNotEnrolled = -7,
    LAErrorBiometryLockout = -8
};

typedef NS_ENUM(NSInteger, LABiometryType) {
    LABiometryTypeNone = 0,
    LABiometryTypeTouchID = 1,
    LABiometryTypeFaceID = 2
};

extern NSString * const LAErrorDomain;

@interface LAContext : NSObject

@property (nonatomic, copy, nullable) NSString *localizedFallbackTitle;
@property (nonatomic, copy, nullable) NSString *localizedCancelTitle;
@property (nonatomic, copy, nullable) NSString *localizedReason;
@property (nonatomic, readonly) LABiometryType biometryType;

- (BOOL)canEvaluatePolicy:(LAPolicy)policy error:(NSError **)error;
- (void)evaluatePolicy:(LAPolicy)policy
       localizedReason:(NSString *)localizedReason
                 reply:(void(^)(BOOL success, NSError * _Nullable error))reply;

@end

#endif // __APPLE__

#endif // LOCAL_AUTHENTICATION_H
