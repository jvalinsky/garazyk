/*!
 @file KeyRotationManager.h

 @abstract JWT signing key rotation manager.

 @discussion Manages lifecycle of JWT signing keys including generation,
 rotation, and grace period for old keys. Old keys retained for 7 days to
 allow in-flight tokens to validate without immediate session breaks.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for key rotation operations. */
extern NSString * const KeyRotationManagerErrorDomain;

/*!
 @enum KeyRotationManagerError

 @abstract Error codes for key rotation.

 @constant KeyRotationManagerErrorKeyGenerationFailed Key generation failed.
 @constant KeyRotationManagerErrorKeyNotFound Required key not found.
 @constant KeyRotationManagerErrorRotationFailed Key rotation failed.
 */
typedef NS_ENUM(NSInteger, KeyRotationManagerError) {
    KeyRotationManagerErrorKeyGenerationFailed = 1000,
    KeyRotationManagerErrorKeyNotFound,
    KeyRotationManagerErrorRotationFailed
};

@class KeyManager;

/*!
 @class KeyRotationManager

 @abstract Manages JWT signing key rotation.

 @discussion Rotates signing keys while maintaining grace period for old keys.
 Ensures in-flight tokens remain valid during rotation. Old keys retained for
 7 days to prevent session interruption.
 */
@interface KeyRotationManager : NSObject

/*! Initialize with key store. */
- (instancetype)initWithKeyStore:(KeyManager *)keyStore;

/*! Get current active signing key. */
- (SecKeyRef _Nullable)currentSigningKey;

/*! Get all valid public keys (current + grace period). */
- (NSArray *)allValidPublicKeys;

/*! Rotate to new signing key, marking old key for grace period. */
- (BOOL)rotateKeys;

/*! Sign data with current signing key. */
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;

/*! Verify signature with any valid public key (current + grace period). */
- (BOOL)verifySignature:(NSData *)signature forData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END