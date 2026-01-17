#import "ATProtoLexiconValidator.h"
#import "ATProtoLexiconRegistry.h"
#import "ATProtoLexiconSchema.h"
#import "ATProtoLexiconDef.h"
#import "ATProtoLexiconConstraints.h"
#import "ATProtoLexiconError.h"
#import "Core/ATProtoValidator.h"
#import "Debug/PDSLogger.h"

// Maximum recursion depth for nested objects
static const NSInteger kMaxRecursionDepth = 32;

@interface ATProtoLexiconValidator ()

@property (nonatomic, strong) ATProtoLexiconRegistry *registry;

@end

@implementation ATProtoLexiconValidator

- (instancetype)initWithRegistry:(ATProtoLexiconRegistry *)registry {
    self = [super init];
    if (self) {
        _registry = registry;
    }
    return self;
}

#pragma mark - Public API

- (BOOL)validateRecord:(NSDictionary *)record
            collection:(NSString *)collection
                  mode:(ATProtoValidationMode)mode
                 error:(NSError **)error {
    // Skip validation if mode is off
    if (mode == ATProtoValidationModeOff) {
        return YES;
    }

    // Check if record is a dictionary
    if (![record isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidFieldValue
                                                message:@"Record must be a JSON object"
                                                context:nil];
        }
        return NO;
    }

    // Check for $type field
    NSString *recordType = record[@"$type"];
    if (!recordType || ![recordType isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorMissingTypeField
                                                message:@"Record missing required $type field"
                                                context:nil];
        }
        return NO;
    }

    // Verify $type matches collection
    if (![recordType isEqualToString:collection]) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorTypeMismatch
                                                message:[NSString stringWithFormat:@"Record $type '%@' does not match collection '%@'",
                                                        recordType, collection]
                                                context:nil];
        }
        return NO;
    }

    // Lookup schema
    ATProtoLexiconSchema *schema = [self.registry schemaForNSID:collection];

    if (!schema) {
        if (mode == ATProtoValidationModeRequired) {
            if (error) {
                *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorSchemaNotFound
                                                    message:[NSString stringWithFormat:@"Lexicon schema not found for '%@'", collection]
                                                    context:nil];
            }
            return NO;
        } else {
            // Optimistic mode: allow unknown lexicons
            PDS_LOG_DEBUG(@"[LexiconValidator] Lexicon unknown for '%@', allowing in optimistic mode", collection);
            return YES;
        }
    }

    // Get main definition
    ATProtoLexiconDef *mainDef = [schema mainDefinition];
    if (!mainDef) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                message:[NSString stringWithFormat:@"Lexicon '%@' missing main definition", collection]
                                                context:nil];
        }
        return NO;
    }

    // Validate record against main definition
    return [self validateValue:record
                    againstDef:mainDef
                       context:@"record"
                 recursionDepth:0
                        schema:schema
                         error:error];
}

#pragma mark - Type Validation

