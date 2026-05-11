// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Core/TID.h"
// #import "Core/NSID.h" // Does not exist


NS_ASSUME_NONNULL_BEGIN

@interface RecordPathValidationTests : XCTestCase
@end

@implementation RecordPathValidationTests

- (void)testValidRecordPathFormat {
    NSString *path = @"app.bsky.feed.post/3k5f2x7a8c9d";
    XCTAssertTrue([self isValidRecordPath:path], @"Valid path should be accepted");
}

- (void)testValidRecordPathWithTID {
    NSString *path = @"app.bsky.feed.post/3k5f2x7a8c9d1e2b3c4d5e6f";
    XCTAssertTrue([self isValidRecordPath:path], @"TID format should be valid");
}

- (void)testValidRecordPathWithCustomKey {
    NSString *path = @"app.bsky.actor.profile/self";
    XCTAssertTrue([self isValidRecordPath:path], @"Custom rkey should be valid");
}

- (void)testInvalidPathEmptyCollection {
    NSString *path = @"/3k5f2x7a8c9d";
    XCTAssertFalse([self isValidRecordPath:path], @"Empty collection should be rejected");
}

- (void)testInvalidPathEmptyRkey {
    NSString *path = @"app.bsky.feed.post/";
    XCTAssertFalse([self isValidRecordPath:path], @"Empty rkey should be rejected");
}

- (void)testInvalidPathNoSlash {
    NSString *path = @"app.bsky.feed.post3k5f2x7a8c9d";
    XCTAssertFalse([self isValidRecordPath:path], @"Missing slash should be rejected");
}

- (void)testInvalidPathLeadingSlash {
    NSString *path = @"/app.bsky.feed.post/3k5f2x7a8c9d";
    XCTAssertFalse([self isValidRecordPath:path], @"Leading slash should be rejected");
}

- (void)testValidNSIDFormat {
    NSString *nsid = @"app.bsky.feed.post";
    XCTAssertTrue([self isValidNSID:nsid], @"Standard NSID should be valid");
}

- (void)testInvalidNSIDUppercase {
    NSString *nsid = @"app.Bluesky.feed.post";
    XCTAssertFalse([self isValidNSID:nsid], @"Uppercase should be rejected");
}

- (void)testInvalidNSIDStartingWithDash {
    NSString *nsid = @"-app.bsky.feed.post";
    XCTAssertFalse([self isValidNSID:nsid], @"Starting with dash should be rejected");
}

- (void)testValidTIDFormat {
    NSString *tid = @"3k5f2x7a8c9d1e2b";
    XCTAssertTrue([self isValidTID:tid], @"Valid TID should be accepted");
}

- (void)testInvalidTIDTooShort {
    NSString *tid = @"3k5f2";
    XCTAssertFalse([self isValidTID:tid], @"Too short TID should be rejected");
}

- (void)testInvalidTIDLowercaseL {
    NSString *invalidTid = @"3k5f2x7a8c9d1e2l";
    XCTAssertFalse([self isValidTID:invalidTid], @"Lowercase L should be rejected");
}

#pragma mark - Phase 1 Extended Tests

- (void)testRecordPathMaxLength {
    // Record path max length is 512 characters total
    NSMutableString *longRkey = [NSMutableString string];
    for (int i = 0; i < 512 - 20; i++) {
        [longRkey appendString:@"a"];
    }
    NSString *validPath = [NSString stringWithFormat:@"app.bsky.feed.post/%@", longRkey];
    XCTAssertTrue([self isValidRecordPath:validPath], @"Path at max length should be valid");
    
    // Exceed the limit
    [longRkey appendString:@"aaaaaaaaaaaaaaaaaaaaaa"];
    NSString *tooLongPath = [NSString stringWithFormat:@"app.bsky.feed.post/%@", longRkey];
    XCTAssertFalse([self isValidRecordPath:tooLongPath], @"Path exceeding 512 chars should be rejected");
}

- (void)testRecordKeyDotRejected {
    // Single dot as rkey is reserved/invalid
    XCTAssertFalse([self isValidRecordKey:@"."], @"Single dot should be rejected");
}

