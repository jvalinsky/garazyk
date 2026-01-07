#import <Foundation/Foundation.h>
#import "Core/DID.h"

@interface DIDValidator : NSObject

+ (BOOL)isValidPlcIdentifier:(NSString *)identifier;
+ (BOOL)isValidWebIdentifier:(NSString *)identifier;
+ (NSError *)plcValidationErrorForIdentifier:(NSString *)identifier;
+ (NSError *)webValidationErrorForIdentifier:(NSString *)identifier;

@end

@implementation DIDValidator

+ (BOOL)isValidPlcIdentifier:(NSString *)identifier {
    return [self plcValidationErrorForIdentifier:identifier] == nil;
}

+ (BOOL)isValidWebIdentifier:(NSString *)identifier {
    return [self webValidationErrorForIdentifier:identifier] == nil;
}

+ (NSError *)plcValidationErrorForIdentifier:(NSString *)identifier {
    if (!identifier || identifier.length == 0) {
        return [NSError errorWithDomain:DIDErrorDomain
                                   code:DIDErrorInvalidIdentifier
                               userInfo:@{NSLocalizedDescriptionKey: @"PLC identifier cannot be empty"}];
    }

    NSString *identifierLower = [identifier lowercaseString];

    if (![identifierLower hasPrefix:@"did:plc:"]) {
        return [NSError errorWithDomain:DIDErrorDomain
                                   code:DIDErrorInvalidIdentifier
                               userInfo:@{NSLocalizedDescriptionKey: @"PLC identifier must start with 'did:plc:'"}];
    }

    NSString *idPart = [identifierLower substringFromIndex:8];

    if (idPart.length != 24) {
        return [NSError errorWithDomain:DIDErrorDomain
                                   code:DIDErrorInvalidIdentifier
                               userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"PLC identifier must be exactly 24 characters, got %lu", (unsigned long)idPart.length]}];
    }

    NSString *validChars = @"abcdefghijklmnopqrstuvwxyz234567";
    NSCharacterSet *validSet = [NSCharacterSet characterSetWithCharactersInString:validChars];
    NSCharacterSet *inputSet = [NSCharacterSet characterSetWithCharactersInString:idPart];

    if (![validSet isSupersetOfSet:inputSet]) {
        return [NSError errorWithDomain:DIDErrorDomain
                                   code:DIDErrorInvalidIdentifier
                               userInfo:@{NSLocalizedDescriptionKey: @"PLC identifier contains invalid characters (only a-z and 2-7 allowed)"}];
    }

    return nil;
}

