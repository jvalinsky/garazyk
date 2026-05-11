// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoLexiconValidator.h

 @abstract Validator for lexicon schema compliance.

 @discussion Validates records against lexicon schemas, enforcing all
 constraints including types, lengths, formats, and enums.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ATProtoLexiconRegistry;
@class ATProtoLexiconDef;

/*!
 @enum ATProtoValidationMode

 @abstract Validation mode for record operations.

 @constant ATProtoValidationModeRequired Fail if lexicon unknown or validation fails.
 @constant ATProtoValidationModeOptimistic Validate if known, allow if unknown (default).
 @constant ATProtoValidationModeOff Skip all validation.
 */
typedef NS_ENUM(NSInteger, ATProtoValidationMode) {
    ATProtoValidationModeRequired,
    ATProtoValidationModeOptimistic,
    ATProtoValidationModeOff
};

/*!
 @class ATProtoLexiconValidator

 @abstract Validates records against lexicon schemas.

 @discussion Provides validation for all ATProto data types
 and constraints. Stateless for thread safety.
 */
@interface ATProtoLexiconValidator : NSObject

/*!
 @method initWithRegistry:

 @abstract Initializes validator with lexicon registry.

 @param registry Registry containing loaded lexicon schemas.

 @return Initialized validator instance.
 */
- (instancetype)initWithRegistry:(ATProtoLexiconRegistry *)registry;

/*!
 @method validateRecord:collection:mode:error:

 @abstract Validates a record against its lexicon schema.

 @param record Record data dictionary (must contain $type field).
 @param collection Collection NSID (must match record $type).
 @param mode Validation mode (required, optimistic, or off).
 @param error Output parameter for validation errors.

 @return YES if validation passes, NO otherwise.

 @discussion In optimistic mode, returns YES if lexicon is unknown.
 In required mode, returns NO if lexicon is unknown.
 In off mode, always returns YES without validation.
 */
- (BOOL)validateRecord:(NSDictionary *)record
            collection:(NSString *)collection
                  mode:(ATProtoValidationMode)mode
                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
