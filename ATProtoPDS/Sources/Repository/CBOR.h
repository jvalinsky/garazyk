/*!
 @file CBOR.h

 @abstract CBOR (Concise Binary Object Representation) encoding and decoding.

 @discussion Implements RFC 8949 CBOR serialization for ATProto data structures.
 Supports major types 0-7 including integers, byte/text strings, arrays, maps,
 tags, and simple values. Used for repository data and DAG-CBOR encoding.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @enum CBORType

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
typedef NS_ENUM(NSInteger, CBORType) {
    CBORTypeUnsignedInteger = 0,
    CBORTypeNegativeInteger = 1,
    CBORTypeByteString = 2,
    CBORTypeTextString = 3,
    CBORTypeArray = 4,
    CBORTypeMap = 5,
    CBORTypeTag = 6,
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
@property (nonatomic, strong, readonly, nullable) NSData *byteString;

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

+ (instancetype)unsignedInteger:(NSUInteger)value;
+ (instancetype)negativeInteger:(NSInteger)value;
+ (instancetype)byteString:(NSData *)data;
+ (instancetype)textString:(NSString *)string;
+ (instancetype)array:(NSArray<CBORValue *> *)array;
+ (instancetype)map:(NSDictionary<CBORValue *, CBORValue *> *)map;
+ (instancetype)tag:(NSUInteger)tag value:(CBORValue *)value;
+ (instancetype)simple:(NSUInteger)value;
+ (instancetype)floatingPoint:(double)value;
+ (instancetype)nilValue;

- (instancetype)initWithType:(CBORType)type;

- (instancetype)initWithUnsignedInteger:(NSNumber *)value;
- (instancetype)initWithNegativeInteger:(NSNumber *)value;
- (instancetype)initWithByteString:(NSData *)data;
- (instancetype)initWithTextString:(NSString *)string;
- (instancetype)initWithArray:(NSArray<CBORValue *> *)array;
- (instancetype)initWithMap:(NSDictionary<CBORValue *, CBORValue *> *)map;
- (instancetype)initWithTag:(NSNumber *)tag value:(CBORValue *)value;
- (instancetype)initWithSimpleValue:(NSNumber *)value;
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