+ (NSError *)webValidationErrorForIdentifier:(NSString *)identifier {
    if (!identifier || identifier.length == 0) {
        return [NSError errorWithDomain:DIDErrorDomain
                                   code:DIDErrorInvalidIdentifier
                               userInfo:@{NSLocalizedDescriptionKey: @"Web identifier cannot be empty"}];
    }

    NSString *identifierLower = [identifier lowercaseString];

    if (![identifierLower hasPrefix:@"did:web:"]) {
        return [NSError errorWithDomain:DIDErrorDomain
                                   code:DIDErrorInvalidIdentifier
                               userInfo:@{NSLocalizedDescriptionKey: @"Web identifier must start with 'did:web:'"}];
    }

    NSString *afterPrefix = [identifierLower substringFromIndex:8];

    if (afterPrefix.length == 0) {
        return [NSError errorWithDomain:DIDErrorDomain
                                   code:DIDErrorInvalidIdentifier
                               userInfo:@{NSLocalizedDescriptionKey: @"Web identifier must include a hostname"}];
    }

    NSString *hostname;
    NSString *path = @"";

    NSRange firstColon = [afterPrefix rangeOfString:@":"];
    if (firstColon.location == NSNotFound) {
        hostname = afterPrefix;
    } else {
        hostname = [afterPrefix substringToIndex:firstColon.location];
        path = [afterPrefix substringFromIndex:firstColon.location + 1];
    }

    if (hostname.length == 0) {
        return [NSError errorWithDomain:DIDErrorDomain
                                   code:DIDErrorInvalidIdentifier
                               userInfo:@{NSLocalizedDescriptionKey: @"Web identifier must include a hostname"}];
    }

    BOOL isIPAddress = NO;
    NSRegularExpression *ipRegex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"
                                                                             options:0
                                                                               error:nil];
    if ([ipRegex numberOfMatchesInString:hostname options:0 range:NSMakeRange(0, hostname.length)] > 0) {
        isIPAddress = YES;
    } else {
        NSArray *labels = [hostname componentsSeparatedByString:@"."];
        if (labels.count < 2) {
            return [NSError errorWithDomain:DIDErrorDomain
                                       code:DIDErrorInvalidIdentifier
                                   userInfo:@{NSLocalizedDescriptionKey: @"Web identifier must be a valid hostname (at least 2 labels)"}];
        }

        NSString *hostRegex = @"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$";
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:hostRegex
                                                                              options:NSRegularExpressionCaseInsensitive
                                                                                error:nil];
        NSRange entireRange = NSMakeRange(0, hostname.length);
        NSArray *matches = [regex matchesInString:hostname options:0 range:entireRange];

        if (matches.count != 1) {
            return [NSError errorWithDomain:DIDErrorDomain
                                       code:DIDErrorInvalidIdentifier
                                   userInfo:@{NSLocalizedDescriptionKey: @"Web identifier is not a valid hostname"}];
        }

        NSTextCheckingResult *firstMatch = matches.firstObject;
        if (firstMatch.range.location != 0 || firstMatch.range.length != hostname.length) {
            return [NSError errorWithDomain:DIDErrorDomain
                                       code:DIDErrorInvalidIdentifier
                                   userInfo:@{NSLocalizedDescriptionKey: @"Web identifier is not a valid hostname"}];
        }

        NSArray *forbiddenTLDs = @[@"onion", @"exit", @"tor", @"i2p", @"freenet"];
        NSString *tld = [labels lastObject];
        if ([forbiddenTLDs containsObject:tld]) {
            return [NSError errorWithDomain:DIDErrorDomain
                                       code:DIDErrorInvalidIdentifier
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"TLD '.%@' is not allowed for handles", tld]}];
        }
    }

    if ([hostname containsString:@"--"] || [hostname containsString:@".."]) {
        return [NSError errorWithDomain:DIDErrorDomain
                                   code:DIDErrorInvalidIdentifier
                               userInfo:@{NSLocalizedDescriptionKey: @"Web identifier contains invalid patterns (consecutive hyphens or dots)"}];
    }

    return nil;
}

@end

#pragma mark - Test Runner

