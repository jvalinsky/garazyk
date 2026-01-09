#import <XCTest/XCTest.h>
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

@interface DIDValidationTests : XCTestCase
@end

@implementation DIDValidationTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

#pragma mark - PLC Validation Tests

- (void)testPLCValidStandard {
    XCTAssertTrue([DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs64oiz"], @"Standard PLC DID should be valid");
}

- (void)testPLCValidAlternate {
    XCTAssertTrue([DIDValidator isValidPlcIdentifier:@"did:plc:7HjwGtP5cLyq3vD5nDzDgXYZ"], @"Alternate PLC DID should be valid");
}

- (void)testPLCEmpty {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:@""], @"Empty string should be invalid");
}

- (void)testPLCNil {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:nil], @"Nil should be invalid");
}

- (void)testPLCWrongPrefix {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:@"did:web:abc123"], @"did:web should be invalid for PLC");
}

- (void)testPLCNoPrefix {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:@"abc12345678901234567890"], @"DID without prefix should be invalid");
}

- (void)testPLCTooShort {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs64oi"], @"23 character identifier should be invalid");
}

- (void)testPLCTooLong {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs64oiza"], @"25 character identifier should be invalid");
}

- (void)testPLCInvalidChar0 {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs640iz"], @"Digit '0' should be invalid");
}

- (void)testPLCInvalidChar1 {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs641iz"], @"Digit '1' should be invalid");
}

- (void)testPLCInvalidChar8 {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs648iz"], @"Digit '8' should be invalid");
}

- (void)testPLCInvalidChar9 {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs649iz"], @"Digit '9' should be invalid");
}

- (void)testPLCUppercaseNormalized {
    XCTAssertTrue([DIDValidator isValidPlcIdentifier:@"did:plc:EWVI7NXZYOUN6ZHXRHS64OIZ"], @"Uppercase should be normalized and accepted");
}

- (void)testPLCMixedCaseNormalized {
    XCTAssertTrue([DIDValidator isValidPlcIdentifier:@"did:plc:EwVi7nXZyOuN6ZhXrHs64OiZ"], @"Mixed case should be normalized and accepted");
}

- (void)testPLCDash {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun-zhxrhs64oiz"], @"Dash should be invalid");
}

- (void)testPLCUnderscore {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun_zhxrhs64oiz"], @"Underscore should be invalid");
}

#pragma mark - Web Validation Tests

- (void)testWebValidBasic {
    XCTAssertTrue([DIDValidator isValidWebIdentifier:@"did:web:example.com"], @"Basic domain should be valid");
}

- (void)testWebValidSubdomain {
    XCTAssertTrue([DIDValidator isValidWebIdentifier:@"did:web:sub.example.com"], @"Subdomain should be valid");
}

- (void)testWebValidPath {
    XCTAssertTrue([DIDValidator isValidWebIdentifier:@"did:web:example.com:user:profile"], @"Path should be valid");
}

- (void)testWebEmpty {
    XCTAssertFalse([DIDValidator isValidWebIdentifier:@""], @"Empty string should be invalid");
}

- (void)testWebNil {
    XCTAssertFalse([DIDValidator isValidWebIdentifier:nil], @"Nil should be invalid");
}

- (void)testWebWrongPrefix {
    XCTAssertFalse([DIDValidator isValidWebIdentifier:@"did:plc:example.com"], @"did:plc should be invalid for web");
}

- (void)testWebNoHostname {
    XCTAssertFalse([DIDValidator isValidWebIdentifier:@"did:web:"], @"Empty hostname should be invalid");
}

- (void)testWebSingleLabel {
    XCTAssertFalse([DIDValidator isValidWebIdentifier:@"did:web:localhost"], @"Single label hostname should be invalid");
}

- (void)testWebStartsWithHyphen {
    XCTAssertFalse([DIDValidator isValidWebIdentifier:@"did:web:-example.com"], @"Hostname starting with hyphen should be invalid");
}

