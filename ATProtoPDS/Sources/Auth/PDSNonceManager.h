#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSNonceManager
 @abstract Manages creation and validation of DPoP nonces.
 */
@interface PDSNonceManager : NSObject

/*! Returns the shared nonce manager instance. */
+ (instancetype)sharedManager;

/*! 
 @method generateNonce
 @abstract Generates a new cryptographically secure nonce.
 @return A new nonce string.
 */
- (NSString *)generateNonce;

/*!
 @method validateNonce:
 @abstract Validates a nonce provided by a client.
 @param nonce The nonce string to validate.
 @return YES if the nonce is valid and has not expired, NO otherwise.
 */
- (BOOL)validateNonce:(NSString *)nonce;

@end

NS_ASSUME_NONNULL_END
