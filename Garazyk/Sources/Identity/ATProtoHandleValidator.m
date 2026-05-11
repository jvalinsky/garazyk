// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Identity/ATProtoHandleValidator.h"

NSString * const ATProtoHandleErrorDomain = @"com.atproto.handle";
NSString * const ATProtoEmailErrorDomain = @"com.atproto.email";

NSString *handleErrorDescriptionForCode(NSInteger code, NSString *handle, NSString *label) {
    switch (code) {
        case 1001:
            return @"Handle cannot be empty";
        case 1002:
            return [NSString stringWithFormat:@"Handle is too long (%lu characters). Maximum length is 253 characters.", (unsigned long)handle.length];
        case 1003:
            return @"Handle cannot be an IP address. Use a domain name like example.com";
        case 1004:
            return @"Handle must have at least two parts separated by dots (e.g., example.com)";
        case 1005:
            return @"Handle cannot contain empty parts (e.g., '..' or leading/trailing dots)";
        case 1006:
            return [NSString stringWithFormat:@"Label '%@' is too long. Each part must be 63 characters or less.", label];
        case 1007: {
            NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"];
            NSCharacterSet *invalid = [validChars invertedSet];
            NSString *invalidChars = @"";
            for (NSUInteger i = 0; i < label.length; i++) {
                unichar c = [label characterAtIndex:i];
                if ([invalid characterIsMember:c]) {
                    invalidChars = [invalidChars stringByAppendingFormat:@" '%C'", c];
                }
            }
            return [NSString stringWithFormat:@"Label '%@' contains invalid characters:%@. Only letters (a-z), numbers (0-9), and hyphens (-) are allowed.", label, invalidChars];
        }
        case 1008:
            return @"Top-level domain (TLD) cannot be all numbers. This helps distinguish handles from IP addresses. Use a real domain like .com, .social, .test, or .bsky.";
        case 1009:
            return @"Handle cannot start with 'admin.' - this prefix is reserved";
        default:
            return @"Invalid handle";
    }
}

NSString *handleRecoverySuggestionForCode(NSInteger code, NSString *handle) {
    switch (code) {
        case 1001:
            return @"Provide a handle in the format: username.domain (e.g., alice.test)";
        case 1002:
            return @"Shorten your handle to 253 characters or less";
        case 1003:
            return @"Use a domain name instead of an IP address. For testing, you can use .test TLD (e.g., alice.test)";
        case 1004:
            return @"Add a domain after the username. Valid examples: alice.test, bob.example.com";
        case 1005:
            return @"Remove empty parts from your handle. For example, change 'alice..example.com' to 'alice.example.com'";
        case 1006:
            return @"Shorten each part of your handle to 63 characters or less";
        case 1007:
            return @"Remove any special characters, spaces, or symbols. Only letters, numbers, and hyphens are allowed";
        case 1008:
            return @"Use a non-numeric TLD like .com, .social, .test, .app, or .bsky instead of numbers";
        case 1009:
            return @"Choose a handle that doesn't start with 'admin.'";
        default:
            return @"Check that your handle follows DNS naming rules";
    }
}

NSString *emailErrorDescriptionForCode(NSInteger code) {
    switch (code) {
        case 2001:
            return @"Email cannot be empty";
        case 2002:
            return @"Email is too long (maximum 254 characters)";
        case 2003:
            return @"Email format is invalid. Missing '@' symbol";
        case 2004:
            return @"Email local part (before @) is invalid";
        case 2005:
            return @"Email domain part (after @) is invalid";
        default:
            return @"Invalid email address";
    }
}

NSString *emailRecoverySuggestionForCode(NSInteger code) {
    switch (code) {
        case 2001:
            return @"Provide an email address like user@example.com";
        case 2002:
            return @"Shorten your email address to 254 characters or less";
        case 2003:
            return @"Include the '@' symbol. Example: username@domain.com";
        case 2004:
            return @"The part before @ can only contain letters, numbers, and these symbols: ._%+-";
        case 2005:
            return @"The domain part must be a valid domain name (e.g., gmail.com, company.org)";
        default:
            return @"Check that your email follows the format: user@domain.extension";
    }
}

