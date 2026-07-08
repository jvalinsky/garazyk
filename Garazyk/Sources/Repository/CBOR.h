// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file CBOR.h

 @abstract CBOR (Concise Binary Object Representation) encoding and decoding.

 @discussion Implements RFC 8949 CBOR serialization for ATProto data structures.
 Supports major types 0-7 including integers, byte/text strings, arrays, maps,
 tags, and simple values. Used for repository data and DAG-CBOR encoding.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!

 @abstract CBOR major type identifiers.

 @constant CBORTypeUnsignedInteger Major type 0: unsigned integer.
 @constant CBORTypeNegativeInteger Major type 1: negative integer.
 @constant CBORTypeByteString Major type 2: byte string.
 @constant CBORTypeTextString Major type 3: text string (UTF-8).
 @constant CBORTypeArray Major type 4: array of items.
 @constant CBORTypeMap Major type 5: map of key-value pairs.
 @constant CBORTypeTag Major type 6: semantic tag.
 @constant CBORTypeSimpleOrFloat Major type 7: simple value or float.
 */
/**
 * @abstract Defines CBORType values exposed by this API.
 */
typedef NS_ENUM(NSInteger, CBORType) {
    /** Major type 0: unsigned integer. */
    CBORTypeUnsignedInteger = 0,
    /** Major type 1: negative integer. */
    CBORTypeNegativeInteger = 1,
    /** Major type 2: byte string. */
    CBORTypeByteString = 2,
    /** Major type 3: UTF-8 text string. */
    CBORTypeTextString = 3,
    /** Major type 4: array. */
    CBORTypeArray = 4,
    /** Major type 5: map. */
    CBORTypeMap = 5,
    /** Major type 6: semantic tag. */
    CBORTypeTag = 6,
    /** Major type 7: simple value or floating-point value. */
    CBORTypeSimpleOrFloat = 7
};

/*!
 @class CBORValue

 @abstract Represents a typed CBOR value.

 @discussion Wraps any CBOR data type with accessors for the underlying value.
 Supports encoding to bytes and decoding from bytes.
 */
@interface CBORValue : NSObject <NSCopying>

/*! The CBOR major type of this value. */
@property (nonatomic, assign, readonly) CBORType type;

/*! Unsigned integer for type 0. */
@property (nonatomic, strong, readonly, nullable) NSNumber *unsignedInteger;

/*! Negative integer for type 1. */
@property (nonatomic, strong, readonly, nullable) NSNumber *negativeInteger;

/*! Byte string for type 2. */
@property (nonatomic, copy, readonly, nullable) NSData *byteString;

/*! Text string for type 3. */
@property (nonatomic, copy, readonly, nullable) NSString *textString;

/*! Array of CBORValue items for type 4. */
@property (nonatomic, copy, readonly, nullable) NSArray<CBORValue *> *array;

/*! Map of CBOR key-value pairs for type 5. */
@property (nonatomic, copy, readonly, nullable) NSDictionary<CBORValue *, CBORValue *> *map;

/*! Semantic tag number for type 6. */
@property (nonatomic, strong, readonly, nullable) NSNumber *tag;

/*! Tagged value content for type 6. */
@property (nonatomic, strong, readonly, nullable) CBORValue *tagValue;

/*! Simple value for type 7 (false, true, null, undefined). */
@property (nonatomic, strong, readonly, nullable) NSNumber *simpleValue;

/*! Floating point value for type 7. */
@property (nonatomic, strong, readonly, nullable) NSNumber *floatValue;

/** Creates an unsigned integer CBOR value. */
+ (instancetype)unsignedInteger:(NSUInteger)value;
/** Creates a negative integer CBOR value. */
+ (instancetype)negativeInteger:(NSInteger)value;
/** Creates a byte-string CBOR value. */
+ (instancetype)byteString:(NSData *)data;
/** Creates a text-string CBOR value. */
+ (instancetype)textString:(NSString *)string;
/** Creates an array CBOR value. */
+ (instancetype)array:(NSArray<CBORValue *> *)array;
/** Creates a map CBOR value. */
+ (instancetype)map:(NSDictionary<CBORValue *, CBORValue *> *)map;
/** Creates a tagged CBOR value. */
+ (instancetype)tag:(NSUInteger)tag value:(CBORValue *)value;
/** Creates a simple-value CBOR value. */
+ (instancetype)simple:(NSUInteger)value;
/** Creates a floating-point CBOR value. */
+ (instancetype)floatingPoint:(double)value;
/** Creates a CBOR null value. */
+ (instancetype)nilValue;

/** Initializes a CBOR value with only its major type. */
- (instancetype)initWithType:(CBORType)type;

/** Initializes an unsigned integer CBOR value. */
- (instancetype)initWithUnsignedInteger:(NSNumber *)value;
/** Initializes a negative integer CBOR value. */
- (instancetype)initWithNegativeInteger:(NSNumber *)value;
/** Initializes a byte-string CBOR value. */
- (instancetype)initWithByteString:(NSData *)data;
/** Initializes a text-string CBOR value. */
- (instancetype)initWithTextString:(NSString *)string;
/** Initializes an array CBOR value. */
- (instancetype)initWithArray:(NSArray<CBORValue *> *)array;
/** Initializes a map CBOR value. */
- (instancetype)initWithMap:(NSDictionary<CBORValue *, CBORValue *> *)map;
/** Initializes a tagged CBOR value. */
- (instancetype)initWithTag:(NSNumber *)tag value:(CBORValue *)value;
/** Initializes a simple-value CBOR value. */
- (instancetype)initWithSimpleValue:(NSNumber *)value;
/** Initializes a floating-point CBOR value. */
- (instancetype)initWithFloatValue:(NSNumber *)value;

/*! Encodes this value to CBOR bytes. */
- (NSData *)encode;

/*! Decodes CBOR bytes to a value. */
+ (nullable instancetype)decode:(NSData *)data;

- (BOOL)isEqual:(id)object;
- (NSUInteger)hash;

@end

/*!
 @class CBOREncoder

 @abstract Encodes CBORValue objects to bytes.
 */
@interface CBOREncoder : NSObject

/*! Encodes a CBOR value to byte data. */
+ (NSData *)encode:(CBORValue *)value;

@end

/*!
 @class CBORDecoder

 @abstract Decodes CBOR bytes to CBORValue objects.
 */
@interface CBORDecoder : NSObject

/*! Decodes CBOR data to a value. */
+ (nullable CBORValue *)decode:(NSData *)data;

/*! Decodes CBOR data starting at offset, updates offset after decoding. */
+ (nullable CBORValue *)decode:(NSData *)data offset:(NSUInteger *)offset;

@end

NS_ASSUME_NONNULL_END
