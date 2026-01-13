#import "Identity/ATProtoHandleValidator.h"

@implementation ATProtoHandleValidator

+ (BOOL)validateHandle:(NSString *)handle error:(NSError **)error {
    if (!handle || handle.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"Handle cannot be empty"}];
        return NO;
    }

    if (handle.length > 253) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1002 userInfo:@{NSLocalizedDescriptionKey: @"Handle too long (max 253 chars)"}];
        return NO;
    }

    // Check for IPv4 address pattern
    NSString *ipv4Pattern = @"^(\\d{1,3}\\.){3}\\d{1,3}$";
    NSRegularExpression *ipv4Regex = [NSRegularExpression regularExpressionWithPattern:ipv4Pattern options:0 error:nil];
    if ([ipv4Regex numberOfMatchesInString:handle options:0 range:NSMakeRange(0, handle.length)] > 0) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1003 userInfo:@{NSLocalizedDescriptionKey: @"Handle cannot be an IPv4 address"}];
        return NO;
    }

    // Split into labels
    NSArray<NSString *> *labels = [handle componentsSeparatedByString:@"."];
    if (labels.count < 2) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1004 userInfo:@{NSLocalizedDescriptionKey: @"Handle must have at least two segments (e.g. example.com)"}];
        return NO;
    }

    // Label validation regex per atproto spec reference pattern
    // Each label: [a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?
    // This ensures: 1-63 chars, alphanumeric start/end, hyphens allowed in middle only
    NSString *labelPattern = @"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$";
    NSRegularExpression *labelRegex = [NSRegularExpression regularExpressionWithPattern:labelPattern options:0 error:nil];

    for (NSString *label in labels) {
        if (label.length == 0) {
            if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1005 userInfo:@{NSLocalizedDescriptionKey: @"Handle cannot contain empty segments (e.g. ..)"}];
            return NO;
        }
        if (label.length > 63) {
            if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1006 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Label too long: %@", label]}];
            return NO;
        }

        if ([labelRegex numberOfMatchesInString:label options:0 range:NSMakeRange(0, label.length)] == 0) {
            if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1007 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid characters or hyphen placement in label: %@", label]}];
            return NO;
        }
    }

    // TLD validation per atproto spec
    // The TLD (last segment) must:
    // 1. Not be all numeric (per spec text: "The last segment (TLD) can not start with a numeric digit")
    // 2. Match the reference regex pattern for full compliance
    NSString *tld = labels.lastObject;

    // Check: TLD cannot be all numeric
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([tld rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1008 userInfo:@{NSLocalizedDescriptionKey: @"TLD cannot be all numeric"}];
        return NO;
    }

    // Additional validation: TLD must match the reference regex pattern
    // Pattern: [a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?
    // This ensures TLD starts with letter and ends with alphanumeric
    NSString *tldPattern = @"^[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$";
    NSRegularExpression *tldRegex = [NSRegularExpression regularExpressionWithPattern:tldPattern options:0 error:nil];
    if ([tldRegex numberOfMatchesInString:tld options:0 range:NSMakeRange(0, tld.length)] == 0) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1009 userInfo:@{NSLocalizedDescriptionKey: @"TLD must start with a letter and contain only alphanumeric characters and hyphens"}];
        return NO;
    }

    return YES;
}

+ (BOOL)validateHandleSyntax:(NSString *)handle error:(NSError **)error {
    if (!handle || handle.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"Handle cannot be empty"}];
        return NO;
    }

    if (handle.length > 253) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1002 userInfo:@{NSLocalizedDescriptionKey: @"Handle too long (max 253 chars)"}];
        return NO;
    }

    NSArray<NSString *> *labels = [handle componentsSeparatedByString:@"."];
    if (labels.count < 2) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1004 userInfo:@{NSLocalizedDescriptionKey: @"Handle must have at least two segments"}];
        return NO;
    }

    NSString *labelPattern = @"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$";
    NSRegularExpression *labelRegex = [NSRegularExpression regularExpressionWithPattern:labelPattern options:0 error:nil];

    NSUInteger index = 0;
    for (NSString *label in labels) {
        if (label.length == 0 || label.length > 63) {
            if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1005 + (label.length > 63 ? 1 : 0) userInfo:@{NSLocalizedDescriptionKey: label.length == 0 ? @"Handle cannot contain empty segments" : @"Label too long"}];
            return NO;
        }

        if ([labelRegex numberOfMatchesInString:label options:0 range:NSMakeRange(0, label.length)] == 0) {
            if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1007 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid characters or hyphen placement in label: %@", label]}];
            return NO;
        }

        // TLD validation (last segment)
        if (index == labels.count - 1) {
            NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
            if ([label rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
                if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1008 userInfo:@{NSLocalizedDescriptionKey: @"TLD cannot be all numeric"}];
                return NO;
            }

            NSString *tldPattern = @"^[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$";
            NSRegularExpression *tldRegex = [NSRegularExpression regularExpressionWithPattern:tldPattern options:0 error:nil];
            if ([tldRegex numberOfMatchesInString:label options:0 range:NSMakeRange(0, label.length)] == 0) {
                if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1009 userInfo:@{NSLocalizedDescriptionKey: @"TLD must start with a letter"}];
                return NO;
            }
        }

        index++;
    }

    return YES;
}

+ (NSString *)normalizeHandle:(NSString *)handle {
    return [handle lowercaseString];
}

@end
