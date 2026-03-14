// Tests for TID: ATProto Timestamp Identifier (base32-sortable, 13 chars).

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Core/TID.h"

@interface TIDTests : XCTestCase
@end

@implementation TIDTests

- (void)testTIDIsThirteenCharacters {
    TID *tid = [TID tid];
    XCTAssertNotNil(tid);
    XCTAssertEqual(tid.stringValue.length, (NSUInteger)13,
                   @"TID must be exactly 13 characters, got: %@", tid.stringValue);
}

- (void)testTIDUsesBase32SortableAlphabet {
    // ATProto TID alphabet: 234567abcdefghijklmnopqrstuvwxyz
    NSString *alphabet = @"234567abcdefghijklmnopqrstuvwxyz";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:alphabet];
    NSCharacterSet *disallowed = [allowed invertedSet];

    for (NSUInteger i = 0; i < 20; i++) {
        TID *tid = [TID tid];
        NSRange bad = [tid.stringValue rangeOfCharacterFromSet:disallowed];
        XCTAssertEqual(bad.location, NSNotFound,
                       @"TID '%@' contains character outside base32-sortable alphabet", tid.stringValue);
    }
}

- (void)testTIDsAreMonotonicallyNonDecreasing {
    // Generate a burst of TIDs and verify lexicographic ordering
    TID *prev = [TID tid];
    for (NSUInteger i = 0; i < 50; i++) {
        TID *next = [TID tid];
        NSComparisonResult cmp = [prev.stringValue compare:next.stringValue];
        XCTAssertTrue(cmp == NSOrderedAscending || cmp == NSOrderedSame,
                      @"TIDs must be non-decreasing: '%@' vs '%@'",
                      prev.stringValue, next.stringValue);
        prev = next;
    }
}

- (void)testTIDWithKnownTimestampProduces13Chars {
    // 1700000000000000 µs (arbitrary fixed timestamp)
    TID *tid = [TID tidWithTimestamp:1700000000000000ULL];
    XCTAssertNotNil(tid);
    XCTAssertEqual(tid.stringValue.length, (NSUInteger)13);
}

- (void)testTIDFromStringRoundTrip {
    TID *original = [TID tid];
    TID *parsed = [TID tidFromString:original.stringValue];
    XCTAssertNotNil(parsed, @"tidFromString: must parse a valid TID string");
    XCTAssertEqualObjects(parsed.stringValue, original.stringValue,
                          @"Round-trip must preserve TID string value");
}

- (void)testTIDFromStringRejectsInvalidInput {
    XCTAssertNil([TID tidFromString:@"tooshort"]);
    XCTAssertNil([TID tidFromString:@""]);
    XCTAssertNil([TID tidFromString:@"!invalid!!!!!!!"]);
}

- (void)testTIDWithDateProduces13Chars {
    TID *tid = [TID tidWithDate:[NSDate date]];
    XCTAssertNotNil(tid);
    XCTAssertEqual(tid.stringValue.length, (NSUInteger)13);
}

- (void)testTIDUniqueness {
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSUInteger i = 0; i < 200; i++) {
        [seen addObject:[TID tid].stringValue];
    }
    XCTAssertEqual(seen.count, (NSUInteger)200, @"200 consecutive TIDs must all be unique");
}

- (void)testTIDIsBeforeAndIsAfter {
    TID *a = [TID tid];
    TID *b = [TID tid];
    if (![a.stringValue isEqualToString:b.stringValue]) {
        XCTAssertTrue([a isBefore:b] || [a.stringValue compare:b.stringValue] == NSOrderedSame);
        XCTAssertTrue([b isAfter:a]  || [a.stringValue compare:b.stringValue] == NSOrderedSame);
    }
}

@end
