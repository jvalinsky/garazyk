// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoLexiconError.h

 @abstract Error handling for lexicon validation.

 @discussion Provides error codes and descriptive error messages for lexicon
 schema parsing and validation failures.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @constant ATProtoLexiconErrorDomain

 @abstract Error domain for lexicon validation errors.
 */
extern NSString * const ATProtoLexiconErrorDomain;

/*!
 @enum ATProtoLexiconErrorCode

 @abstract Error codes for lexicon validation failures.

 @constant ATProtoLexiconErrorInvalidSchema Schema JSON is malformed or invalid.
 @constant ATProtoLexiconErrorSchemaNotFound Lexicon schema not found for NSID.
 @constant ATProtoLexiconErrorMissingTypeField Record missing required $type field.
 @constant ATProtoLexiconErrorTypeMismatch $type does not match collection NSID.
 @constant ATProtoLexiconErrorMissingRequiredField Required field is missing.
 @constant ATProtoLexiconErrorInvalidFieldValue Field value has wrong type.
 @constant ATProtoLexiconErrorConstraintViolation Field violates constraint (length, range, enum, etc.).
 @constant ATProtoLexiconErrorUnionValidationFailed Union value doesn't match any variant.
 @constant ATProtoLexiconErrorRecursionLimitExceeded Nested object depth exceeds limit.
 @constant ATProtoLexiconErrorCircularReference Circular reference detected in schema.
 */
typedef NS_ENUM(NSInteger, ATProtoLexiconErrorCode) {
    ATProtoLexiconErrorInvalidSchema = 1000,
    ATProtoLexiconErrorSchemaNotFound,
    ATProtoLexiconErrorMissingTypeField,
    ATProtoLexiconErrorTypeMismatch,
    ATProtoLexiconErrorMissingRequiredField,
    ATProtoLexiconErrorInvalidFieldValue,
    ATProtoLexiconErrorConstraintViolation,
    ATProtoLexiconErrorUnionValidationFailed,
    ATProtoLexiconErrorRecursionLimitExceeded,
    ATProtoLexiconErrorCircularReference,
};

/*!
 @class ATProtoLexiconError

 @abstract Factory for creating descriptive lexicon validation errors.
 */
@interface ATProtoLexiconError : NSObject

/*!
 @method errorWithCode:message:context:

 @abstract Creates an error with the specified code and message.

 @param code Error code from ATProtoLexiconErrorCode enum.
 @param message Human-readable error message.
 @param context Optional context path (e.g., "record.text", "record.reply.parent.cid").

 @return NSError instance with ATProtoLexiconErrorDomain.
 */
+ (NSError *)errorWithCode:(ATProtoLexiconErrorCode)code
                   message:(NSString *)message
                   context:(nullable NSString *)context;

/*!
 @method constraintError:field:value:expected:

 @abstract Creates a constraint violation error with details.

 @param constraint Name of the constraint violated (e.g., "maxGraphemes", "minimum", "enum").
 @param field Field path where violation occurred.
 @param value Actual value that violated the constraint.
 @param expected Expected constraint (e.g., "3000", "0-100", "post,reply,repost").

 @return NSError instance with ATProtoLexiconErrorCode.constraintViolation.
 */
+ (NSError *)constraintError:(NSString *)constraint
                       field:(NSString *)field
                       value:(id)value
                    expected:(NSString *)expected;

/*!
 @method missingRequiredFieldError:context:

 @abstract Creates an error for a missing required field.

 @param field Name of the required field.
 @param context Context path where field is missing.

 @return NSError instance.
 */
+ (NSError *)missingRequiredFieldError:(NSString *)field
                               context:(nullable NSString *)context;

/*!
 @method typeMismatchError:expected:actual:context:

 @abstract Creates an error for type mismatch.

 @param field Field name.
 @param expected Expected type (e.g., "string", "integer", "array").
 @param actual Actual type found.
 @param context Context path.

 @return NSError instance.
 */
+ (NSError *)typeMismatchError:(NSString *)field
                      expected:(NSString *)expected
                        actual:(NSString *)actual
                       context:(nullable NSString *)context;

@end

NS_ASSUME_NONNULL_END