- (BOOL)validateValue:(id)value
           againstDef:(ATProtoLexiconDef *)def
              context:(NSString *)context
        recursionDepth:(NSInteger)depth
               schema:(ATProtoLexiconSchema *)schema
                error:(NSError **)error {
    // Check recursion depth
    if (depth > kMaxRecursionDepth) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorRecursionLimitExceeded
                                                message:[NSString stringWithFormat:@"Maximum nesting depth (%ld) exceeded", (long)kMaxRecursionDepth]
                                                context:context];
        }
        return NO;
    }

    // Dispatch to type-specific validator
    switch (def.type) {
        case ATProtoLexiconDefTypeString:
            return [self validateString:value constraints:def.constraints context:context error:error];

        case ATProtoLexiconDefTypeInteger:
            return [self validateInteger:value constraints:def.constraints context:context error:error];

        case ATProtoLexiconDefTypeBoolean:
            return [self validateBoolean:value constraints:def.constraints context:context error:error];

        case ATProtoLexiconDefTypeBytes:
            return [self validateBytes:value constraints:def.constraints context:context error:error];

        case ATProtoLexiconDefTypeArray:
            return [self validateArray:value
                           constraints:def.constraints
                               context:context
                         recursionDepth:depth
                                schema:schema
                                 error:error];

        case ATProtoLexiconDefTypeObject:
        case ATProtoLexiconDefTypeRecord:
            return [self validateObject:value
                            constraints:def.constraints
                                context:context
                          recursionDepth:depth
                                 schema:schema
                                  error:error];

        case ATProtoLexiconDefTypeBlob:
            return [self validateBlob:value constraints:def.constraints context:context error:error];

        case ATProtoLexiconDefTypeUnion:
            return [self validateUnion:value
                           constraints:def.constraints
                               context:context
                         recursionDepth:depth
                                schema:schema
                                 error:error];

        case ATProtoLexiconDefTypeRef:
            return [self validateRef:value
                         constraints:def.constraints
                             context:context
                       recursionDepth:depth
                              schema:schema
                               error:error];

        case ATProtoLexiconDefTypeUnknown:
            // Unknown type allows any object
            if (![value isKindOfClass:[NSDictionary class]]) {
                if (error) {
                    *error = [ATProtoLexiconError typeMismatchError:@"value"
                                                            expected:@"object"
                                                              actual:[self typeNameForValue:value]
                                                             context:context];
                }
                return NO;
            }
            return YES;

        case ATProtoLexiconDefTypeToken:
            // Tokens have no runtime representation
            return YES;

        default:
            if (error) {
                *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                    message:[NSString stringWithFormat:@"Unsupported type: %@",
                                                            [ATProtoLexiconDef stringFromType:def.type]]
                                                    context:context];
            }
            return NO;
    }
}

#pragma mark - String Validation

- (BOOL)validateString:(id)value
           constraints:(ATProtoLexiconStringConstraints *)constraints
               context:(NSString *)context
                 error:(NSError **)error {
    if (![value isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [ATProtoLexiconError typeMismatchError:@"value"
                                                    expected:@"string"
                                                      actual:[self typeNameForValue:value]
                                                     context:context];
        }
        return NO;
    }

    NSString *str = (NSString *)value;

    // Const check
    if (constraints.constValue && ![str isEqualToString:constraints.constValue]) {
        if (error) {
            *error = [ATProtoLexiconError constraintError:@"const"
                                                    field:context
                                                    value:str
                                                 expected:constraints.constValue];
        }
        return NO;
    }

    // Enum check
    if (constraints.enumValues && constraints.enumValues.count > 0) {
        if (![constraints.enumValues containsObject:str]) {
            NSString *enumList = [constraints.enumValues componentsJoinedByString:@", "];
            if (error) {
                *error = [ATProtoLexiconError constraintError:@"enum"
                                                        field:context
                                                        value:str
                                                     expected:enumList];
            }
            return NO;
        }
    }

    // Length checks (UTF-8 bytes)
    if (constraints.maxLength || constraints.minLength) {
        NSUInteger byteLength = [str lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

        if (constraints.maxLength && byteLength > [constraints.maxLength unsignedIntegerValue]) {
            if (error) {
                *error = [ATProtoLexiconError constraintError:@"maxLength"
                                                        field:context
                                                        value:@(byteLength)
                                                     expected:[NSString stringWithFormat:@"%@", constraints.maxLength]];
            }
            return NO;
        }

        if (constraints.minLength && byteLength < [constraints.minLength unsignedIntegerValue]) {
            if (error) {
                *error = [ATProtoLexiconError constraintError:@"minLength"
                                                        field:context
                                                        value:@(byteLength)
                                                     expected:[NSString stringWithFormat:@"%@", constraints.minLength]];
            }
            return NO;
        }
    }

    // Grapheme checks
    if (constraints.maxGraphemes || constraints.minGraphemes) {
        __block NSUInteger graphemeCount = 0;
        [str enumerateSubstringsInRange:NSMakeRange(0, str.length)
                                options:NSStringEnumerationByComposedCharacterSequences
                             usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
            graphemeCount++;
        }];

        if (constraints.maxGraphemes && graphemeCount > [constraints.maxGraphemes unsignedIntegerValue]) {
            if (error) {
                *error = [ATProtoLexiconError constraintError:@"maxGraphemes"
                                                        field:context
                                                        value:@(graphemeCount)
                                                     expected:[NSString stringWithFormat:@"%@", constraints.maxGraphemes]];
            }
            return NO;
        }

        if (constraints.minGraphemes && graphemeCount < [constraints.minGraphemes unsignedIntegerValue]) {
            if (error) {
                *error = [ATProtoLexiconError constraintError:@"minGraphemes"
                                                        field:context
                                                        value:@(graphemeCount)
                                                     expected:[NSString stringWithFormat:@"%@", constraints.minGraphemes]];
            }
            return NO;
        }
    }

    // Format validation
    if (constraints.format) {
        if (![self validateStringFormat:str format:constraints.format context:context error:error]) {
            return NO;
        }
    }

    return YES;
}

