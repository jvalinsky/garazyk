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
    
    // Check for IP address (basic check)
    // IPv4 regex
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
    
    // Label validation regex: ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$
    // Adjusted to case-insensitive for input, though we normalize before strict usage usually
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
            if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1007 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid characters in label: %@", label]}];
            return NO;
        }
    }
    
    // TLD Check: Last segment should be a valid TLD (alphabetic only is a safe-ish bet for ATProto, though ICANN allows numbers now. ATProto usually allows any valid DNS TLD)
    // Actually, simply ensuring it's not numeric is the key to distinguish from IP. But we already checked IP.
    // Spec says: "The last segment (TLD) must not be all numeric."
    NSString *tld = labels.lastObject;
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([tld rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
         if (error) *error = [NSError errorWithDomain:@"com.atproto.handle" code:1008 userInfo:@{NSLocalizedDescriptionKey: @"TLD cannot be all numeric"}];
         return NO;
    }

    return YES;
}

+ (NSString *)normalizeHandle:(NSString *)handle {
    return [handle lowercaseString];
}

@end
