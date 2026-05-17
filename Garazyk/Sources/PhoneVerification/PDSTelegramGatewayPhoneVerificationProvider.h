// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSTelegramGatewayPhoneVerificationProvider.h

 @abstract Telegram Gateway phone verification provider.

 @discussion
    Uses the Telegram Gateway API to send and validate phone verification
    codes. Telegram handles OTP generation, delivery, and validation
    end-to-end. We call sendVerificationMessage to send and
    checkVerificationStatus to validate.

    The Telegram Gateway API is purpose-built for verification code delivery,
    costing $0.01 per verified code with automatic refunds for undelivered
    messages. It supports an optional checkSendAbility call to verify a user
    can receive Telegram messages before incurring a charge.

    Requires configuration:
    - Telegram Gateway Token (env:TELEGRAM_GATEWAY_TOKEN)

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

#import "Services/Core/PDSPhoneVerificationProvider.h"

/**
 * @abstract Defines the PDSSecretsProvider protocol contract.
 */
@protocol PDSSecretsProvider;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for Telegram Gateway provider errors. */
extern NSString *const PDSTelegramGatewayProviderErrorDomain;

/*!

 @abstract Error codes for Telegram Gateway provider operations.
 */
typedef NS_ENUM(NSInteger, PDSTelegramGatewayProviderErrorCode) {
    PDSTelegramGatewayProviderErrorNotConfigured = 1,
    PDSTelegramGatewayProviderErrorMissingToken = 2,
    PDSTelegramGatewayProviderErrorRequestFailed = 3,
    PDSTelegramGatewayProviderErrorVerificationFailed = 4,
    PDSTelegramGatewayProviderErrorInvalidPhoneNumber = 5,
    PDSTelegramGatewayProviderErrorSendAbilityCheckFailed = 6,
};

/*!
 @class PDSTelegramGatewayPhoneVerificationProvider

 @abstract Telegram Gateway phone verification provider.

 @discussion
    Sends verification codes via the Telegram Gateway API and validates
    them using the checkVerificationStatus endpoint. Uses JSON POST
    requests with Bearer token authentication. Thread-safe: the HTTP
    client is lazily initialized on first use.

    The provider optionally calls checkSendAbility before sending a
    verification message to verify the user can receive Telegram
    messages, avoiding unnecessary charges for unreachable numbers.
    The request_id from checkSendAbility is passed to
    sendVerificationMessage for free delivery.
 */
/**
 * @abstract Declares the PDSTelegramGatewayPhoneVerificationProvider public API.
 */
@interface PDSTelegramGatewayPhoneVerificationProvider : NSObject <PDSPhoneVerificationProvider>

/*!
 @method initWithSecretsProvider:configuration:
 @abstract Designated initializer.
 @param secretsProvider The secrets provider for resolving Telegram credentials.
 @param configuration The PDS configuration (for env: prefix resolution).
 */
- (instancetype)initWithSecretsProvider:(id<PDSSecretsProvider>)secretsProvider
                          configuration:(NSDictionary *)configuration NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
