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

#pragma mark - TID Generation

- (void)testTIDGenerationFormat {
    TID *tid = [TID tid];
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
    TID *previous = [TID tid];

    for (NSUInteger i = 0; i < 256; i++) {
        TID *current = [TID tid];

        XCTAssertEqual([previous compare:current], NSOrderedAscending);
        XCTAssertEqual([previous.stringValue compare:current.stringValue], NSOrderedAscending);

        previous = current;
    }
}

- (void)testTIDUniqueness {
    NSMutableSet<NSString *> *tids = [NSMutableSet setWithCapacity:10000];

    for (NSUInteger i = 0; i < 10000; i++) {
        NSString *tidString = [TID tid].stringValue;
        XCTAssertNotNil(tidString);
        XCTAssertFalse([tids containsObject:tidString], @"Duplicate TID generated at iteration %lu: %@", (unsigned long)i, tidString);
        [tids addObject:tidString];
    }

    XCTAssertEqual(tids.count, 10000U);
}

- (void)testTIDParsing {
    uint64_t timestamp = 1700000000123456ULL;
    TID *original = [TID tidWithTimestamp:timestamp];
    TID *parsed = [TID tidFromString:original.stringValue];

    XCTAssertNotNil(parsed);
    XCTAssertEqual(parsed.timestamp, timestamp);
    XCTAssertEqualObjects(parsed.stringValue, original.stringValue);
}

- (void)testTIDInvalidFormats {
    XCTAssertNil([TID tidFromString:@"3zz2zzzzzzzz"], @"Should reject TIDs that are too short");
    XCTAssertNil([TID tidFromString:@"3zz2zzzzzzzzzz"], @"Should reject TIDs that are too long");
    XCTAssertNil([TID tidFromString:@"3zz2zzzzzzz0z"], @"Should reject TIDs with invalid base32 characters");
}

- (void)testTIDSortOrder {
    TID *earlier = [TID tidWithTimestamp:1700000000123456ULL];
    TID *later = [TID tidWithTimestamp:1700000000123457ULL];

    XCTAssertEqual([earlier compare:later], NSOrderedAscending);
    XCTAssertEqual([earlier.stringValue compare:later.stringValue], NSOrderedAscending);
    XCTAssertEqual([later compare:earlier], NSOrderedDescending);
    XCTAssertEqual([later.stringValue compare:earlier.stringValue], NSOrderedDescending);
}

@end
