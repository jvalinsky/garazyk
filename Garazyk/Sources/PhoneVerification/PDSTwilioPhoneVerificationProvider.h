// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSTwilioPhoneVerificationProvider.h

 @abstract Twilio Verify phone verification provider.

 @discussion
    Uses the Twilio Verify API to send and validate phone verification
    codes. Twilio handles OTP generation, delivery, rate limiting, and
    fraud guard end-to-end. We call /Verifications to send and
    /VerificationCheck to validate.

    Requires configuration:
    - Twilio Account SID (env:TWILIO_ACCOUNT_SID)
    - Twilio Auth Token (env:TWILIO_AUTH_TOKEN)
    - Twilio Verify Service SID (env:TWILIO_VERIFY_SERVICE_SID)

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

#import "Services/Core/PDSPhoneVerificationProvider.h"

@protocol PDSSecretsProvider;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for Twilio provider errors. */
extern NSString *const PDSTwilioProviderErrorDomain;

/*!

 @abstract Error codes for Twilio provider operations.
 */
typedef NS_ENUM(NSInteger, PDSTwilioProviderErrorCode) {
    PDSTwilioProviderErrorNotConfigured = 1,
    PDSTwilioProviderErrorMissingAccountSID = 2,
    PDSTwilioProviderErrorMissingAuthToken = 3,
    PDSTwilioProviderErrorMissingServiceSID = 4,
    PDSTwilioProviderErrorRequestFailed = 5,
    PDSTwilioProviderErrorVerificationFailed = 6,
    PDSTwilioProviderErrorInvalidPhoneNumber = 7,
};

/*!
 @class PDSTwilioPhoneVerificationProvider

 @abstract Twilio Verify phone verification provider.

 @discussion
    Sends verification codes via Twilio Verify and validates them
    using the /VerificationCheck endpoint. Thread-safe: the HTTP
    client is lazily initialized on first use.
 */
@interface PDSTwilioPhoneVerificationProvider : NSObject <PDSPhoneVerificationProvider>

/*!
 @method initWithSecretsProvider:configuration:
 @abstract Designated initializer.
 @param secretsProvider The secrets provider for resolving Twilio credentials.
 @param configuration The PDS configuration (for env: prefix resolution).
 */
- (instancetype)initWithSecretsProvider:(id<PDSSecretsProvider>)secretsProvider
                          configuration:(NSDictionary *)configuration NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