- (BOOL)validateStringFormat:(NSString *)str
                      format:(NSString *)format
                     context:(NSString *)context
                       error:(NSError **)error {
    NSError *formatError = nil;

    if ([format isEqualToString:@"did"]) {
        if (![ATProtoValidator validateDID:str error:&formatError]) {
            if (error) {
                *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorConstraintViolation
                                                    message:[NSString stringWithFormat:@"Invalid DID format in '%@': %@",
                                                            context, formatError.localizedDescription]
                                                    context:context];
            }
            return NO;
        }
    } else if ([format isEqualToString:@"handle"]) {
        if (![ATProtoValidator validateHandle:str error:&formatError]) {
            if (error) {
                *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorConstraintViolation
                                                    message:[NSString stringWithFormat:@"Invalid handle format in '%@': %@",
                                                            context, formatError.localizedDescription]
                                                    context:context];
            }
            return NO;
        }
    } else if ([format isEqualToString:@"at-identifier"]) {
        // Accept either DID or handle
        BOOL validDID = [ATProtoValidator validateDID:str error:nil];
        BOOL validHandle = [ATProtoValidator validateHandle:str error:nil];
        if (!validDID && !validHandle) {
            if (error) {
                *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorConstraintViolation
                                                    message:[NSString stringWithFormat:@"Invalid AT identifier in '%@': must be DID or handle", context]
                                                    context:context];
            }
            return NO;
        }
    } else if ([format isEqualToString:@"nsid"]) {
        if (![ATProtoValidator validateNSID:str error:&formatError]) {
            if (error) {
                *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorConstraintViolation
                                                    message:[NSString stringWithFormat:@"Invalid NSID format in '%@': %@",
                                                            context, formatError.localizedDescription]
                                                    context:context];
            }
            return NO;
        }
    } else if ([format isEqualToString:@"cid"]) {
        if (![ATProtoValidator validateCID:str error:&formatError]) {
            if (error) {
                *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorConstraintViolation
                                                    message:[NSString stringWithFormat:@"Invalid CID format in '%@': %@",
                                                            context, formatError.localizedDescription]
                                                    context:context];
            }
            return NO;
        }
    } else if ([format isEqualToString:@"tid"]) {
        if (![ATProtoValidator validateTID:str error:&formatError]) {
            if (error) {
                *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorConstraintViolation
                                                    message:[NSString stringWithFormat:@"Invalid TID format in '%@': %@",
                                                            context, formatError.localizedDescription]
                                                    context:context];
            }
            return NO;
        }
    } else if ([format isEqualToString:@"datetime"]) {
        // ISO 8601 datetime format (simplified check)
        if (![self validateDatetimeFormat:str]) {
            if (error) {
                *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorConstraintViolation
                                                    message:[NSString stringWithFormat:@"Invalid datetime format in '%@': must be ISO 8601", context]
                                                    context:context];
            }
            return NO;
        }
    } else if ([format isEqualToString:@"uri"]) {
        // Basic URI validation
        NSURL *url = [NSURL URLWithString:str];
        if (!url || !url.scheme) {
            if (error) {
                *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorConstraintViolation
                                                    message:[NSString stringWithFormat:@"Invalid URI format in '%@'", context]
                                                    context:context];
            }
            return NO;
        }
    } else if ([format isEqualToString:@"at-uri"]) {
        // AT-URI validation (simplified)
        if (![str hasPrefix:@"at://"]) {
            if (error) {
                *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorConstraintViolation
                                                    message:[NSString stringWithFormat:@"Invalid AT-URI format in '%@': must start with 'at://'", context]
                                                    context:context];
            }
            return NO;
        }
    }
    // Other formats (record-key, language) not strictly validated for now

    return YES;
}

