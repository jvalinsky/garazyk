// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class ATProtoBase32
 
 @abstract ATProto-compliant Base32 implementation.
 
 @discussion Implements Base32 encoding and decoding using the sortable alphabet
 "234567abcdefghijklmnopqrstuvwxyz" as required by ATProto TIDs and CIDs.
 */
@interface ATProtoBase32 : NSObject

/*!
 @method encodeData:
 
 @abstract Encodes data into a Base32 string.
 
 @param data The data to encode.
 @return The Base32-encoded string.
 */
+ (NSString *)encodeData:(NSData *)data;

/*!
 @method decodeString:
 
 @abstract Decodes a Base32 string into data.
 
 @param string The Base32 string to decode.
 @return The decoded data, or nil if the string is invalid.
 */
+ (nullable NSData *)decodeString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
