// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoLexiconDef.h

 @abstract Type definitions for lexicon schemas.

 @discussion Defines the various type definitions supported by ATProto lexicons,
 including records, queries, procedures, primitives, containers, and references.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @enum ATProtoLexiconDefType

 @abstract Types of lexicon definitions.

 @constant ATProtoLexiconDefTypeRecord Record definition (stored in repository).
 @constant ATProtoLexiconDefTypeQuery Query method (HTTP GET).
 @constant ATProtoLexiconDefTypeProcedure Procedure method (HTTP POST).
 @constant ATProtoLexiconDefTypeSubscription WebSocket subscription.
 @constant ATProtoLexiconDefTypeObject Object with typed properties.
 @constant ATProtoLexiconDefTypeArray Array of items.
 @constant ATProtoLexiconDefTypeString String value.
 @constant ATProtoLexiconDefTypeInteger Integer value.
 @constant ATProtoLexiconDefTypeBoolean Boolean value.
 @constant ATProtoLexiconDefTypeBytes Byte array.
 @constant ATProtoLexiconDefTypeBlob Blob reference.
 @constant ATProtoLexiconDefTypeUnion Discriminated union.
 @constant ATProtoLexiconDefTypeRef Reference to another definition.
 @constant ATProtoLexiconDefTypeToken Empty token (for enum references).
 @constant ATProtoLexiconDefTypeUnknown Unknown/unvalidated data.
 @constant ATProtoLexiconDefTypeParams HTTP query parameters.
 */
typedef NS_ENUM(NSInteger, ATProtoLexiconDefType) {
    ATProtoLexiconDefTypeRecord,
    ATProtoLexiconDefTypeQuery,
    ATProtoLexiconDefTypeProcedure,
    ATProtoLexiconDefTypeSubscription,
    ATProtoLexiconDefTypeObject,
    ATProtoLexiconDefTypeArray,
    ATProtoLexiconDefTypeString,
    ATProtoLexiconDefTypeInteger,
    ATProtoLexiconDefTypeBoolean,
    ATProtoLexiconDefTypeBytes,
    ATProtoLexiconDefTypeBlob,
    ATProtoLexiconDefTypeUnion,
    ATProtoLexiconDefTypeRef,
    ATProtoLexiconDefTypeToken,
    ATProtoLexiconDefTypeCIDLink,
    ATProtoLexiconDefTypePermissionSet,
    ATProtoLexiconDefTypeUnknown,
    ATProtoLexiconDefTypeParams,
};

/*!
 @class ATProtoLexiconDef

 @abstract Lexicon type definition.

 @discussion Represents a single type definition within a lexicon schema.
 The constraints property holds a type-specific constraints object.
 */
@interface ATProtoLexiconDef : NSObject

/*! Type of this definition. */
@property (nonatomic, assign) ATProtoLexiconDefType type;

/*! Human-readable description. */
@property (nonatomic, copy, nullable) NSString *lexiconDescription;

/*! Type-specific constraints (e.g., ATProtoLexiconStringConstraints for string type). */
@property (nonatomic, strong, nullable) id constraints;

/*!
 @method defFromJSONObject:error:

 @abstract Creates a definition from JSON dictionary.

 @param json JSON dictionary representing the definition.
 @param error Output parameter for parsing errors.

 @return ATProtoLexiconDef instance or nil on error.
 */
+ (nullable instancetype)defFromJSONObject:(NSDictionary *)json error:(NSError **)error;

/*!
 @method typeFromString:

 @abstract Converts type string to enum value.

 @param typeString Type name (e.g., "string", "integer", "object").

 @return ATProtoLexiconDefType enum value, or -1 if unknown.
 */
+ (ATProtoLexiconDefType)typeFromString:(NSString *)typeString;

/*!
 @method stringFromType:

 @abstract Converts type enum to string.

 @param type Type enum value.

 @return Type name string (e.g., "string", "integer").
 */
+ (NSString *)stringFromType:(ATProtoLexiconDefType)type;

@end

NS_ASSUME_NONNULL_END