- (void)testWebEndsWithHyphen {
    XCTAssertFalse([DIDValidator isValidWebIdentifier:@"did:web:example-.com"], @"Hostname ending with hyphen should be invalid");
}

- (void)testWebConsecutiveHyphens {
    XCTAssertFalse([DIDValidator isValidWebIdentifier:@"did:web:exam--ple.com"], @"Consecutive hyphens should be invalid");
}

- (void)testWebConsecutiveDots {
    XCTAssertFalse([DIDValidator isValidWebIdentifier:@"did:web:example..com"], @"Consecutive dots should be invalid");
}

- (void)testWebForbiddenTLDOnion {
    XCTAssertFalse([DIDValidator isValidWebIdentifier:@"did:web:example.onion"], @".onion TLD should be forbidden");
}

- (void)testWebForbiddenTLDExit {
    XCTAssertFalse([DIDValidator isValidWebIdentifier:@"did:web:example.exit"], @".exit TLD should be forbidden");
}

- (void)testWebWithNumbers {
    XCTAssertTrue([DIDValidator isValidWebIdentifier:@"did:web:server123.example.com"], @"Numbers in hostname should be valid");
}

- (void)testWebHyphenInMiddle {
    XCTAssertTrue([DIDValidator isValidWebIdentifier:@"did:web:my-server.example.com"], @"Hyphen in middle of label should be valid");
}

- (void)testWebIPAddress {
    XCTAssertTrue([DIDValidator isValidWebIdentifier:@"did:web:127.0.0.1"], @"IP address should be valid");
}

#pragma mark - Edge Case Tests

- (void)testPLC24CharsValid {
    XCTAssertTrue([DIDValidator isValidPlcIdentifier:@"did:plc:abcdefghijklmnopqrstuvwx"], @"24 character identifier should be valid");
}

- (void)testPLCAllValidChars {
    XCTAssertTrue([DIDValidator isValidPlcIdentifier:@"did:plc:abcdefghijklmnopqrstuvwx"], @"All valid characters should be accepted");
}

- (void)testPLCInvalidFirstChar {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:@"did:plc:0bcdefghijklmnopqrstuvwx"], @"Invalid first character should be rejected");
}

- (void)testPLCUnicode {
    XCTAssertFalse([DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs64oiż"], @"Unicode characters should be invalid");
}

- (void)testWebLongHostname {
    NSString *longHostname = [@"a" stringByPaddingToLength:63 withString:@"a" startingAtIndex:0];
    NSString *longWeb = [NSString stringWithFormat:@"did:web:%@.com", longHostname];
    XCTAssertTrue([DIDValidator isValidWebIdentifier:longWeb], @"63 character hostname should be valid");
}

- (void)testWebSingleCharLabel {
    XCTAssertTrue([DIDValidator isValidWebIdentifier:@"did:web:a.b"], @"Single character label should be valid");
}

- (void)testBothMethodsValid {
    BOOL plcValid = [DIDValidator isValidPlcIdentifier:@"did:plc:ewvi7nxzyoun6zhxrhs64oiz"];
    BOOL webValid = [DIDValidator isValidWebIdentifier:@"did:web:example.com"];
    XCTAssertTrue(plcValid && webValid, @"Both methods should be independently valid");
}

#pragma mark - Error Message Tests

- (void)testPLCErrorHasMessage {
    NSError *plcError = [DIDValidator plcValidationErrorForIdentifier:@"did:plc:abc"];
    XCTAssertNotNil(plcError, @"Error should not be nil");
    XCTAssertTrue(plcError.localizedDescription.length > 0, @"Error should have a message");
}

- (void)testWebErrorHasMessage {
    NSError *webError = [DIDValidator webValidationErrorForIdentifier:@"did:web:"];
    XCTAssertNotNil(webError, @"Error should not be nil");
    XCTAssertTrue(webError.localizedDescription.length > 0, @"Error should have a message");
}

@end
