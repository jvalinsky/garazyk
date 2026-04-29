/*!
 @file TutorialBase64URL.h

 @abstract Base64URL encoding and decoding for tutorial examples.

 @discussion Provides RFC 4648 §5 base64url encoding without padding.
 Shared across all tutorials that handle JWT, CID, or JWK encoding.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class TutorialBase64URL

 @abstract Base64URL encode/decode without padding.

 @discussion Standard base64 uses '+' and '/' with '=' padding.
 Base64URL replaces '+' with '-', '/' with '_', and removes padding.
 This is used in JWT, JWK, and CID encodings throughout ATProto.
 */
@interface TutorialBase64URL : NSObject

/*! Encodes data to base64url string (no padding). */
+ (NSString *)encode:(NSData *)data;

/*! Decodes base64url string to data. Returns nil on invalid input. */
+ (nullable NSData *)decode:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