@implementation ATProtoHandleValidator

+ (BOOL)validateHandle:(NSString *)handle error:(NSError **)error {
    if (!handle || handle.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoHandleErrorDomain
                                         code:1001
                                     userInfo:@{
                NSLocalizedDescriptionKey: handleErrorDescriptionForCode(1001, handle, nil),
                NSLocalizedRecoverySuggestionErrorKey: handleRecoverySuggestionForCode(1001, handle)
            }];
        }
        return NO;
    }
    
    if (handle.length > 253) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoHandleErrorDomain
                                         code:1002
                                     userInfo:@{
                NSLocalizedDescriptionKey: handleErrorDescriptionForCode(1002, handle, nil),
                NSLocalizedRecoverySuggestionErrorKey: handleRecoverySuggestionForCode(1002, handle)
            }];
        }
        return NO;
    }
    
    NSString *ipv4Pattern = @"^(\\d{1,3}\\.){3}\\d{1,3}$";
    NSRegularExpression *ipv4Regex = [NSRegularExpression regularExpressionWithPattern:ipv4Pattern options:0 error:nil];
    if ([ipv4Regex numberOfMatchesInString:handle options:0 range:NSMakeRange(0, handle.length)] > 0) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoHandleErrorDomain
                                         code:1003
                                     userInfo:@{
                NSLocalizedDescriptionKey: handleErrorDescriptionForCode(1003, handle, nil),
                NSLocalizedRecoverySuggestionErrorKey: handleRecoverySuggestionForCode(1003, handle)
            }];
        }
        return NO;
    }
    
    NSArray<NSString *> *labels = [handle componentsSeparatedByString:@"."];
    if (labels.count < 2) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoHandleErrorDomain
                                         code:1004
                                     userInfo:@{
                NSLocalizedDescriptionKey: handleErrorDescriptionForCode(1004, handle, nil),
                NSLocalizedRecoverySuggestionErrorKey: handleRecoverySuggestionForCode(1004, handle)
            }];
        }
        return NO;
    }
    
    // Reject reserved prefixes
    if ([[handle lowercaseString] hasPrefix:@"admin."]) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoHandleErrorDomain
                                         code:1009
                                     userInfo:@{
                NSLocalizedDescriptionKey: handleErrorDescriptionForCode(1009, handle, nil),
                NSLocalizedRecoverySuggestionErrorKey: handleRecoverySuggestionForCode(1009, handle)
            }];
        }
        return NO;
    }
    
    NSString *labelPattern = @"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$";
    NSRegularExpression *labelRegex = [NSRegularExpression regularExpressionWithPattern:labelPattern options:0 error:nil];
    
    for (NSString *label in labels) {
        if (label.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:ATProtoHandleErrorDomain
                                             code:1005
                                         userInfo:@{
                    NSLocalizedDescriptionKey: handleErrorDescriptionForCode(1005, handle, nil),
                    NSLocalizedRecoverySuggestionErrorKey: handleRecoverySuggestionForCode(1005, handle)
                }];
            }
            return NO;
        }
        if (label.length > 63) {
            if (error) {
                *error = [NSError errorWithDomain:ATProtoHandleErrorDomain
                                             code:1006
                                         userInfo:@{
                    NSLocalizedDescriptionKey: handleErrorDescriptionForCode(1006, handle, label),
                    NSLocalizedRecoverySuggestionErrorKey: handleRecoverySuggestionForCode(1006, handle)
                }];
            }
            return NO;
        }
        
        if ([labelRegex numberOfMatchesInString:label options:0 range:NSMakeRange(0, label.length)] == 0) {
            if (error) {
                *error = [NSError errorWithDomain:ATProtoHandleErrorDomain
                                             code:1007
                                         userInfo:@{
                    NSLocalizedDescriptionKey: handleErrorDescriptionForCode(1007, handle, label),
                    NSLocalizedRecoverySuggestionErrorKey: handleRecoverySuggestionForCode(1007, handle)
                }];
            }
            return NO;
        }
    }
    
    NSString *tld = labels.lastObject;
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([tld rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
         if (error) {
             *error = [NSError errorWithDomain:ATProtoHandleErrorDomain
                                          code:1008
                                      userInfo:@{
                 NSLocalizedDescriptionKey: handleErrorDescriptionForCode(1008, handle, nil),
                 NSLocalizedRecoverySuggestionErrorKey: handleRecoverySuggestionForCode(1008, handle)
             }];
         }
         return NO;
    }
    
    return YES;
}

