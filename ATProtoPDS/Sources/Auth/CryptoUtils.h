/*!
 @file CryptoUtils.h

 @abstract Cryptographic utility functions for ATProto operations.

 @discussion Provides common cryptographic primitives including HMAC, SHA-256,
 secure random generation, and hex encoding. Used throughout the PDS for
 hashing, signing, and token generation.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class CryptoUtils

 @abstract Collection of cryptographic utility methods.
 */
@interface CryptoUtils : NSObject

/*! Computes HMAC-SHA1 of data with key. */
+ (nullable NSData *)hmacSHA1WithKey:(NSData *)key data:(NSData *)data;

/*! Computes HMAC-SHA256 of data with key. */
+ (nullable NSData *)hmacSHA256WithKey:(NSData *)key data:(NSData *)data;

/*! Computes SHA-256 hash of data. */
+ (nullable NSData *)sha256:(NSData *)data;

/*! Generates cryptographically secure random bytes. */
+ (nullable NSData *)randomBytes:(NSUInteger)length;

/*! Converts binary data to lowercase hex string. */
+ (NSString *)hexStringFromData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