int runDIDValidationTests(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"🧪 Running DID Format Validation Tests");
        NSUInteger totalTests = 0;
        NSUInteger passedTests = 0;

        NSLog(@"\n========== did:plc VALIDATION TESTS ==========\n");

        // Test 1: Valid PLC identifier (standard)
        totalTests++;
        if ([DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs64oiz"]) {
            passedTests++;
            NSLog(@"✅ PLC Valid (standard): PASSED");
        } else {
            NSLog(@"❌ PLC Valid (standard): FAILED - should accept standard PLC DID");
        }

        // Test 2: Valid PLC identifier (another example - 24 char base32)
        totalTests++;
        if ([DIDValidator isValidPlcIdentifier:@"did:plc:7HjwGtP5cLyq3vD5nDzDgXYZ"]) {
            passedTests++;
            NSLog(@"✅ PLC Valid (alternate): PASSED");
        } else {
            NSLog(@"❌ PLC Valid (alternate): FAILED");
        }

        // Test 3: PLC - Empty string
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:@""]) {
            passedTests++;
            NSLog(@"✅ PLC Empty: PASSED");
        } else {
            NSLog(@"❌ PLC Empty: FAILED - should reject empty string");
        }

        // Test 4: PLC - Nil
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:nil]) {
            passedTests++;
            NSLog(@"✅ PLC Nil: PASSED");
        } else {
            NSLog(@"❌ PLC Nil: FAILED - should reject nil");
        }

        // Test 5: PLC - Wrong prefix
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:@"did:web:abc123"]) {
            passedTests++;
            NSLog(@"✅ PLC Wrong Prefix: PASSED");
        } else {
            NSLog(@"❌ PLC Wrong Prefix: FAILED - should reject did:web");
        }

        // Test 6: PLC - No prefix
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:@"abc12345678901234567890"]) {
            passedTests++;
            NSLog(@"✅ PLC No Prefix: PASSED");
        } else {
            NSLog(@"❌ PLC No Prefix: FAILED - should reject DIDs without prefix");
        }

        // Test 7: PLC - Too short (23 chars)
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs64oi"]) {
            passedTests++;
            NSLog(@"✅ PLC Too Short: PASSED");
        } else {
            NSLog(@"❌ PLC Too Short: FAILED - should reject 23 char identifier");
        }

        // Test 8: PLC - Too long (25 chars)
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs64oiza"]) {
            passedTests++;
            NSLog(@"✅ PLC Too Long: PASSED");
        } else {
            NSLog(@"❌ PLC Too Long: FAILED - should reject 25 char identifier");
        }

        // Test 9: PLC - Invalid char '0'
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs640iz"]) {
            passedTests++;
            NSLog(@"✅ PLC Invalid '0': PASSED");
        } else {
            NSLog(@"❌ PLC Invalid '0': FAILED - should reject digit 0");
        }

        // Test 10: PLC - Invalid char '1'
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs641iz"]) {
            passedTests++;
            NSLog(@"✅ PLC Invalid '1': PASSED");
        } else {
            NSLog(@"❌ PLC Invalid '1': FAILED - should reject digit 1");
        }

        // Test 11: PLC - Invalid char '8'
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs648iz"]) {
            passedTests++;
            NSLog(@"✅ PLC Invalid '8': PASSED");
        } else {
            NSLog(@"❌ PLC Invalid '8': FAILED - should reject digit 8");
        }

        // Test 12: PLC - Invalid char '9'
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs649iz"]) {
            passedTests++;
            NSLog(@"✅ PLC Invalid '9': PASSED");
        } else {
            NSLog(@"❌ PLC Invalid '9': FAILED - should reject digit 9");
        }

        // Test 13: PLC - Uppercase letters (should be normalized and accepted per DID spec)
        totalTests++;
        if ([DIDValidator isValidPlcIdentifier:@"did:plc:EWVI7NXZYOUN6ZHXRHS64OIZ"]) {
            passedTests++;
            NSLog(@"✅ PLC Uppercase (normalized): PASSED");
        } else {
            NSLog(@"❌ PLC Uppercase (normalized): FAILED - should normalize and accept uppercase");
        }

        // Test 14: PLC - Mixed case (should be normalized)
        totalTests++;
        if ([DIDValidator isValidPlcIdentifier:@"did:plc:EwVi7nXZyOuN6ZhXrHs64OiZ"]) {
            passedTests++;
            NSLog(@"✅ PLC Mixed Case (normalized): PASSED");
        } else {
            NSLog(@"❌ PLC Mixed Case (normalized): FAILED - should normalize and accept");
        }

        // Test 15: PLC - Special chars like dash
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun-zhxrhs64oiz"]) {
            passedTests++;
            NSLog(@"✅ PLC Dash: PASSED");
        } else {
            NSLog(@"❌ PLC Dash: FAILED - should reject dash");
        }

        // Test 16: PLC - Special chars like underscore
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun_zhxrhs64oiz"]) {
            passedTests++;
            NSLog(@"✅ PLC Underscore: PASSED");
        } else {
            NSLog(@"❌ PLC Underscore: FAILED - should reject underscore");
        }

        NSLog(@"\n========== did:web VALIDATION TESTS ==========\n");

        // Test 17: Valid Web identifier (basic domain)
        totalTests++;
        if ([DIDValidator isValidWebIdentifier:@"did:web:example.com"]) {
            passedTests++;
            NSLog(@"✅ Web Valid (basic): PASSED");
        } else {
            NSLog(@"❌ Web Valid (basic): FAILED");
        }

        // Test 18: Valid Web identifier (subdomain)
        totalTests++;
        if ([DIDValidator isValidWebIdentifier:@"did:web:sub.example.com"]) {
            passedTests++;
            NSLog(@"✅ Web Valid (subdomain): PASSED");
        } else {
            NSLog(@"❌ Web Valid (subdomain): FAILED");
        }

        // Test 19: Valid Web identifier (with path)
        totalTests++;
        if ([DIDValidator isValidWebIdentifier:@"did:web:example.com:user:profile"]) {
            passedTests++;
            NSLog(@"✅ Web Valid (path): PASSED");
        } else {
            NSLog(@"❌ Web Valid (path): FAILED");
        }

        // Test 20: Web - Empty string
        totalTests++;
        if (![DIDValidator isValidWebIdentifier:@""]) {
            passedTests++;
            NSLog(@"✅ Web Empty: PASSED");
        } else {
            NSLog(@"❌ Web Empty: FAILED - should reject empty string");
        }

        // Test 21: Web - Nil
        totalTests++;
        if (![DIDValidator isValidWebIdentifier:nil]) {
            passedTests++;
            NSLog(@"✅ Web Nil: PASSED");
        } else {
            NSLog(@"❌ Web Nil: FAILED - should reject nil");
        }

        // Test 22: Web - Wrong prefix
        totalTests++;
        if (![DIDValidator isValidWebIdentifier:@"did:plc:example.com"]) {
            passedTests++;
            NSLog(@"✅ Web Wrong Prefix: PASSED");
        } else {
            NSLog(@"❌ Web Wrong Prefix: FAILED - should reject did:plc");
        }

        // Test 23: Web - No hostname
        totalTests++;
        if (![DIDValidator isValidWebIdentifier:@"did:web:"]) {
            passedTests++;
            NSLog(@"✅ Web No Hostname: PASSED");
        } else {
            NSLog(@"❌ Web No Hostname: FAILED - should reject empty hostname");
        }

        // Test 24: Web - Single label (no TLD)
        totalTests++;
        if (![DIDValidator isValidWebIdentifier:@"did:web:localhost"]) {
            passedTests++;
            NSLog(@"✅ Web Single Label: PASSED");
        } else {
            NSLog(@"❌ Web Single Label: FAILED - should reject single label hostnames");
        }

        // Test 25: Web - Starts with hyphen
        totalTests++;
        if (![DIDValidator isValidWebIdentifier:@"did:web:-example.com"]) {
            passedTests++;
            NSLog(@"✅ Web Starts With Hyphen: PASSED");
        } else {
            NSLog(@"❌ Web Starts With Hyphen: FAILED");
        }

        // Test 26: Web - Ends with hyphen
        totalTests++;
        if (![DIDValidator isValidWebIdentifier:@"did:web:example-.com"]) {
            passedTests++;
            NSLog(@"✅ Web Ends With Hyphen: PASSED");
        } else {
            NSLog(@"❌ Web Ends With Hyphen: FAILED");
        }

        // Test 27: Web - Consecutive hyphens
        totalTests++;
        if (![DIDValidator isValidWebIdentifier:@"did:web:exam--ple.com"]) {
            passedTests++;
            NSLog(@"✅ Web Consecutive Hyphens: PASSED");
        } else {
            NSLog(@"❌ Web Consecutive Hyphens: FAILED");
        }

        // Test 28: Web - Consecutive dots
        totalTests++;
        if (![DIDValidator isValidWebIdentifier:@"did:web:example..com"]) {
            passedTests++;
            NSLog(@"✅ Web Consecutive Dots: PASSED");
        } else {
            NSLog(@"❌ Web Consecutive Dots: FAILED");
        }

        // Test 29: Web - Forbidden TLD (.onion)
        totalTests++;
        if (![DIDValidator isValidWebIdentifier:@"did:web:example.onion"]) {
            passedTests++;
            NSLog(@"✅ Web Forbidden TLD (onion): PASSED");
        } else {
            NSLog(@"❌ Web Forbidden TLD (onion): FAILED - should reject .onion TLD");
        }

        // Test 30: Web - Forbidden TLD (.exit)
        totalTests++;
        if (![DIDValidator isValidWebIdentifier:@"did:web:example.exit"]) {
            passedTests++;
            NSLog(@"✅ Web Forbidden TLD (exit): PASSED");
        } else {
            NSLog(@"❌ Web Forbidden TLD (exit): FAILED");
        }

        // Test 31: Web - Valid with numbers
        totalTests++;
        if ([DIDValidator isValidWebIdentifier:@"did:web:server123.example.com"]) {
            passedTests++;
            NSLog(@"✅ Web With Numbers: PASSED");
        } else {
            NSLog(@"❌ Web With Numbers: FAILED");
        }

        // Test 32: Web - Valid hyphen in middle
        totalTests++;
        if ([DIDValidator isValidWebIdentifier:@"did:web:my-server.example.com"]) {
            passedTests++;
            NSLog(@"✅ Web Hyphen In Middle: PASSED");
        } else {
            NSLog(@"❌ Web Hyphen In Middle: FAILED");
        }

        // Test 33: Web - IP address (should be valid)
        totalTests++;
        if ([DIDValidator isValidWebIdentifier:@"did:web:127.0.0.1"]) {
            passedTests++;
            NSLog(@"✅ Web IP Address: PASSED");
        } else {
            NSLog(@"❌ Web IP Address: FAILED");
        }

        NSLog(@"\n========== EDGE CASE TESTS ==========\n");

        // Test 34: PLC - Exactly valid length boundary
        totalTests++;
        if ([DIDValidator isValidPlcIdentifier:@"did:plc:abcdefghijklmnopqrstuvwx"]) {
            passedTests++;
            NSLog(@"✅ PLC 24 chars (valid): PASSED");
        } else {
            NSLog(@"❌ PLC 24 chars (valid): FAILED");
        }

        // Test 35: PLC - Valid chars only
        totalTests++;
        if ([DIDValidator isValidPlcIdentifier:@"did:plc:abcdefghijklmnopqrstuvwx"]) {
            passedTests++;
            NSLog(@"✅ PLC All Valid Chars: PASSED");
        } else {
            NSLog(@"❌ PLC All Valid Chars: FAILED");
        }

        // Test 36: PLC - Invalid char at start
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:@"did:plc:0bcdefghijklmnopqrstuvwx"]) {
            passedTests++;
            NSLog(@"✅ PLC Invalid First Char: PASSED");
        } else {
            NSLog(@"❌ PLC Invalid First Char: FAILED");
        }

        // Test 37: PLC - Unicode characters
        totalTests++;
        if (![DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs64oiż"]) {
            passedTests++;
            NSLog(@"✅ PLC Unicode: PASSED");
        } else {
            NSLog(@"❌ PLC Unicode: FAILED - should reject unicode");
        }

        // Test 38: Web - Very long hostname
        totalTests++;
        NSString *longHostname = [@"a" stringByPaddingToLength:63 withString:@"a" startingAtIndex:0];
        NSString *longWeb = [NSString stringWithFormat:@"did:web:%@.com", longHostname];
        if ([DIDValidator isValidWebIdentifier:longWeb]) {
            passedTests++;
            NSLog(@"✅ Web Long Hostname (63 chars): PASSED");
        } else {
            NSLog(@"❌ Web Long Hostname (63 chars): FAILED");
        }

        // Test 39: Web - Single character label
        totalTests++;
        if ([DIDValidator isValidWebIdentifier:@"did:web:a.b"]) {
            passedTests++;
            NSLog(@"✅ Web Single Char Label: PASSED");
        } else {
            NSLog(@"❌ Web Single Char Label: FAILED");
        }

        // Test 40: Mixed method - both valid
        totalTests++;
        BOOL plcValid = [DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs64oiz"];
        BOOL webValid = [DIDValidator isValidWebIdentifier:@"did:web:example.com"];
        if (plcValid && webValid) {
            passedTests++;
            NSLog(@"✅ Both Methods Valid: PASSED");
        } else {
            NSLog(@"❌ Both Methods Valid: FAILED - PLC: %@, Web: %@", plcValid ? @"YES" : @"NO", webValid ? @"YES" : @"NO");
        }

        NSLog(@"\n========== ERROR MESSAGE TESTS ==========\n");

        // Test 41: PLC error message content
        totalTests++;
        NSError *plcError = [DIDValidator plcValidationErrorForIdentifier:@"did:plc:abc"];
        if (plcError && plcError.localizedDescription && plcError.localizedDescription.length > 0) {
            passedTests++;
            NSLog(@"✅ PLC Error Has Message: PASSED");
        } else {
            NSLog(@"❌ PLC Error Has Message: FAILED");
        }

        // Test 42: Web error message content
        totalTests++;
        NSError *webError = [DIDValidator webValidationErrorForIdentifier:@"did:web:"];
        if (webError && webError.localizedDescription && webError.localizedDescription.length > 0) {
            passedTests++;
            NSLog(@"✅ Web Error Has Message: PASSED");
        } else {
            NSLog(@"❌ Web Error Has Message: FAILED");
        }

        // Summary
        NSLog(@"\n========================================");
        NSLog(@"🎯 DID Validation Test Results: %lu/%lu tests passed", (unsigned long)passedTests, (unsigned long)totalTests);
        NSLog(@"========================================\n");

        if (passedTests == totalTests) {
            NSLog(@"🎉 All DID validation tests PASSED!");
        } else {
            NSLog(@"⚠️  %lu tests FAILED", (unsigned long)(totalTests - passedTests));
        }

        return (int)passedTests;
    }
}

int main(int argc, const char * argv[]) {
    return runDIDValidationTests(argc, argv);
}
