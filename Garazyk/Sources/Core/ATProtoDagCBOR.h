// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoDagCBOR.h

 @abstract Canonical DAG-CBOR encoder/decoder for ATProto compliance.

 @discussion This is the authoritative CBOR encoder for ATProto repositories.
 It implements DRISL (https://dasl.ing/drisl.html), the deterministic CBOR
 profile ATProto calls DAG-CBOR:
 - Canonical map key ordering (by encoded key bytes, length-first)
 - String-only map keys, no duplicates
 - ATProtoCID-link encoding (CBOR tag 42 with 0x00 marker byte); all other tags rejected
 - JSON $link/$bytes wrapper conversion
 - Minimal-length integer/length encodings only; no indefinite lengths
 - `true`, `false` and `null` are the only simple values; `undefined` is rejected

 This replaces the use of ATProtoCBORSerialization for repo/commit encoding.

 Floats are governed by the profile — see ATProtoDRISLProfile.
 */

#import <Foundation/Foundation.h>

@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

/**
 Which DRISL dialect to encode or decode.

 DRISL permits 64-bit floats; ATProto records do not permit floats at all. Both
 statements are true at once, so the float rule is a profile rather than a
 single global policy. Everything else about the two dialects is identical.
 */
typedef NS_ENUM(NSInteger, ATProtoDRISLProfile) {
    /**
     ATProto records, commits, ATProtoMST nodes and firehose frames. Floats are
     rejected on both encode and decode. This is the default for every
     profile-less API and is what all repository code uses.
     */
    ATProtoDRISLProfileATProto = 0,

    /**
     DRISL as specified. Adds 64-bit floats (major type 7, additional info 27),
     represented by ATProtoDRISLFloat. Half- and single-precision floats stay
     rejected, as do NaN, Infinity and -Infinity; negative zero is permitted.

     Used by the DASL conformance suite and by non-record DASL documents such
     as MASL. Do not use it for anything that gets signed into a repository.
     */
    ATProtoDRISLProfileDRISL = 1
};

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
    ATProtoDagCBORErrorCodeInvalidCIDLink = 5,
    /** A CBOR tag other than 42 was encountered. DRISL permits only tag 42. */
    ATProtoDagCBORErrorCodeDisallowedTag = 6,
    /** A map key was not a text string. DRISL permits only string keys. */
    ATProtoDagCBORErrorCodeNonStringMapKey = 7
};

/**
 A 64-bit IEEE 754 value, for use with ATProtoDRISLProfileDRISL.

 Floats need their own box rather than riding on NSNumber. NSNumber cannot tell
 `0.0` apart from `0`, so a decoded float would re-encode as an integer and
 break content addressing; and GNUstep reports some boxed integers as floating
 types, so inspecting -objCType would misclassify ordinary integers. An
 explicit type makes the distinction unambiguous on both platforms.

 NaN, Infinity and -Infinity are rejected at encode time. Negative zero is
 permitted and round-trips exactly.
 */
@interface ATProtoDRISLFloat : NSObject <NSCopying>

/** The underlying double. */
@property (readonly, nonatomic) double value;

/** Creates a float box. */
+ (instancetype)floatWithValue:(double)value;

/** Initializes a float box. */
- (instancetype)initWithValue:(double)value NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

/**
 ATProto-compliant DAG-CBOR encoder/decoder.
 
 This class handles:
 - Encoding Foundation objects to DAG-CBOR bytes
 - Decoding DAG-CBOR bytes to Foundation objects
 - ATProtoCID-link encoding/decoding (tag 42)
 - JSON wrapper conversion ($link, $bytes)
 - Canonical map ordering
 */
/**
 * @abstract Declares the ATProtoDagCBOR public API.
 */
@interface ATProtoDagCBOR : NSObject

/**
 Encode a Foundation object to canonical DAG-CBOR bytes.
 
 @param object A Foundation object (NSDictionary, NSArray, NSString, NSNumber, NSData, NSNull, or ATProtoCID)
 @param error Error pointer (optional)
 @return DAG-CBOR encoded bytes, or nil on error
 
 @discussion Supported types:
 - NSDictionary → CBOR map (with canonical key ordering)
 - NSArray → CBOR array
 - NSString → CBOR text string
 - NSNumber (integer/boolean only) → CBOR integer/boolean
 - NSData → CBOR byte string
 - NSNull → CBOR null
 - ATProtoCID → CBOR tag 42 (ATProtoCID-link)
 
 Dictionaries with `$link` keys are automatically converted to ATProtoCID-links.
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
 
 @discussion ATProtoCID-links (tag 42) are decoded as ATProtoCID objects.
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
 @return JSON-compatible object with ATProtoCID-links as $link wrappers, or nil on error
 
 @discussion ATProtoCID-links are decoded as `{"$link": "bafy..."}` dictionaries.
 Byte strings are decoded as `{"$bytes": "base64..."}` dictionaries where needed.
 */
+ (nullable id)decodeDataAsJSON:(NSData *)data error:(NSError **)error;

/**
 Encode a Foundation object under an explicit DRISL profile.

 @param object The object to encode. Add ATProtoDRISLFloat to the supported
 types under ATProtoDRISLProfileDRISL.
 @param profile Which DRISL dialect to encode.
 @param error Error pointer (optional)
 @return DRISL-encoded bytes, or nil on error

 @discussion `encodeObject:error:` is this method with
 ATProtoDRISLProfileATProto.
 */
+ (nullable NSData *)encodeObject:(id)object
                          profile:(ATProtoDRISLProfile)profile
                            error:(NSError **)error;

/**
 Decode DRISL bytes under an explicit DRISL profile.

 @param data DRISL-encoded bytes
 @param profile Which DRISL dialect to accept.
 @param error Error pointer (optional)
 @return Decoded Foundation object, or nil on error

 @discussion `decodeData:error:` is this method with
 ATProtoDRISLProfileATProto.
 */
+ (nullable id)decodeData:(NSData *)data
                  profile:(ATProtoDRISLProfile)profile
                    error:(NSError **)error;

/**
 Decode one DRISL item from the beginning of a byte sequence.

 @param data Bytes containing one item, optionally followed by another item.
 @param profile Which DRISL profile to apply.
 @param consumedLength Receives the number of bytes consumed by the first item.
 @param error Error pointer (optional).
 @return The decoded first item, or nil on error.

 @discussion Unlike `decodeData:profile:error:`, this method intentionally
 permits trailing bytes. It is used for the two concatenated CBOR items in an
 AT Protocol XRPC stream frame; callers must validate the remainder separately.
 */
+ (nullable id)decodeOneFromData:(NSData *)data
                         profile:(ATProtoDRISLProfile)profile
                 consumedLength:(NSUInteger *)consumedLength
                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
