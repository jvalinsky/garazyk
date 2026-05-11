// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSPhoneVerificationProvider.h

 @abstract Phone verification provider protocol and provider factory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain used by phone verification providers and factory methods. */
extern NSString * const PDSPhoneVerificationProviderErrorDomain;

/*!
 @enum PDSPhoneVerificationProviderErrorCode

 @abstract Error codes for provider configuration and request failures.
 */
typedef NS_ENUM(NSInteger, PDSPhoneVerificationProviderErrorCode) {
    PDSPhoneVerificationProviderErrorNotConfigured = 1,
    PDSPhoneVerificationProviderErrorUnsupportedProvider = 2,
    PDSPhoneVerificationProviderErrorRequestFailed = 3,
};

/*!
 @protocol PDSPhoneVerificationProvider

 @abstract Sends verification requests to an external provider.
 */
@protocol PDSPhoneVerificationProvider <NSObject>

/*!
 @method requestVerificationForPhoneNumber:error:

 @abstract Starts a phone verification flow for the provided number.

 @param phoneNumber E.164 or provider-compatible phone number string.
 @param error On failure, set to the provider-specific error.
 @result Session ID string on success (provider-specific, e.g. request_id,
         session_uuid), or nil on failure. For providers that do not use
         session IDs (e.g. Twilio Verify), returns an empty string (@"") on success.
 */
- (nullable NSString *)requestVerificationForPhoneNumber:(NSString *)phoneNumber error:(NSError **)error;

@optional

/*!
 @method verifyCode:forPhoneNumber:sessionID:error:

 @abstract Verifies a code sent to the given phone number.

 @discussion
    Implementations that use a hosted verification service (e.g. Twilio Verify,
    Vonage Verify, Plivo Verify) should implement this method to validate the
    code server-side. The sessionID parameter carries the session identifier
    returned by requestVerificationForPhoneNumber:error:; providers that do
    not require a session ID (e.g. Twilio) may ignore it.

 @param code The verification code entered by the user.
 @param phoneNumber The phone number that received the code.
 @param sessionID The session ID returned by requestVerificationForPhoneNumber:,
        or nil if not applicable.
 @param error On failure, set to a verification error.
 @result YES if the code is valid, NO otherwise.
 */
- (BOOL)verifyCode:(NSString *)code
     forPhoneNumber:(NSString *)phoneNumber
          sessionID:(nullable NSString *)sessionID
              error:(NSError **)error;

/*!
 @method verifyCode:forPhoneNumber:error:

 @abstract Verifies a code sent to the given phone number (legacy).

 @discussion
    Legacy method without session ID support. Prefer
    verifyCode:forPhoneNumber:sessionID:error: for new implementations.
    This method is retained for backward compatibility during the transition.

 @param code The verification code entered by the user.
 @param phoneNumber The phone number that received the code.
 @param error On failure, set to a verification error.
 @result YES if the code is valid, NO otherwise.
 */
- (BOOL)verifyCode:(NSString *)code forPhoneNumber:(NSString *)phoneNumber error:(NSError **)error;

@end

/*!
 @class PDSPhoneVerificationProviderFactory

 @abstract Resolves and manages named phone verification providers.
 */
@interface PDSPhoneVerificationProviderFactory : NSObject

/*!
 @method providerWithName:configuration:secretsProvider:error:

 @abstract Returns a provider instance for a configured provider name.

 @discussion
    This is the preferred factory method. It accepts a secrets provider and
    configuration dictionary, which are required for built-in providers
    (twilio, vonage, plivo, telegram) that need API credentials.

 @param providerName Provider identifier (mock, twilio, vonage, plivo, telegram, custom).
 @param configuration The PDS configuration dictionary.
 @param secretsProvider The secrets provider for resolving credentials.
 @param error On failure, set to a configuration or resolution error.
 @result Provider instance, or nil when unavailable.
 */
+ (nullable id<PDSPhoneVerificationProvider>)providerWithName:(NSString *)providerName
                                                 configuration:(NSDictionary *)configuration
                                                secretsProvider:(nullable id)secretsProvider
                                                          error:(NSError **)error;

/*!
 @method providerWithName:error:

 @abstract Returns a provider instance for a configured provider name (legacy).

 @discussion
    Legacy factory method without secrets provider. Only supports "mock"
    and custom providers registered via registerProviderClass:forName:.
    For built-in providers (twilio, vonage, plivo, telegram), use
    providerWithName:configuration:secretsProvider:error: instead.

 @param providerName Provider identifier (mock, custom provider name, etc.).
 @param error On failure, set to a configuration or resolution error.
 @result Provider instance, or nil when unavailable.
 */
+ (nullable id<PDSPhoneVerificationProvider>)providerWithName:(NSString *)providerName error:(NSError **)error;

/*!
 @method registerProviderClass:forName:

 @abstract Registers a custom provider class for lookup by name.

 @param providerClass Class implementing PDSPhoneVerificationProvider.
 @param providerName Provider identifier used for later resolution.
 */
+ (void)registerProviderClass:(Class)providerClass forName:(NSString *)providerName;

/*!
 @method unregisterProviderWithName:

 @abstract Removes a previously registered custom provider.

 @param providerName Provider identifier to remove.
 */
+ (void)unregisterProviderWithName:(NSString *)providerName;

/*!
 @method resetCustomProviders

 @abstract Clears all registered custom providers.
 */
+ (void)resetCustomProviders;

@end

NS_ASSUME_NONNULL_END