- (BOOL)validateDatetimeFormat:(NSString *)str {
    // Simplified ISO 8601 check: YYYY-MM-DDTHH:MM:SS(.mmm)(Z|+HH:MM|-HH:MM)
    // Full validation would use NSDateFormatter
    if (str.length < 19) return NO; // Minimum: "2024-01-01T00:00:00"
    if ([str rangeOfString:@"T"].location == NSNotFound) return NO;

    // Try parsing with ISO8601DateFormatter
    if (@available(macOS 10.12, iOS 10.0, *)) {
        NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
        NSDate *date = [formatter dateFromString:str];
        return date != nil;
    }

    return YES; // Fallback: allow if iOS < 10
}

#pragma mark - Integer Validation

- (BOOL)validateInteger:(id)value
            constraints:(ATProtoLexiconIntegerConstraints *)constraints
                context:(NSString *)context
                  error:(NSError **)error {
    if (![value isKindOfClass:[NSNumber class]]) {
        if (error) {
            *error = [ATProtoLexiconError typeMismatchError:@"value"
                                                    expected:@"integer"
                                                      actual:[self typeNameForValue:value]
                                                     context:context];
        }
        return NO;
    }

    NSNumber *num = (NSNumber *)value;

    // Const check
    if (constraints.constValue && ![num isEqualToNumber:constraints.constValue]) {
        if (error) {
            *error = [ATProtoLexiconError constraintError:@"const"
                                                    field:context
                                                    value:num
                                                 expected:[constraints.constValue stringValue]];
        }
        return NO;
    }

    // Enum check
    if (constraints.enumValues && constraints.enumValues.count > 0) {
        if (![constraints.enumValues containsObject:num]) {
            NSArray *enumStrs = [constraints.enumValues valueForKey:@"stringValue"];
            NSString *enumList = [enumStrs componentsJoinedByString:@", "];
            if (error) {
                *error = [ATProtoLexiconError constraintError:@"enum"
                                                        field:context
                                                        value:num
                                                     expected:enumList];
            }
            return NO;
        }
    }

    // Range checks
    if (constraints.minimum && [num compare:constraints.minimum] == NSOrderedAscending) {
        if (error) {
            *error = [ATProtoLexiconError constraintError:@"minimum"
                                                    field:context
                                                    value:num
                                                 expected:[NSString stringWithFormat:@">= %@", constraints.minimum]];
        }
        return NO;
    }

    if (constraints.maximum && [num compare:constraints.maximum] == NSOrderedDescending) {
        if (error) {
            *error = [ATProtoLexiconError constraintError:@"maximum"
                                                    field:context
                                                    value:num
                                                 expected:[NSString stringWithFormat:@"<= %@", constraints.maximum]];
        }
        return NO;
    }

    return YES;
}

#pragma mark - Boolean Validation

- (BOOL)validateBoolean:(id)value
            constraints:(ATProtoLexiconBooleanConstraints *)constraints
                context:(NSString *)context
                  error:(NSError **)error {
    if (![value isKindOfClass:[NSNumber class]] || strcmp([value objCType], @encode(BOOL)) != 0) {
        if (error) {
            *error = [ATProtoLexiconError typeMismatchError:@"value"
                                                    expected:@"boolean"
                                                      actual:[self typeNameForValue:value]
                                                     context:context];
        }
        return NO;
    }

    NSNumber *boolNum = (NSNumber *)value;

    // Const check
    if (constraints.constValue && ![boolNum isEqualToNumber:constraints.constValue]) {
        if (error) {
            *error = [ATProtoLexiconError constraintError:@"const"
                                                    field:context
                                                    value:boolNum
                                                 expected:[constraints.constValue boolValue] ? @"true" : @"false"];
        }
        return NO;
    }

    return YES;
}

#pragma mark - Bytes Validation

