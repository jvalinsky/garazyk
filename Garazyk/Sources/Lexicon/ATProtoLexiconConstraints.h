// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoLexiconConstraints.h

 @abstract Constraint definitions for lexicon validation.

 @discussion Defines constraint objects for all ATProto lexicon data types,
 including strings, integers, arrays, objects, blobs, and unions.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ATProtoLexiconDef;

/*!
 @class ATProtoLexiconStringConstraints

 @abstract Constraints for string type validation.

 @discussion Supports format validation, length limits (bytes and graphemes),
 enum/known values, and constant/default values.
 */
@interface ATProtoLexiconStringConstraints : NSObject

/*! Format identifier (at-identifier, at-uri, cid, datetime, did, handle, nsid, tid, record-key, uri, language). */
@property (nonatomic, copy, nullable) NSString *format;

/*! Maximum length in UTF-8 bytes. */
@property (nonatomic, strong, nullable) NSNumber *maxLength;

/*! Minimum length in UTF-8 bytes. */
@property (nonatomic, strong, nullable) NSNumber *minLength;

/*! Maximum length in Unicode grapheme clusters. */
@property (nonatomic, strong, nullable) NSNumber *maxGraphemes;

/*! Minimum length in Unicode grapheme clusters. */
@property (nonatomic, strong, nullable) NSNumber *minGraphemes;

/*! Closed set of allowed values (enum). */
@property (nonatomic, strong, nullable) NSArray<NSString *> *enumValues;

/*! Suggested values (not restrictive). */
@property (nonatomic, strong, nullable) NSArray<NSString *> *knownValues;

/*! Fixed constant value. */
@property (nonatomic, copy, nullable) NSString *constValue;

/*! Default value if not provided. */
@property (nonatomic, copy, nullable) NSString *defaultValue;

@end

/*!
 @class ATProtoLexiconIntegerConstraints

 @abstract Constraints for integer type validation.
 */
@interface ATProtoLexiconIntegerConstraints : NSObject

/*! Minimum acceptable value. */
@property (nonatomic, strong, nullable) NSNumber *minimum;

/*! Maximum acceptable value. */
@property (nonatomic, strong, nullable) NSNumber *maximum;

/*! Closed set of allowed values (enum). */
@property (nonatomic, strong, nullable) NSArray<NSNumber *> *enumValues;

/*! Fixed constant value. */
@property (nonatomic, strong, nullable) NSNumber *constValue;

/*! Default value if not provided. */
@property (nonatomic, strong, nullable) NSNumber *defaultValue;

@end

/*!
 @class ATProtoLexiconBooleanConstraints

 @abstract Constraints for boolean type validation.
 */
@interface ATProtoLexiconBooleanConstraints : NSObject

/*! Fixed constant value. */
@property (nonatomic, strong, nullable) NSNumber *constValue;

/*! Default value if not provided. */
@property (nonatomic, strong, nullable) NSNumber *defaultValue;

@end

/*!
 @class ATProtoLexiconBytesConstraints

 @abstract Constraints for bytes type validation.
 */
@interface ATProtoLexiconBytesConstraints : NSObject

/*! Minimum length in bytes. */
@property (nonatomic, strong, nullable) NSNumber *minLength;

/*! Maximum length in bytes. */
@property (nonatomic, strong, nullable) NSNumber *maxLength;

@end

/*!
 @class ATProtoLexiconArrayConstraints

 @abstract Constraints for array type validation.
 */
@interface ATProtoLexiconArrayConstraints : NSObject

/*! Schema definition for array items. */
@property (nonatomic, strong, nullable) ATProtoLexiconDef *items;

/*! Minimum number of elements. */
@property (nonatomic, strong, nullable) NSNumber *minLength;

/*! Maximum number of elements. */
@property (nonatomic, strong, nullable) NSNumber *maxLength;

@end

/*!
 @class ATProtoLexiconObjectConstraints

 @abstract Constraints for object type validation.
 */
@interface ATProtoLexiconObjectConstraints : NSObject

/*! Map of property names to schema definitions. */
@property (nonatomic, strong, nullable) NSDictionary<NSString *, ATProtoLexiconDef *> *properties;

/*! Array of required property names. */
@property (nonatomic, strong, nullable) NSArray<NSString *> *required;

/*! Array of property names that can be null. */
@property (nonatomic, strong, nullable) NSArray<NSString *> *nullable;

@end

/*!
 @class ATProtoLexiconBlobConstraints

 @abstract Constraints for blob type validation.
 */
@interface ATProtoLexiconBlobConstraints : NSObject

/*! Whitelist of accepted MIME types (supports glob patterns like image/asterisk). */
@property (nonatomic, strong, nullable) NSArray<NSString *> *accept;

/*! Maximum blob size in bytes. */
@property (nonatomic, strong, nullable) NSNumber *maxSize;

@end

/*!
 @class ATProtoLexiconUnionConstraints

 @abstract Constraints for union type validation.
 */
@interface ATProtoLexiconUnionConstraints : NSObject

/*! References to valid union variant definitions. */
@property (nonatomic, strong, nullable) NSArray<NSString *> *refs;

/*! Whether union is closed (true) or open to unknown types (false). */
@property (nonatomic, assign) BOOL closed;

@end

/*!
 @class ATProtoLexiconRefConstraints

 @abstract Constraints for reference type.
 */
@interface ATProtoLexiconRefConstraints : NSObject

/*! Reference to another definition (NSID or local #name). */
@property (nonatomic, copy, nullable) NSString *ref;

@end

NS_ASSUME_NONNULL_END
