// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSPhoneOTPRegistrationGate.h

 @abstract Phone OTP registration gate.

 @discussion
    Validates that a createAccount request includes a valid phone
    verification code. The phone verification provider sends the OTP;
    this gate verifies the code was provided and is valid.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Registration/PDSRegistrationGate.h"

@protocol PDSPhoneVerificationProvider;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSPhoneOTPRegistrationGate

 @abstract Requires a valid phone verification code for account registration.
 */
@interface PDSPhoneOTPRegistrationGate : NSObject <PDSRegistrationGate>

/*! Initialize with a phone verification provider for code validation. */
- (instancetype)initWithPhoneVerificationProvider:(nullable id<PDSPhoneVerificationProvider>)provider;

@end

NS_ASSUME_NONNULL_END
