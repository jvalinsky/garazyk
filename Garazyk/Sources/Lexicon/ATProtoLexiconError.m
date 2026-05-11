// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "ATProtoLexiconError.h"

NSString * const ATProtoLexiconErrorDomain = @"com.atproto.pds.lexicon";

@implementation ATProtoLexiconError

+ (NSError *)errorWithCode:(ATProtoLexiconErrorCode)code
                   message:(NSString *)message
                   context:(nullable NSString *)context {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:message
                                                                        forKey:NSLocalizedDescriptionKey];
    if (context) {
        userInfo[@"context"] = context;

        // Include context in description for better debugging
        NSString *fullMessage = [NSString stringWithFormat:@"%@ (at %@)", message, context];
        userInfo[NSLocalizedDescriptionKey] = fullMessage;
    }

    return [NSError errorWithDomain:ATProtoLexiconErrorDomain
                               code:code
                           userInfo:userInfo];
}

+ (NSError *)constraintError:(NSString *)constraint
                       field:(NSString *)field
                       value:(id)value
                    expected:(NSString *)expected {
    NSString *valueStr = [self stringFromValue:value];
    NSString *message = [NSString stringWithFormat:
                        @"Constraint '%@' violated in field '%@': expected %@, got %@",
                        constraint, field, expected, valueStr];

    NSMutableDictionary *userInfo = @{
        NSLocalizedDescriptionKey: message,
        @"constraint": constraint,
        @"field": field,
        @"expected": expected
    }.mutableCopy;

    if (value) {
        userInfo[@"actualValue"] = value;
    }

    return [NSError errorWithDomain:ATProtoLexiconErrorDomain
                               code:ATProtoLexiconErrorConstraintViolation
                           userInfo:userInfo];
}

+ (NSError *)missingRequiredFieldError:(NSString *)field
                               context:(nullable NSString *)context {
    NSString *message = [NSString stringWithFormat:@"Missing required field '%@'", field];
    return [self errorWithCode:ATProtoLexiconErrorMissingRequiredField
                       message:message
                       context:context];
}

+ (NSError *)typeMismatchError:(NSString *)field
                      expected:(NSString *)expected
                        actual:(NSString *)actual
                       context:(nullable NSString *)context {
    NSString *message = [NSString stringWithFormat:
                        @"Type mismatch in field '%@': expected %@, got %@",
                        field, expected, actual];

    NSMutableDictionary *userInfo = @{
        NSLocalizedDescriptionKey: message,
        @"field": field,
        @"expectedType": expected,
        @"actualType": actual
    }.mutableCopy;

    if (context) {
        userInfo[@"context"] = context;
        NSString *fullMessage = [NSString stringWithFormat:@"%@ (at %@)", message, context];
        userInfo[NSLocalizedDescriptionKey] = fullMessage;
    }

    return [NSError errorWithDomain:ATProtoLexiconErrorDomain
                               code:ATProtoLexiconErrorInvalidFieldValue
                           userInfo:userInfo];
}

#pragma mark - Private Helpers

+ (NSString *)stringFromValue:(id)value {
    if (!value || [value isKindOfClass:[NSNull class]]) {
        return @"null";
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *str = (NSString *)value;
        if (str.length > 50) {
            return [NSString stringWithFormat:@"\"%@...\" (%lu chars)",
                   [str substringToIndex:47], (unsigned long)str.length];
        }
        return [NSString stringWithFormat:@"\"%@\"", str];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value stringValue];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)value;
        return [NSString stringWithFormat:@"array[%lu]", (unsigned long)arr.count];
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)value;
        return [NSString stringWithFormat:@"object{%lu fields}", (unsigned long)dict.count];
    }
    return [NSString stringWithFormat:@"%@", value];
}

@end
