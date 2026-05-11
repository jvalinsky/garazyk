// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file TOTPGenerator.h

 @abstract Time-based One-Time Password (TOTP) generation for 2FA.

 @discussion Implements RFC 6238 TOTP generation with configurable parameters.
 Used for two-factor authentication on ATProto accounts.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class TOTPGenerator

 @abstract Generates TOTP codes for two-factor authentication.

 @discussion Creates time-based one-time passwords using HMAC-SHA algorithms.
 Default configuration: 6 digits, 30-second period, SHA-256.
 */
@interface TOTPGenerator : NSObject

/*!
 @method initWithSecret:digits:period:algorithm:

 @abstract Initializes TOTP generator with full configuration.

 @param secret The shared secret key.
 @param digits Number of digits in OTP (typically 6).
 @param period Time period in seconds (typically 30).
 @param algorithm Hash algorithm ("SHA1", "SHA256", "SHA512").
 */
- (instancetype)initWithSecret:(NSData *)secret
                        digits:(NSUInteger)digits
                        period:(NSTimeInterval)period
                     algorithm:(NSString *)algorithm;

/*! Initializes with default parameters (6 digits, 30s, SHA256). */
- (instancetype)initWithSecret:(NSData *)secret;

/*! Generates OTP valid at the specified date. */
- (nullable NSString *)generateOTPForDate:(NSDate *)date;

/*! Generates OTP valid at the current time. */
- (nullable NSString *)generateOTP;

@end

NS_ASSUME_NONNULL_END
