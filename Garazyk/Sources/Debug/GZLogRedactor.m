// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Debug/GZLogRedactor.h"

@implementation GZLogRedactor

+ (NSArray<NSRegularExpression *> *)redactionPatterns {
    static NSArray<NSRegularExpression *> *patterns = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *patternStrings = @[
            @"(?i)(authorization\\s*[:=]\\s*bearer\\s+)[^\\s,;\\]\\)]+",
            @"(?i)(cookie\\s*[:=]\\s*)[^\\n\\r]+",
            @"(?i)(set-cookie\\s*[:=]\\s*)[^\\n\\r]+",
            @"(?i)(ui_admin_token=)[^;\\s]+",
            @"(?i)(access_token|refresh_token|client_secret|client_assertion|code|password|session(?:_id)?|private_key|token)\\s*=\\s*[^&\\s,;\\]\\)]+",
            @"(?i)(\\\"(?:access_token|refresh_token|client_secret|client_assertion|code|password|session(?:_id)?|private_key|token)\\\"\\s*:\\s*\\\")[^\\\"]+",
            @"(?i)((?:access_token|refresh_token|client_secret|client_assertion|code|password|session(?:_id)?|private_key|token)\\s*[:=]\\s*)[^\\s,;\\]\\)]+"
        ];
        NSMutableArray *compiled = [NSMutableArray arrayWithCapacity:patternStrings.count];
        for (NSString *pattern in patternStrings) {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                                    options:NSRegularExpressionCaseInsensitive
                                                                                      error:nil];
            if (regex) {
                [compiled addObject:regex];
            }
        }
        patterns = [compiled copy];
    });
    return patterns;
}

+ (NSString *)redactString:(NSString *)message {
    if (![message isKindOfClass:[NSString class]] || message.length == 0) {
        return @"";
    }

    NSMutableString *redacted = [message mutableCopy];
    for (NSRegularExpression *regex in [self redactionPatterns]) {
        NSRange fullRange = NSMakeRange(0, redacted.length);
        NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:redacted
                                                                  options:0
                                                                    range:fullRange];
        for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
            if (match.numberOfRanges < 2) {
                continue;
            }
            NSRange prefixRange = [match rangeAtIndex:1];
            if (prefixRange.location == NSNotFound) {
                continue;
            }
            NSUInteger sensitiveStart = NSMaxRange(prefixRange);
            if (sensitiveStart > NSMaxRange(match.range)) {
                continue;
            }
            NSRange sensitiveRange = NSMakeRange(sensitiveStart, NSMaxRange(match.range) - sensitiveStart);
            [redacted replaceCharactersInRange:sensitiveRange withString:@"<redacted>"];
        }
    }
    return redacted;
}

+ (NSString *)redactURLString:(NSString *)urlString {
    if (![urlString isKindOfClass:[NSString class]] || urlString.length == 0) {
        return @"";
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    if (!components) {
        return [self redactString:urlString];
    }

    NSMutableArray<NSURLQueryItem *> *safeItems = [NSMutableArray array];
    NSSet<NSString *> *sensitiveNames = [NSSet setWithArray:@[
        @"access_token", @"refresh_token", @"client_secret", @"client_assertion",
        @"code", @"password", @"token", @"session", @"ui_admin_token"
    ]];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        NSString *name = item.name.lowercaseString ?: @"";
        NSString *value = [sensitiveNames containsObject:name] ? @"<redacted>" : item.value;
        [safeItems addObject:[NSURLQueryItem queryItemWithName:item.name value:value]];
    }
    components.queryItems = safeItems.count > 0 ? safeItems : components.queryItems;
    return [self redactString:components.string ?: urlString];
}

+ (NSString *)maskToken:(NSString *)token {
    if (![token isKindOfClass:[NSString class]] || token.length == 0) {
        return @"<empty>";
    }
    
    if (token.length <= 12) {
        return @"<redacted>";
    }
    
    NSString *prefix = [token substringToIndex:4];
    NSString *suffix = [token substringFromIndex:token.length - 4];
    return [NSString stringWithFormat:@"%@...%@", prefix, suffix];
}

@end
