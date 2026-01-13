#import <XCTest/XCTest.h>
#import "Identity/ATProtoHandleValidator.h"

@interface ATProtoHandleValidatorTests : XCTestCase
@end

@implementation ATProtoHandleValidatorTests

- (void)testValidHandles {
    NSArray *validHandles = @[
        @"alice.bsky.social",
        @"bob.test",
        @"my-handle.example.com",
        @"h123.v456.test",
        @"a.b.c.d.e.f.g.h.i.j.com",
        @"handle-with-123.example.com"
    ];
    
    for (NSString *handle in validHandles) {
        NSError *error = nil;
        XCTAssertTrue([ATProtoHandleValidator validateHandle:handle error:&error], @"Handle should be valid: %@", handle);
        XCTAssertNil(error, @"Error should be nil for valid handle: %@", handle);
    }
}

- (void)testNormalization {
    NSString *input = @"MixedCase.EXAMPLE.com";
    NSString *expected = @"mixedcase.example.com";
    NSString *result = [ATProtoHandleValidator normalizeHandle:input];
    XCTAssertEqualObjects(result, expected, @"Normalization should lowercase the handle");
}

- (void)testEmptyAndNilHandles {
    NSError *error = nil;
    XCTAssertFalse([ATProtoHandleValidator validateHandle:nil error:&error], @"Nil handle should be invalid");
    XCTAssertEqual(error.code, 1001);
    
    error = nil;
    XCTAssertFalse([ATProtoHandleValidator validateHandle:@"" error:&error], @"Empty handle should be invalid");
    XCTAssertEqual(error.code, 1001);
}

- (void)testHandleTooLong {
    // 254 characters
    NSString *longLabel = [@"" stringByPaddingToLength:60 withString:@"a" startingAtIndex:0];
    NSString *longHandle = [NSString stringWithFormat:@"%@.%@.%@.%@.com", longLabel, longLabel, longLabel, longLabel];
    // This is around 244 + some dots. Let's make it exactly 254.
    NSMutableString *huge = [NSMutableString string];
    for (int i = 0; i < 25; i++) {
        [huge appendString:@"abcdefghij."]; // 11 * 23 = 253. 
    }
    [huge appendString:@"a"]; // 254 chars total? No wait.
    
    NSString *tooLong = [@"" stringByPaddingToLength:254 withString:@"a" startingAtIndex:0];
    // Need at least one dot to not fail on segment count first
    tooLong = [tooLong stringByReplacingCharactersInRange:NSMakeRange(100, 1) withString:@"."];
    
    NSError *error = nil;
    XCTAssertFalse([ATProtoHandleValidator validateHandle:tooLong error:&error], @"Handle > 253 chars should be invalid");
    XCTAssertEqual(error.code, 1002);
}

- (void)testIPv4Addresses {
    NSArray *ips = @[
        @"192.168.1.1",
        @"127.0.0.1",
        @"8.8.8.8",
        @"1.2.3.4"
    ];
    
    for (NSString *ip in ips) {
        NSError *error = nil;
        XCTAssertFalse([ATProtoHandleValidator validateHandle:ip error:&error], @"IPv4 address should be invalid: %@", ip);
        XCTAssertEqual(error.code, 1003);
    }
}

- (void)testSegmentCount {
    NSArray *invalid = @[
        @"alice",
        @"singleword",
        @"com"
    ];
    
    for (NSString *handle in invalid) {
        NSError *error = nil;
        XCTAssertFalse([ATProtoHandleValidator validateHandle:handle error:&error], @"Single segment handle should be invalid: %@", handle);
        XCTAssertEqual(error.code, 1004);
    }
}

- (void)testEmptySegments {
    NSArray *invalid = @[
        @"alice..social",
        @".example.com",
        @"example.com.",
        @"a...b"
    ];
    
    for (NSString *handle in invalid) {
        NSError *error = nil;
        XCTAssertFalse([ATProtoHandleValidator validateHandle:handle error:&error], @"Handle with empty segments should be invalid: %@", handle);
        XCTAssertEqual(error.code, 1005);
    }
}

