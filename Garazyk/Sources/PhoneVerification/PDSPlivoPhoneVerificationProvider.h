/*!
 @file PDSPlivoPhoneVerificationProvider.h

 @abstract Plivo Verify phone verification provider.

 @discussion
    Uses the Plivo Verify API to send and validate phone verification
    codes. Plivo handles OTP generation, delivery, and fraud shield
    end-to-end. We call /Verify/Session/ to send and
    /Verify/Session/{session_uuid}/ to validate.

    Requires configuration:
    - Plivo Auth ID (env:PLIVO_AUTH_ID)
    - Plivo Auth Token (env:PLIVO_AUTH_TOKEN)

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

#import "Services/Core/PDSPhoneVerificationProvider.h"

@protocol PDSSecretsProvider;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for Plivo provider errors. */
extern NSString *const PDSPlivoProviderErrorDomain;

/*!
 @enum PDSPlivoProviderErrorCode

 @abstract Error codes for Plivo provider operations.
 */
typedef NS_ENUM(NSInteger, PDSPlivoProviderErrorCode) {
    PDSPlivoProviderErrorNotConfigured = 1,
    PDSPlivoProviderErrorMissingAuthID = 2,
    PDSPlivoProviderErrorMissingAuthToken = 3,
    PDSPlivoProviderErrorRequestFailed = 4,
    PDSPlivoProviderErrorVerificationFailed = 5,
    PDSPlivoProviderErrorInvalidPhoneNumber = 6,
};

/*!
 @class PDSPlivoPhoneVerificationProvider

 @abstract Plivo Verify phone verification provider.

 @discussion
    Sends verification codes via Plivo Verify and validates them
    using the /Verify/Session/{session_uuid}/ endpoint. Uses JSON
    POST requests with Basic Auth. Thread-safe: the HTTP
    client is lazily initialized on first use.
 */
@interface PDSPlivoPhoneVerificationProvider : NSObject <PDSPhoneVerificationProvider>

/*!
 @method initWithSecretsProvider:configuration:
 @abstract Designated initializer.
 @param secretsProvider The secrets provider for resolving Plivo credentials.
 @param configuration The PDS configuration (for env: prefix resolution).
 */
- (instancetype)initWithSecretsProvider:(id<PDSSecretsProvider>)secretsProvider
                          configuration:(NSDictionary *)configuration NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
