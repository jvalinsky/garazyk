#import <Foundation/Foundation.h>
#import "AdminUITemplateRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@implementation AdminUITemplateRenderer

+ (NSString *)renderTemplate:(NSString *)template withContext:(NSDictionary *)context {
    NSMutableString *result = [NSMutableString stringWithString:template];

    for (NSString *key in context) {
        NSObject *value = context[key];
        NSString *placeholder = [NSString stringWithFormat:@"{{%@}}", key];
        NSString *replacement = [self valueToString:value];

        [result replaceOccurrencesOfString:placeholder
                                withString:replacement
                                   options:NSLiteralSearch
                                     range:NSMakeRange(0, result.length)];
    }

    return [result copy];
}

+ (NSString *)renderAdvancedTemplate:(NSString *)template withContext:(NSDictionary *)context {
    NSMutableString *result = [NSMutableString stringWithString:template];

    // Process {{#if key}}...{{/if}} blocks
    result = (NSMutableString *)[self processConditionalBlocks:result withContext:context];

    // Process {{#each array}}...{{/each}} blocks
    result = (NSMutableString *)[self processLoopBlocks:result withContext:context];

    // Process remaining {{key}} substitutions
    result = (NSMutableString *)[self renderTemplate:result withContext:context];

    return [result copy];
}

+ (NSMutableString *)processConditionalBlocks:(NSString *)template withContext:(NSDictionary *)context {
    NSMutableString *result = [NSMutableString stringWithString:template];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\{\\{#if\\s+(\\w+)\\}\\}(.+?)\\{\\{/if\\}\\}"
                                                                           options:NSRegularExpressionDotMatchesLineSeparators
                                                                             error:NULL];

    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:result
                                                               options:0
                                                                 range:NSMakeRange(0, result.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSString *key = [result substringWithRange:[match rangeAtIndex:1]];
        NSString *content = [result substringWithRange:[match rangeAtIndex:2]];
        NSString *replacement = @"";

        if (context[key] && [self isTruthy:context[key]]) {
            replacement = content;
        }

        [result replaceCharactersInRange:match.range withString:replacement];
    }

    return result;
}

+ (NSMutableString *)processLoopBlocks:(NSString *)template withContext:(NSDictionary *)context {
    NSMutableString *result = [NSMutableString stringWithString:template];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\{\\{#each\\s+(\\w+)\\}\\}(.+?)\\{\\{/each\\}\\}"
                                                                           options:NSRegularExpressionDotMatchesLineSeparators
                                                                             error:NULL];

    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:result
                                                               options:0
                                                                 range:NSMakeRange(0, result.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSString *key = [result substringWithRange:[match rangeAtIndex:1]];
        NSString *template = [result substringWithRange:[match rangeAtIndex:2]];
        NSString *replacement = @"";

        NSArray *items = context[key];
        if ([items isKindOfClass:[NSArray class]]) {
            NSMutableString *accumulated = [NSMutableString string];
            for (NSDictionary *item in items) {
                [accumulated appendString:[self renderAdvancedTemplate:template withContext:item]];
            }
            replacement = accumulated;
        }

        [result replaceCharactersInRange:match.range withString:replacement];
    }

    return result;
}

+ (BOOL)isTruthy:(NSObject *)value {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value boolValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *str = (NSString *)value;
        return str.length > 0 && ![str isEqualToString:@"0"] && ![str isEqualToString:@"false"];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        return [(NSArray *)value count] > 0;
    }
    return value != nil && value != [NSNull null];
}

+ (NSString *)valueToString:(NSObject *)value {
    if (value == nil || [value isKindOfClass:[NSNull class]]) {
        return @"";
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value stringValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [self escapeHTML:(NSString *)value];
    }
    return [self escapeHTML:[value description]];
}

+ (NSString *)escapeHTML:(NSString *)value {
    if (!value || value.length == 0) {
        return @"";
    }

    NSMutableString *escaped = [NSMutableString stringWithString:value];
    [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:NSLiteralSearch range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:NSLiteralSearch range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:NSLiteralSearch range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:NSLiteralSearch range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"'" withString:@"&#x27;" options:NSLiteralSearch range:NSMakeRange(0, escaped.length)];
    return [escaped copy];
}

@end

NS_ASSUME_NONNULL_END
