// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file Base58.h

 @abstract Base58BTC encode/decode helpers.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class Base58

 @abstract Provides Base58BTC conversions used by DID/CID parsing code.
 */
@interface Base58 : NSObject

/*!
 @method encode:

 @abstract Encodes raw bytes as a Base58BTC string.

 @param data Input bytes.
 @result Base58BTC text representation.
 */
+ (NSString *)encode:(NSData *)data;

/*!
 @method decode:

 @abstract Decodes Base58BTC text to raw bytes.

 @param string Base58BTC-encoded text.
 @result Decoded bytes, or nil when input contains invalid characters.
 */
+ (nullable NSData *)decode:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
