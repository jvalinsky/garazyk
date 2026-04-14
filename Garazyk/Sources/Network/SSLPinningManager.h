#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const SSLPinningErrorDomain;

typedef NS_ENUM(NSInteger, SSLPinningError) {
    SSLPinningErrorCertificateValidationFailed = 1,
    SSLPinningErrorNoPinnedKeysForDomain = 2,
    SSLPinningErrorInvalidCertificate = 3
};

/*!
 @class SSLPinningManager

 @abstract Manages SSL certificate pinning for HTTPS connections.

 @discussion SSLPinningManager validates server certificates against pre-configured
 public keys for specific domains. This prevents man-in-the-middle attacks by ensuring
 connections use expected certificates.

 Certificate pinning can be bypassed in development environments.
 */
@interface SSLPinningManager : NSObject <NSURLSessionDelegate>

/*!
 @property pinningEnabled

 @abstract Whether SSL pinning is currently enabled.

 @discussion When disabled, certificates are validated using standard iOS/macOS trust evaluation
 without additional pinning checks.
 */
@property (nonatomic, readonly, getter=isPinningEnabled) BOOL pinningEnabled;

/*!
 @method sharedManager

 @abstract Returns the shared SSL pinning manager instance.

 @return The singleton SSLPinningManager.
 */
+ (instancetype)sharedManager;

/*!
 @method initWithPinningEnabled:

 @abstract Initializes a new SSL pinning manager.

 @param pinningEnabled Whether pinning should be enabled.

 @return An initialized SSLPinningManager.
 */
- (instancetype)initWithPinningEnabled:(BOOL)pinningEnabled;

/*!
 @method addPinnedPublicKey:forDomain:

 @abstract Adds a pinned public key for a domain.

 @param publicKeyData The DER-encoded public key data.
 @param domain The domain to pin the key for.
 */
- (void)addPinnedPublicKey:(NSData *)publicKeyData forDomain:(NSString *)domain;

/*!
 @method removePinnedKeysForDomain:

 @abstract Removes all pinned keys for a domain.

 @param domain The domain to remove pinned keys for.
 */
- (void)removePinnedKeysForDomain:(NSString *)domain;

/*!
 @method createSessionWithConfiguration:

 @abstract Creates a URLSession configured for SSL pinning.

 @param configuration The session configuration to use.

 @return A URLSession with SSL pinning enabled.
 */
- (NSURLSession *)createSessionWithConfiguration:(NSURLSessionConfiguration *)configuration;

/*!
 @method validateChallenge:forDomain:

 @abstract Validates an authentication challenge for a domain.

 @param challenge The authentication challenge.
 @param domain The domain being connected to.

 @return YES if the challenge is valid, NO otherwise.
 */
- (BOOL)validateChallenge:(NSURLAuthenticationChallenge *)challenge forDomain:(NSString *)domain;

@end

NS_ASSUME_NONNULL_END