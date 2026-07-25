// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UITemplateEngine.h"
#import "Debug/GZLogger.h"

@implementation UITemplateEngine

static NSString *EscapeHTML(NSString *str) {
    if (!str) return @"";
    NSMutableString *s = [NSMutableString stringWithString:str];
    [s replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"'" withString:@"&#39;" options:0 range:NSMakeRange(0, s.length)];
    return s;
}

+ (NSString *)renderTemplate:(NSString *)templateName context:(NSDictionary<NSString *, id> *)context {
    NSString *bundlePath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"AdminUIAssets"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
        // Fallback for unit tests running from repository root
        bundlePath = @"Garazyk/Sources/AdminUIServer/Assets";
    }
    NSString *filePath = [bundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"html/%@.html", templateName]];
    
    NSError *error = nil;
    NSString *templateString = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&error];
    
    if (!templateString) {
        GZ_LOG_ERROR(@"Failed to load template %@: %@", templateName, error);
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">Failed to load template: %@</div>", templateName];
    }
    
    NSMutableString *result = [templateString mutableCopy];
    
    // Process sections: {{#key}}...{{/key}} and {{^key}}...{{/key}}
    NSRegularExpression *sectionRegex = [NSRegularExpression regularExpressionWithPattern:@"\\{\\{([#\\^])([a-zA-Z0-9_]+)\\}\\}(.*?)\\{\\{/\\2\\}\\}" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    
    BOOL matched;
    do {
        matched = NO;
        NSTextCheckingResult *match = [sectionRegex firstMatchInString:result options:0 range:NSMakeRange(0, result.length)];
        if (match) {
            matched = YES;
            NSString *type = [result substringWithRange:[match rangeAtIndex:1]];
            NSString *key = [result substringWithRange:[match rangeAtIndex:2]];
            NSString *content = [result substringWithRange:[match rangeAtIndex:3]];
            
            id value = context[key];
            BOOL isTruthy = NO;
            NSArray *arrayValue = nil;
            
            if (value) {
                if ([value isKindOfClass:[NSArray class]]) {
                    arrayValue = value;
                    isTruthy = (arrayValue.count > 0);
                } else if ([value isKindOfClass:[NSNumber class]]) {
                    isTruthy = [value boolValue];
                } else if ([value isKindOfClass:[NSString class]]) {
                    isTruthy = ([value length] > 0);
                } else {
                    isTruthy = YES;
                }
            }
            
            NSMutableString *replacement = [NSMutableString string];
            if ([type isEqualToString:@"#"]) {
                if (isTruthy) {
                    if (arrayValue) {
                        for (NSDictionary *item in arrayValue) {
                            NSMutableString *itemContent = [content mutableCopy];
                            for (NSString *itemKey in item) {
                                NSString *itemValue = [NSString stringWithFormat:@"%@", item[itemKey] ?: @""];
                                NSString *escapedValue = EscapeHTML(itemValue);
                                
                                NSString *unescapedPlaceholder = [NSString stringWithFormat:@"{{{%@}}}", itemKey];
                                [itemContent replaceOccurrencesOfString:unescapedPlaceholder withString:itemValue options:0 range:NSMakeRange(0, itemContent.length)];
                                
                                NSString *escapedPlaceholder = [NSString stringWithFormat:@"{{%@}}", itemKey];
                                [itemContent replaceOccurrencesOfString:escapedPlaceholder withString:escapedValue options:0 range:NSMakeRange(0, itemContent.length)];
                            }
                            [replacement appendString:itemContent];
                        }
                    } else {
                        [replacement appendString:content];
                    }
                }
            } else if ([type isEqualToString:@"^"]) {
                if (!isTruthy) {
                    [replacement appendString:content];
                }
            }
            
            [result replaceCharactersInRange:match.range withString:replacement];
        }
    } while (matched);

    for (NSString *key in context) {
        if ([context[key] isKindOfClass:[NSString class]] || [context[key] isKindOfClass:[NSNumber class]]) {
            NSString *value = [NSString stringWithFormat:@"%@", context[key] ?: @""];
            NSString *escapedValue = EscapeHTML(value);
            
            NSString *unescapedPlaceholder = [NSString stringWithFormat:@"{{{%@}}}", key];
            [result replaceOccurrencesOfString:unescapedPlaceholder
                                    withString:value
                                       options:0
                                         range:NSMakeRange(0, result.length)];
            
            NSString *escapedPlaceholder = [NSString stringWithFormat:@"{{%@}}", key];
            [result replaceOccurrencesOfString:escapedPlaceholder
                                    withString:escapedValue
                                       options:0
                                         range:NSMakeRange(0, result.length)];
        }
    }
    
    return [result copy];
}

@end
