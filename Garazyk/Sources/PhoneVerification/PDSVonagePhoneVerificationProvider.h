// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSVonagePhoneVerificationProvider.h

 @abstract Vonage Verify phone verification provider.

 @discussion
    Uses the Vonage Verify API to send and validate phone verification
    codes. Vonage handles OTP generation, delivery, and rate limiting
    end-to-end. We call /verify/json to send and /verify/check/json
    to validate.

    Requires configuration:
    - Vonage API Key (env:VONAGE_API_KEY)
    - Vonage API Secret (env:VONAGE_API_SECRET)
    - Vonage Brand Name (env:VONAGE_BRAND_NAME, optional, defaults to "Garazyk")

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

#import "Services/Core/PDSPhoneVerificationProvider.h"

@protocol PDSSecretsProvider;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for Vonage provider errors. */
extern NSString *const PDSVonageProviderErrorDomain;

/*!

 @abstract Error codes for Vonage provider operations.
 */
typedef NS_ENUM(NSInteger, PDSVonageProviderErrorCode) {
    PDSVonageProviderErrorNotConfigured = 1,
    PDSVonageProviderErrorMissingAPIKey = 2,
    PDSVonageProviderErrorMissingAPISecret = 3,
    PDSVonageProviderErrorMissingBrandName = 4,
    PDSVonageProviderErrorRequestFailed = 5,
    PDSVonageProviderErrorVerificationFailed = 6,
    PDSVonageProviderErrorInvalidPhoneNumber = 7,
};

/*!
 @class PDSVonagePhoneVerificationProvider

 @abstract Vonage Verify phone verification provider.

 @discussion
    Sends verification codes via Vonage Verify and validates them
    using the /verify/check/json endpoint. Uses form-encoded POST
    requests (Vonage API convention). Thread-safe: the HTTP
    client is lazily initialized on first use.
 */
@interface PDSVonagePhoneVerificationProvider : NSObject <PDSPhoneVerificationProvider>

/*!
 @method initWithSecretsProvider:configuration:
 @abstract Designated initializer.
 @param secretsProvider The secrets provider for resolving Vonage credentials.
 @param configuration The PDS configuration (for env: prefix resolution).
 */
- (instancetype)initWithSecretsProvider:(id<PDSSecretsProvider>)secretsProvider
                          configuration:(NSDictionary *)configuration NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