- (void)testLabelLength {
    NSString *tooLongLabel = [@"" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
    NSString *handle = [NSString stringWithFormat:@"%@.com", tooLongLabel];
    
    NSError *error = nil;
    XCTAssertFalse([ATProtoHandleValidator validateHandle:handle error:&error], @"Label > 63 chars should be invalid");
    XCTAssertEqual(error.code, 1006);
}

- (void)testInvalidCharacters {
    NSArray *invalid = @[
        @"alice_bsky.social",
        @"bob!test.com",
        @"carol@example.com",
        @"dave#123.test",
        @"emoji-😎.com"
    ];
    
    for (NSString *handle in invalid) {
        NSError *error = nil;
        XCTAssertFalse([ATProtoHandleValidator validateHandle:handle error:&error], @"Handle with invalid characters should be invalid: %@", handle);
        XCTAssertEqual(error.code, 1007);
    }
}

- (void)testHyphenPlacement {
    NSArray *invalid = @[
        @"-alice.bsky.social",
        @"alice-.bsky.social",
        @"bob.-test.com",
        @"bob.test-.com"
    ];
    
    for (NSString *handle in invalid) {
        NSError *error = nil;
        XCTAssertFalse([ATProtoHandleValidator validateHandle:handle error:&error], @"Handle with hyphens at start/end of label should be invalid: %@", handle);
        XCTAssertEqual(error.code, 1007);
    }
}

- (void)testNumericTLD {
    NSArray *invalid = @[
        @"example.123",
        @"test.4567"
    ];

    for (NSString *handle in invalid) {
        NSError *error = nil;
        XCTAssertFalse([ATProtoHandleValidator validateHandle:handle error:&error], @"Handle with all-numeric TLD should be invalid: %@", handle);
        XCTAssertEqual(error.code, 1008);
    }

    // Alphanumeric TLD is okay per ATProto spec
    XCTAssertTrue([ATProtoHandleValidator validateHandle:@"example.a123" error:nil]);
}

- (void)testTLDMustStartWithLetter {
    NSError *error = nil;
    
    // All-numeric TLD returns 1008
    XCTAssertFalse([ATProtoHandleValidator validateHandle:@"cn.8" error:&error]);
    XCTAssertEqual(error.code, 1008);
    
    XCTAssertFalse([ATProtoHandleValidator validateHandle:@"john.0" error:&error]);
    XCTAssertEqual(error.code, 1008);
    
    // TLD starting with digit but not all numeric returns 1009
    XCTAssertFalse([ATProtoHandleValidator validateHandle:@"example.1abc" error:&error]);
    XCTAssertEqual(error.code, 1009);
}

- (void)testSpecExampleValidHandles {
    NSArray *valid = @[
        @"jay.bsky.social",
        @"8.cn",
        @"name.t--t",
        @"XX.LCS.MIT.EDU",
        @"a.co",
        @"xn--notarealidn.com",
        @"xn--ls8h.test",
        @"example.t"
    ];

    for (NSString *handle in valid) {
        NSError *error = nil;
        XCTAssertTrue([ATProtoHandleValidator validateHandle:handle error:&error], @"Handle should be valid per spec: %@", handle);
        XCTAssertNil(error, @"Error should be nil for valid handle: %@", error);
    }
}

- (void)testSpecExampleInvalidHandles {
    NSArray *invalid = @[
        @"jo@hn.test",
        @"john..test",
        @"xn--bcher-.tld",
        @"john.0",
        @"cn.8",
        @"www.masełkowski.pl.com",
        @"org",
        @"name.org."
    ];

    for (NSString *handle in invalid) {
        NSError *error = nil;
        XCTAssertFalse([ATProtoHandleValidator validateHandle:handle error:&error], @"Handle should be invalid per spec: %@", handle);
    }
}

- (void)testTLDSingleCharacter {
    NSError *error = nil;
    XCTAssertTrue([ATProtoHandleValidator validateHandle:@"a.b" error:&error], @"Single char TLD should be valid");
    XCTAssertNil(error);
}

- (void)testTLDSingleCharacterInvalid {
    NSError *error = nil;
    XCTAssertFalse([ATProtoHandleValidator validateHandle:@"a.1" error:&error], @"Single char numeric TLD should be invalid");
    XCTAssertEqual(error.code, 1008);
}

- (void)testTLDSingleLetterValid {
    NSError *error = nil;
    XCTAssertTrue([ATProtoHandleValidator validateHandle:@"example.a" error:&error], @"Single letter TLD should be valid");
    XCTAssertNil(error);
}

- (void)testTLDSingleLetterInvalid {
    NSError *error = nil;
    XCTAssertFalse([ATProtoHandleValidator validateHandle:@"example.1" error:&error], @"Single digit TLD should be invalid");
    XCTAssertEqual(error.code, 1008);
}

- (void)testHandleSyntaxMethod {
    XCTAssertTrue([ATProtoHandleValidator validateHandleSyntax:@"alice.bsky.social" error:nil]);

    NSError *error = nil;
    XCTAssertFalse([ATProtoHandleValidator validateHandleSyntax:@"example.123" error:&error], @"Numeric TLD should fail syntax validation");
    XCTAssertEqual(error.code, 1008);
}

- (void)testReservedTLDsSyntaxValid {
    NSError *error = nil;
    XCTAssertTrue([ATProtoHandleValidator validateHandleSyntax:@"test.arpa" error:nil], @"Reserved TLDs should pass syntax validation");
    XCTAssertTrue([ATProtoHandleValidator validateHandleSyntax:@"test.local" error:nil], @"Reserved TLDs should pass syntax validation");
    XCTAssertTrue([ATProtoHandleValidator validateHandleSyntax:@"test.example" error:nil], @"Reserved TLDs should pass syntax validation");
}

@end
