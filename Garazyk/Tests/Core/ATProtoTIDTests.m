// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Core/TID.h"

@interface ATProtoTIDTests : XCTestCase
@end

@implementation ATProtoTIDTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

#pragma mark - ATProtoTID Generation

- (void)testTIDGenerationFormat {
    ATProtoTID *tid = [ATProtoTID tid];
    XCTAssertNotNil(tid);

    NSString *stringValue = tid.stringValue;
    XCTAssertNotNil(stringValue);
    XCTAssertEqual(stringValue.length, 13U);

    static NSString * const alphabet = @"234567abcdefghijklmnopqrstuvwxyz";
    NSCharacterSet *validCharacters = [NSCharacterSet characterSetWithCharactersInString:alphabet];

    for (NSUInteger i = 0; i < stringValue.length; i++) {
        unichar c = [stringValue characterAtIndex:i];
        XCTAssertTrue([validCharacters characterIsMember:c], @"Unexpected character '%C' at index %lu in %@", c, (unsigned long)i, stringValue);
    }
}

- (void)testTIDMonotonicOrdering {
    ATProtoTID *previous = [ATProtoTID tid];

    for (NSUInteger i = 0; i < 256; i++) {
        ATProtoTID *current = [ATProtoTID tid];

        XCTAssertEqual([previous compare:current], NSOrderedAscending);
        XCTAssertEqual([previous.stringValue compare:current.stringValue], NSOrderedAscending);

        previous = current;
    }
}

- (void)testTIDUniqueness {
    NSMutableSet<NSString *> *tids = [NSMutableSet setWithCapacity:10000];

    for (NSUInteger i = 0; i < 10000; i++) {
        NSString *tidString = [ATProtoTID tid].stringValue;
        XCTAssertNotNil(tidString);
        XCTAssertFalse([tids containsObject:tidString], @"Duplicate ATProtoTID generated at iteration %lu: %@", (unsigned long)i, tidString);
        [tids addObject:tidString];
    }

    XCTAssertEqual(tids.count, 10000U);
}

- (void)testTIDParsing {
    uint64_t timestamp = 1700000000123456ULL;
    ATProtoTID *original = [ATProtoTID tidWithTimestamp:timestamp];
    ATProtoTID *parsed = [ATProtoTID tidFromString:original.stringValue];

    XCTAssertNotNil(parsed);
    XCTAssertEqual(parsed.timestamp, timestamp);
    XCTAssertEqualObjects(parsed.stringValue, original.stringValue);
}

- (void)testTIDInvalidFormats {
    XCTAssertNil([ATProtoTID tidFromString:@"3zz2zzzzzzzz"], @"Should reject TIDs that are too short");
    XCTAssertNil([ATProtoTID tidFromString:@"3zz2zzzzzzzzzz"], @"Should reject TIDs that are too long");
    XCTAssertNil([ATProtoTID tidFromString:@"3zz2zzzzzzz0z"], @"Should reject TIDs with invalid base32 characters");
}

- (void)testTIDSortOrder {
    ATProtoTID *earlier = [ATProtoTID tidWithTimestamp:1700000000123456ULL];
    ATProtoTID *later = [ATProtoTID tidWithTimestamp:1700000000123457ULL];

    XCTAssertEqual([earlier compare:later], NSOrderedAscending);
    XCTAssertEqual([earlier.stringValue compare:later.stringValue], NSOrderedAscending);
    XCTAssertEqual([later compare:earlier], NSOrderedDescending);
    XCTAssertEqual([later.stringValue compare:earlier.stringValue], NSOrderedDescending);
}

@end