+ (NSString *)normalizeHandle:(NSString *)handle {
    return [handle lowercaseString];
}

+ (nullable NSString *)validateAndNormalizeHandle:(NSString *)handle error:(NSError **)error {
    if (![self validateHandle:handle error:error]) {
        return nil;
    }
    return [self normalizeHandle:handle];
}

+ (BOOL)validateEmail:(NSString *)email error:(NSError **)error {
    if (!email || email.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoEmailErrorDomain
                                         code:2001
                                     userInfo:@{
                NSLocalizedDescriptionKey: emailErrorDescriptionForCode(2001),
                NSLocalizedRecoverySuggestionErrorKey: emailRecoverySuggestionForCode(2001)
            }];
        }
        return NO;
    }
    
    if (email.length > 254) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoEmailErrorDomain
                                         code:2002
                                     userInfo:@{
                NSLocalizedDescriptionKey: emailErrorDescriptionForCode(2002),
                NSLocalizedRecoverySuggestionErrorKey: emailRecoverySuggestionForCode(2002)
            }];
        }
        return NO;
    }
    
    NSRange atRange = [email rangeOfString:@"@"];
    if (atRange.location == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoEmailErrorDomain
                                         code:2003
                                     userInfo:@{
                NSLocalizedDescriptionKey: emailErrorDescriptionForCode(2003),
                NSLocalizedRecoverySuggestionErrorKey: emailRecoverySuggestionForCode(2003)
            }];
        }
        return NO;
    }
    
    NSString *localPart = [email substringToIndex:atRange.location];
    NSString *domainPart = [email substringFromIndex:atRange.location + 1];
    
    NSString *localPattern = @"^[a-zA-Z0-9][a-zA-Z0-9._%+-]{0,63}$";
    NSRegularExpression *localRegex = [NSRegularExpression regularExpressionWithPattern:localPattern options:0 error:nil];
    if (localPart.length == 0 || localPart.length > 64 ||
        [localRegex numberOfMatchesInString:localPart options:0 range:NSMakeRange(0, localPart.length)] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoEmailErrorDomain
                                         code:2004
                                     userInfo:@{
                NSLocalizedDescriptionKey: emailErrorDescriptionForCode(2004),
                NSLocalizedRecoverySuggestionErrorKey: emailRecoverySuggestionForCode(2004)
            }];
        }
        return NO;
    }
    
    NSString *domainPattern = @"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$";
    NSRegularExpression *domainRegex = [NSRegularExpression regularExpressionWithPattern:domainPattern options:0 error:nil];
    if (domainPart.length == 0 || domainPart.length > 253 ||
        [domainRegex numberOfMatchesInString:domainPart options:0 range:NSMakeRange(0, domainPart.length)] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:ATProtoEmailErrorDomain
                                         code:2005
                                     userInfo:@{
                NSLocalizedDescriptionKey: emailErrorDescriptionForCode(2005),
                NSLocalizedRecoverySuggestionErrorKey: emailRecoverySuggestionForCode(2005)
            }];
        }
        return NO;
    }
    
    return YES;
}

@end