- (BOOL)validateBytes:(id)value
          constraints:(ATProtoLexiconBytesConstraints *)constraints
              context:(NSString *)context
                error:(NSError **)error {
    // Bytes in JSON are represented as {"$bytes": "<base64>"}
    if (![value isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [ATProtoLexiconError typeMismatchError:@"value"
                                                    expected:@"bytes object"
                                                      actual:[self typeNameForValue:value]
                                                     context:context];
        }
        return NO;
    }

    NSDictionary *dict = (NSDictionary *)value;
    NSString *base64 = dict[@"$bytes"];

    if (!base64 || ![base64 isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidFieldValue
                                                message:[NSString stringWithFormat:@"Bytes object missing $bytes field in '%@'", context]
                                                context:context];
        }
        return NO;
    }

    // Decode base64 to check length
    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    if (!data) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidFieldValue
                                                message:[NSString stringWithFormat:@"Invalid base64 encoding in '%@'", context]
                                                context:context];
        }
        return NO;
    }

    NSUInteger length = data.length;

    if (constraints.maxLength && length > [constraints.maxLength unsignedIntegerValue]) {
        if (error) {
            *error = [ATProtoLexiconError constraintError:@"maxLength"
                                                    field:context
                                                    value:@(length)
                                                 expected:[NSString stringWithFormat:@"%@", constraints.maxLength]];
        }
        return NO;
    }

    if (constraints.minLength && length < [constraints.minLength unsignedIntegerValue]) {
        if (error) {
            *error = [ATProtoLexiconError constraintError:@"minLength"
                                                    field:context
                                                    value:@(length)
                                                 expected:[NSString stringWithFormat:@"%@", constraints.minLength]];
        }
        return NO;
    }

    return YES;
}

#pragma mark - Array Validation

- (BOOL)validateArray:(id)value
          constraints:(ATProtoLexiconArrayConstraints *)constraints
              context:(NSString *)context
        recursionDepth:(NSInteger)depth
               schema:(ATProtoLexiconSchema *)schema
                error:(NSError **)error {
    if (![value isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [ATProtoLexiconError typeMismatchError:@"value"
                                                    expected:@"array"
                                                      actual:[self typeNameForValue:value]
                                                     context:context];
        }
        return NO;
    }

    NSArray *arr = (NSArray *)value;
    NSUInteger length = arr.count;

    // Length checks
    if (constraints.maxLength && length > [constraints.maxLength unsignedIntegerValue]) {
        if (error) {
            *error = [ATProtoLexiconError constraintError:@"maxLength"
                                                    field:context
                                                    value:@(length)
                                                 expected:[NSString stringWithFormat:@"%@", constraints.maxLength]];
        }
        return NO;
    }

    if (constraints.minLength && length < [constraints.minLength unsignedIntegerValue]) {
        if (error) {
            *error = [ATProtoLexiconError constraintError:@"minLength"
                                                    field:context
                                                    value:@(length)
                                                 expected:[NSString stringWithFormat:@"%@", constraints.minLength]];
        }
        return NO;
    }

    // Validate each item
    if (constraints.items) {
        for (NSUInteger i = 0; i < arr.count; i++) {
            id item = arr[i];
            NSString *itemContext = [NSString stringWithFormat:@"%@[%lu]", context, (unsigned long)i];

            if (![self validateValue:item
                          againstDef:constraints.items
                             context:itemContext
                       recursionDepth:depth + 1
                              schema:schema
                               error:error]) {
                return NO;
            }
        }
    }

    return YES;
}

#pragma mark - Object Validation

