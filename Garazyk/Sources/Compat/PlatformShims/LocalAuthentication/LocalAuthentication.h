// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#ifndef LocalAuthentication_h
#define LocalAuthentication_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LABiometryType) {
    LABiometryTypeNone = 0,
    LABiometryTypeTouchID = 1,
    LABiometryTypeFaceID = 2,
};

typedef NS_ENUM(NSInteger, LAPolicy) {
    LAPolicyDeviceOwnerAuthenticationWithBiometrics = 1,
    LAPolicyDeviceOwnerAuthentication = 2,
};

typedef NS_ENUM(NSInteger, LAError) {
    LAErrorAuthenticationFailed = -1,
    LAErrorUserCancel = -2,
    LAErrorUserFallback = -3,
    LAErrorSystemCancel = -4,
    LAErrorPasscodeNotSet = -5,
    LAErrorBiometryNotAvailable = -6,
    LAErrorBiometryNotEnrolled = -7,
    LAErrorBiometryLockout = -8,
    LAErrorAppCancel = -9,
    LAErrorInvalidContext = -10,
    LAErrorNotInteractive = -11,
};

extern NSString * const LAErrorDomain;

@interface LAContext : NSObject

@property (nonatomic, assign) LABiometryType biometryType;
@property (nonatomic, copy, nullable) NSString *localizedReason;
@property (nonatomic, copy, nullable) NSString *localizedCancelTitle;
@property (nonatomic, copy, nullable) NSString *localizedFallbackTitle;
@property (nonatomic, assign) BOOL interactionNotAllowed;

- (BOOL)canEvaluatePolicy:(LAPolicy)policy error:(NSError **)error;
- (void)evaluatePolicy:(LAPolicy)policy 
       localizedReason:(NSString *)localizedReason 
                 reply:(void (^)(BOOL success, NSError * _Nullable error))reply;
- (BOOL)invalidate;

@end

NS_ASSUME_NONNULL_END

#endif /* LocalAuthentication_h */
