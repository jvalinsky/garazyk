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
 @result YES when request submission succeeds, otherwise NO.
 */
- (BOOL)requestVerificationForPhoneNumber:(NSString *)phoneNumber error:(NSError **)error;

@end

/*!
 @class PDSPhoneVerificationProviderFactory

 @abstract Resolves and manages named phone verification providers.
 */
@interface PDSPhoneVerificationProviderFactory : NSObject

/*!
 @method providerWithName:error:

 @abstract Returns a provider instance for a configured provider name.

 @param providerName Provider identifier (`mock`, custom provider name, etc.).
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