- (BOOL)validateObject:(id)value
           constraints:(ATProtoLexiconObjectConstraints *)constraints
               context:(NSString *)context
         recursionDepth:(NSInteger)depth
                schema:(ATProtoLexiconSchema *)schema
                 error:(NSError **)error {
    if (![value isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [ATProtoLexiconError typeMismatchError:@"value"
                                                    expected:@"object"
                                                      actual:[self typeNameForValue:value]
                                                     context:context];
        }
        return NO;
    }

    NSDictionary *obj = (NSDictionary *)value;

    // Check required fields
    if (constraints.required) {
        for (NSString *requiredField in constraints.required) {
            if (!obj[requiredField]) {
                if (error) {
                    *error = [ATProtoLexiconError missingRequiredFieldError:requiredField context:context];
                }
                return NO;
            }
        }
    }

    // Validate properties
    if (constraints.properties) {
        for (NSString *propName in obj) {
            // Skip $type field (it's the discriminator)
            if ([propName isEqualToString:@"$type"]) {
                continue;
            }

            id propValue = obj[propName];
            ATProtoLexiconDef *propDef = constraints.properties[propName];

            if (!propDef) {
                // Unknown field - log warning but allow (forward compatibility)
                PDS_LOG_DEBUG(@"[LexiconValidator] Unknown field '%@' in %@", propName, context);
                continue;
            }

            // Check nullable
            if ([propValue isKindOfClass:[NSNull class]]) {
                if (constraints.nullable && [constraints.nullable containsObject:propName]) {
                    continue; // Null is allowed
                } else {
                    if (error) {
                        *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidFieldValue
                                                            message:[NSString stringWithFormat:@"Field '%@' cannot be null", propName]
                                                            context:context];
                    }
                    return NO;
                }
            }

            // Validate property
            NSString *propContext = [context isEqualToString:@"record"] ?
                                    [NSString stringWithFormat:@"record.%@", propName] :
                                    [NSString stringWithFormat:@"%@.%@", context, propName];

            if (![self validateValue:propValue
                          againstDef:propDef
                             context:propContext
                       recursionDepth:depth + 1
                              schema:schema
                               error:error]) {
                return NO;
            }
        }
    }

    return YES;
}

#pragma mark - Blob Validation

- (BOOL)validateBlob:(id)value
         constraints:(ATProtoLexiconBlobConstraints *)constraints
             context:(NSString *)context
               error:(NSError **)error {
    // Blob structure: {"$type": "blob", "ref": {...}, "mimeType": "...", "size": N}
    if (![value isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [ATProtoLexiconError typeMismatchError:@"value"
                                                    expected:@"blob object"
                                                      actual:[self typeNameForValue:value]
                                                     context:context];
        }
        return NO;
    }

    NSDictionary *blob = (NSDictionary *)value;

    // Check required fields
    if (!blob[@"$type"] || ![@"blob" isEqualToString:blob[@"$type"]]) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidFieldValue
                                                message:[NSString stringWithFormat:@"Blob missing $type field in '%@'", context]
                                                context:context];
        }
        return NO;
    }

    NSString *mimeType = blob[@"mimeType"];
    NSNumber *size = blob[@"size"];

    // MIME type check
    if (constraints.accept && constraints.accept.count > 0 && mimeType) {
        BOOL accepted = NO;
        for (NSString *pattern in constraints.accept) {
            if ([self mimeType:mimeType matchesPattern:pattern]) {
                accepted = YES;
                break;
            }
        }

        if (!accepted) {
            NSString *acceptList = [constraints.accept componentsJoinedByString:@", "];
            if (error) {
                *error = [ATProtoLexiconError constraintError:@"accept"
                                                        field:context
                                                        value:mimeType ?: @"(none)"
                                                     expected:acceptList];
            }
            return NO;
        }
    }

    // Size check
    if (constraints.maxSize && size && [size unsignedIntegerValue] > [constraints.maxSize unsignedIntegerValue]) {
        if (error) {
            *error = [ATProtoLexiconError constraintError:@"maxSize"
                                                    field:context
                                                    value:size
                                                 expected:[NSString stringWithFormat:@"%@", constraints.maxSize]];
        }
        return NO;
    }

    return YES;
}

- (BOOL)mimeType:(NSString *)mimeType matchesPattern:(NSString *)pattern {
    if ([pattern isEqualToString:@"*/*"] || [pattern isEqualToString:@"*"]) {
        return YES;
    }

    if ([pattern hasSuffix:@"/*"]) {
        NSString *prefix = [pattern substringToIndex:pattern.length - 2];
        return [mimeType hasPrefix:prefix];
    }

    return [mimeType isEqualToString:pattern];
}

#pragma mark - Union Validation

