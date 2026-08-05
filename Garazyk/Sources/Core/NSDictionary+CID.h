// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file NSDictionary+ATProtoCID.h

 @abstract NSDictionary category for extracting ATProtoCID string values from CBOR-decoded dictionaries.

 @discussion When ATProtoDagCBOR decodes CBOR data, ATProtoCID values (tag 42) are
 returned as ATProtoCID objects, not NSString. This category provides a safe accessor
 that handles ATProtoCID objects, NSString, and NSNull values, returning the canonical
 ATProtoCID string representation or nil.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Extends NSDictionary with cidadditions behavior.
 */
@interface NSDictionary (CIDAdditions)

/*!
 @method cidStringForKey:
 @abstract Extract a ATProtoCID string from a dictionary value that may be a ATProtoCID object, NSString, or NSNull.

 @param key The dictionary key whose value contains a ATProtoCID.
 @return The ATProtoCID string representation, or nil if the value is NSNull, nil, or not a ATProtoCID/NSString.

 @discussion Use this when reading from CBOR-decoded dictionaries where ATProtoCID values
 are ATProtoCID objects (from tag 42 decode) rather than strings. For example:
 @code
   NSString *cidStr = [op cidStringForKey:@"cid"];
 @endcode
 */
/**
 * @abstract Performs the cidStringForKey operation.
 */
- (nullable NSString *)cidStringForKey:(NSString *)key;

/*!
 @method cidObjectForKey:
 @abstract Extract a ATProtoCID object from a dictionary value that may be a ATProtoCID object, NSString, or NSNull.

 @param key The dictionary key whose value contains a ATProtoCID.
 @return The ATProtoCID object, or nil if the value is NSNull, nil, or not a valid ATProtoCID.

 @discussion Use this when you need the ATProtoCID object itself rather than its string representation.
 If the value is an NSString, it will be parsed into a ATProtoCID object via +[ATProtoCID cidFromString:].
 */
- (nullable ATProtoCID *)cidObjectForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
