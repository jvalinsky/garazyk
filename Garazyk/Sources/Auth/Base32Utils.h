/*!
 @file Base32Utils.h

 @abstract Base32 encoding and decoding utilities.

 @discussion Provides RFC 4648 Base32 encoding/decoding for TOTP secrets
 and other binary data that needs text representation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class Base32Utils

 @abstract Base32 encoding and decoding.
 */
@interface Base32Utils : NSObject

/*! Decodes a Base32 string to binary data. */
+ (nullable NSData *)dataFromBase32String:(NSString *)base32String;

/*! Encodes binary data as a Base32 string. */
+ (NSString *)base32StringFromData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