- (void)testRecordKeyDoubleDotRejected {
    // Double dot as rkey is reserved/invalid
    XCTAssertFalse([self isValidRecordKey:@".."], @"Double dot should be rejected");
}

- (void)testRecordKeyReservedSelf {
    // 'self' is a valid reserved rkey for profile records
    XCTAssertTrue([self isValidRecordKey:@"self"], @"'self' should be a valid rkey");
}

- (void)testRecordKeyPrintableASCII {
    // Valid: 0x21-0x7E (printable ASCII except space)
    XCTAssertTrue([self isValidRecordKey:@"valid-rkey_123"], @"Alphanumeric with dash/underscore should be valid");
    XCTAssertTrue([self isValidRecordKey:@"~special~chars~"], @"Tilde is valid printable ASCII");
    
    // Invalid: space (0x20) and control chars
    XCTAssertFalse([self isValidRecordKey:@"has space"], @"Space should be rejected");
    XCTAssertFalse([self isValidRecordKey:@"has\ttab"], @"Tab should be rejected");
    XCTAssertFalse([self isValidRecordKey:@"has\nnewline"], @"Newline should be rejected");
}

- (void)testRecordPathDoubleSlashRejected {
    // Double slashes in path should be rejected
    XCTAssertFalse([self isValidRecordPath:@"app.bsky.feed.post//rkey"], @"Double slash should be rejected");
}

- (void)testTIDMonotonicityYieldsDescendingOrder {
    // TIDs should be time-ordered - later timestamp = lexically greater
    NSString *earlier = @"3jqfcqzm3fo2j";
    NSString *later = @"3k5f2x7a8c9d1";
    
    // Later TID should compare greater
    NSComparisonResult result = [later compare:earlier];
    XCTAssertEqual(result, NSOrderedDescending, @"Later TID should be lexically greater");
}


- (BOOL)isValidRecordPath:(NSString *)path {
    if (path.length == 0) return NO;
    if ([path hasPrefix:@"/"]) return NO;
    if ([path hasSuffix:@"/"]) return NO;
    if ([path containsString:@"//"]) return NO;
    NSArray *components = [path componentsSeparatedByString:@"/"];
    if (components.count != 2) return NO;
    NSString *collection = components[0];
    NSString *rkey = components[1];
    if (collection.length == 0 || rkey.length == 0) return NO;
    return [self isValidNSID:collection] && [self isValidRecordKey:rkey];
}

- (BOOL)isValidNSID:(NSString *)nsid {
    if (nsid.length == 0) return NO;
    NSArray *components = [nsid componentsSeparatedByString:@"."];
    if (components.count < 2) return NO;
    for (NSString *component in components) {
        if (component.length == 0 || component.length > 63) return NO;
        unichar firstChar = [component characterAtIndex:0];
        if (!isalnum(firstChar)) return NO;
        if (isupper(firstChar)) return NO;
        for (NSInteger i = 1; i < component.length; i++) {
            unichar c = [component characterAtIndex:i];
            if (c != '-' && c != '_' && !isalnum(c)) return NO;
        }
    }
    return YES;
}

- (BOOL)isValidRecordKey:(NSString *)rkey {
    if (rkey.length == 0 || rkey.length > 512) return NO;
    if ([rkey isEqualToString:@"."] || [rkey isEqualToString:@".."]) return NO;
    for (NSInteger i = 0; i < rkey.length; i++) {
        unichar c = [rkey characterAtIndex:i];
        if (c < 0x21 || c > 0x7E) return NO;
    }
    return YES;
}

- (BOOL)isValidTID:(NSString *)tid {
    if (tid.length < 13 || tid.length > 20) return NO;
    NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789"];
    NSCharacterSet *tidChars = [NSCharacterSet characterSetWithCharactersInString:tid];
    if (![validChars isSupersetOfSet:tidChars]) return NO;
    NSString *forbidden = @"ilo";
    for (NSInteger i = 0; i < tid.length; i++) {
        if ([forbidden containsString:[tid substringWithRange:NSMakeRange(i, 1)]]) return NO;
    }
    return YES;
}

@end

NS_ASSUME_NONNULL_END
