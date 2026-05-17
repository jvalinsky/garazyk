// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file NSDictionary+CID.h

 @abstract NSDictionary category for extracting CID string values from CBOR-decoded dictionaries.

 @discussion When ATProtoDagCBOR decodes CBOR data, CID values (tag 42) are
 returned as CID objects, not NSString. This category provides a safe accessor
 that handles CID objects, NSString, and NSNull values, returning the canonical
 CID string representation or nil.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class CID;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Extends NSDictionary with cidadditions behavior.
 */
@interface NSDictionary (CIDAdditions)

/*!
 @method cidStringForKey:
 @abstract Extract a CID string from a dictionary value that may be a CID object, NSString, or NSNull.

 @param key The dictionary key whose value contains a CID.
 @return The CID string representation, or nil if the value is NSNull, nil, or not a CID/NSString.

 @discussion Use this when reading from CBOR-decoded dictionaries where CID values
 are CID objects (from tag 42 decode) rather than strings. For example:
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
 @abstract Extract a CID object from a dictionary value that may be a CID object, NSString, or NSNull.

 @param key The dictionary key whose value contains a CID.
 @return The CID object, or nil if the value is NSNull, nil, or not a valid CID.

 @discussion Use this when you need the CID object itself rather than its string representation.
 If the value is an NSString, it will be parsed into a CID object via +[CID cidFromString:].
 */
- (nullable CID *)cidObjectForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