- (BOOL)validateUnion:(id)value
          constraints:(ATProtoLexiconUnionConstraints *)constraints
              context:(NSString *)context
        recursionDepth:(NSInteger)depth
               schema:(ATProtoLexiconSchema *)schema
                error:(NSError **)error {
    if (![value isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [ATProtoLexiconError typeMismatchError:@"value"
                                                    expected:@"union object"
                                                      actual:[self typeNameForValue:value]
                                                     context:context];
        }
        return NO;
    }

    NSDictionary *obj = (NSDictionary *)value;
    NSString *discriminator = obj[@"$type"];

    if (!discriminator) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorMissingTypeField
                                                message:[NSString stringWithFormat:@"Union missing $type discriminator in '%@'", context]
                                                context:context];
        }
        return NO;
    }

    // Try to validate against each variant
    if (constraints.refs) {
        for (NSString *ref in constraints.refs) {
            // Resolve ref to definition
            ATProtoLexiconDef *variantDef = [self resolveRef:ref inSchema:schema];

            if (variantDef) {
                NSError *variantError = nil;
                if ([self validateValue:value
                             againstDef:variantDef
                                context:context
                          recursionDepth:depth
                                 schema:schema
                                  error:&variantError]) {
                    return YES; // Matched one variant
                }
            }
        }
    }

    // If closed union, fail
    if (constraints.closed) {
        if (error) {
            NSString *refList = [constraints.refs componentsJoinedByString:@", "];
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorUnionValidationFailed
                                                message:[NSString stringWithFormat:@"Union value in '%@' doesn't match any variant: %@", context, refList]
                                                context:context];
        }
        return NO;
    }

    // Open union: allow unknown types
    return YES;
}

#pragma mark - Ref Validation

- (BOOL)validateRef:(id)value
        constraints:(ATProtoLexiconRefConstraints *)constraints
            context:(NSString *)context
      recursionDepth:(NSInteger)depth
             schema:(ATProtoLexiconSchema *)schema
              error:(NSError **)error {
    if (!constraints.ref) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                message:[NSString stringWithFormat:@"Ref missing 'ref' field in '%@'", context]
                                                context:context];
        }
        return NO;
    }

    // Resolve reference
    ATProtoLexiconDef *targetDef = [self resolveRef:constraints.ref inSchema:schema];

    if (!targetDef) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                message:[NSString stringWithFormat:@"Cannot resolve ref '%@' in '%@'", constraints.ref, context]
                                                context:context];
        }
        return NO;
    }

    // Validate value against target definition
    return [self validateValue:value
                    againstDef:targetDef
                       context:context
                 recursionDepth:depth + 1
                        schema:schema
                         error:error];
}

- (nullable ATProtoLexiconDef *)resolveRef:(NSString *)ref inSchema:(ATProtoLexiconSchema *)schema {
    if ([ref hasPrefix:@"#"]) {
        // Local reference
        NSString *defName = [ref substringFromIndex:1];
        return [schema definitionForName:defName];
    } else {
        // Global reference (NSID)
        NSString *nsid = ref;
        NSString *defName = @"main";
        NSRange hashRange = [ref rangeOfString:@"#"];
        if (hashRange.location != NSNotFound) {
            nsid = [ref substringToIndex:hashRange.location];
            defName = [ref substringFromIndex:hashRange.location + 1];
        }

        ATProtoLexiconSchema *targetSchema = [self.registry schemaForNSID:nsid];
        if (!targetSchema) {
            return nil;
        }

        return [targetSchema definitionForName:defName];
    }
}

#pragma mark - Helpers

- (NSString *)typeNameForValue:(id)value {
    if (!value || [value isKindOfClass:[NSNull class]]) {
        return @"null";
    } else if ([value isKindOfClass:[NSString class]]) {
        return @"string";
    } else if ([value isKindOfClass:[NSNumber class]]) {
        // Distinguish boolean from number
        if (strcmp([value objCType], @encode(BOOL)) == 0) {
            return @"boolean";
        }
        return @"number";
    } else if ([value isKindOfClass:[NSArray class]]) {
        return @"array";
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        return @"object";
    } else {
        return NSStringFromClass([value class]);
    }
}

@end
