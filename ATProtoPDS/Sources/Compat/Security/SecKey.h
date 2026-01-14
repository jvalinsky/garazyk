/**
 * @file SecKey.h
 *
 * @brief SecKey operations compatibility wrapper.
 *
 * Provides cross-platform wrapper for public key operations.
 * On macOS, uses Security framework. On Linux, uses OpenSSL/libsecp256k1.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifndef SecKey_h
#define SecKey_h

#import "Security.h"

@class NSData;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class SecKeyWrapper

 @abstract Cross-platform public key operations.

 @discussion Provides unified interface for public key operations
 across macOS (Security framework) and Linux (OpenSSL).
 */
@interface SecKeyWrapper : NSObject

/*! Extract public key from key data. */
+ (nullable NSData *)publicKeyFromData:(NSData *)keyData error:(NSError **)error;

/*! Encrypt data with public key. */
+ (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key error:(NSError **)error;

/*! Decrypt data with private key. */
+ (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* SecKey_h */
