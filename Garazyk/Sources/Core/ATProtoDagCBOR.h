// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoDagCBOR.h

 @abstract Canonical DAG-CBOR encoder/decoder for ATProto compliance.

 @discussion This is the authoritative CBOR encoder for ATProto repositories.
 It implements the DRISL-CBOR subset used by ATProto:
 - Canonical map key ordering (by encoded key bytes, length-first)
 - CID-link encoding (CBOR tag 42 with 0x00 marker byte)
 - JSON $link/$bytes wrapper conversion
 - Float rejection (DRISL-CBOR forbids IEEE 754 floats)
 
 This replaces the use of ATProtoCBORSerialization for repo/commit encoding.
 */

#import <Foundation/Foundation.h>

@class CID;

NS_ASSUME_NONNULL_BEGIN

/**
 Error domain for DAG-CBOR operations.
 */
extern NSString * const ATProtoDagCBORErrorDomain;

/**
 * @abstract Defines ATProtoDagCBORErrorCode values exposed by this API.
 */
typedef NS_ENUM(NSInteger, ATProtoDagCBORErrorCode) {
    ATProtoDagCBORErrorCodeEncodingFailed = 1,
    ATProtoDagCBORErrorCodeDecodingFailed = 2,
    ATProtoDagCBORErrorCodeInvalidType = 3,
    ATProtoDagCBORErrorCodeFloatsNotAllowed = 4,
    ATProtoDagCBORErrorCodeInvalidCIDLink = 5
};

/**
 ATProto-compliant DAG-CBOR encoder/decoder.
 
 This class handles:
 - Encoding Foundation objects to DAG-CBOR bytes
 - Decoding DAG-CBOR bytes to Foundation objects
 - CID-link encoding/decoding (tag 42)
 - JSON wrapper conversion ($link, $bytes)
 - Canonical map ordering
 */
/**
 * @abstract Declares the ATProtoDagCBOR public API.
 */
@interface ATProtoDagCBOR : NSObject

/**
 Encode a Foundation object to canonical DAG-CBOR bytes.
 
 @param object A Foundation object (NSDictionary, NSArray, NSString, NSNumber, NSData, NSNull, or CID)
 @param error Error pointer (optional)
 @return DAG-CBOR encoded bytes, or nil on error
 
 @discussion Supported types:
 - NSDictionary → CBOR map (with canonical key ordering)
 - NSArray → CBOR array
 - NSString → CBOR text string
 - NSNumber (integer/boolean only) → CBOR integer/boolean
 - NSData → CBOR byte string
 - NSNull → CBOR null
 - CID → CBOR tag 42 (CID-link)
 
 Dictionaries with `$link` keys are automatically converted to CID-links.
 Dictionaries with `$bytes` keys are converted to byte strings.
 
 Floats are rejected with ATProtoDagCBORErrorCodeFloatsNotAllowed.
 */
/**
 * @abstract Performs the encodeObject operation.
 */
+ (nullable NSData *)encodeObject:(id)object error:(NSError **)error;

/**
 Decode DAG-CBOR bytes to a Foundation object.
 
 @param data DAG-CBOR encoded bytes
 @param error Error pointer (optional)
 @return Decoded Foundation object, or nil on error
 
 @discussion CID-links (tag 42) are decoded as CID objects.
 */
+ (nullable id)decodeData:(NSData *)data error:(NSError **)error;

/**
 Encode a Foundation object with JSON wrapper conversion.
 
 @param jsonObject A JSON-compatible object (may contain $link/$bytes wrappers)
 @param error Error pointer (optional)
 @return DAG-CBOR encoded bytes, or nil on error
 
 @discussion This is the preferred method for encoding records, as it handles
 the JSON→DAG-CBOR conversion including $link and $bytes wrappers.
 */
+ (nullable NSData *)encodeJSONObject:(id)jsonObject error:(NSError **)error;

/**
 Decode DAG-CBOR bytes to a JSON-compatible object.
 
 @param data DAG-CBOR encoded bytes
 @param error Error pointer (optional)
 @return JSON-compatible object with CID-links as $link wrappers, or nil on error
 
 @discussion CID-links are decoded as `{"$link": "bafy..."}` dictionaries.
 Byte strings are decoded as `{"$bytes": "base64..."}` dictionaries where needed.
 */
+ (nullable id)decodeDataAsJSON:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
