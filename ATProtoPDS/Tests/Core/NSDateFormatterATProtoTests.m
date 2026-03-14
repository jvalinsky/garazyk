#import <XCTest/XCTest.h>
#import "Core/NSDateFormatter+ATProto.h"

@interface NSDateFormatterATProtoTests : XCTestCase
@end

@implementation NSDateFormatterATProtoTests

- (void)testDateFromStringParsesZuluWithoutFractionalSeconds {
    NSDate *date = [NSDateFormatter atproto_dateFromString:@"2026-02-26T04:25:53Z"];
    XCTAssertNotNil(date);
    XCTAssertGreaterThan([date timeIntervalSince1970], 0);
}

- (void)testDateFromStringParsesZuluWithFractionalSeconds {
    NSDate *date = [NSDateFormatter atproto_dateFromString:@"2026-02-26T04:25:53.123Z"];
    XCTAssertNotNil(date);
    XCTAssertGreaterThan([date timeIntervalSince1970], 0);
}

- (void)testDateFromStringParsesOffsetWithoutFractionalSeconds {
    NSDate *date = [NSDateFormatter atproto_dateFromString:@"2026-02-26T04:25:53+00:00"];
    XCTAssertNotNil(date);
    XCTAssertGreaterThan([date timeIntervalSince1970], 0);
}

- (void)testDateFromStringParsesOffsetWithFractionalSeconds {
    NSDate *date = [NSDateFormatter atproto_dateFromString:@"2026-02-26T04:25:53.123+00:00"];
    XCTAssertNotNil(date);
    XCTAssertGreaterThan([date timeIntervalSince1970], 0);
}

- (void)testDateFromStringParsesLongFractionalSeconds {
    NSDate *date = [NSDateFormatter atproto_dateFromString:@"2026-02-26T04:25:53.123456789Z"];
    XCTAssertNotNil(date);
    XCTAssertGreaterThan([date timeIntervalSince1970], 0);
}

- (void)testDateFromStringRejectsInvalidString {
    NSDate *date = [NSDateFormatter atproto_dateFromString:@"not-a-datetime"];
    XCTAssertNil(date);
}

- (void)testStringFromDateRoundTrip {
    // Format a known timestamp, parse it back, timestamps must match within 1ms.
    NSDate *original = [NSDate dateWithTimeIntervalSinceReferenceDate:12345678.0];
    NSString *string = [NSDateFormatter atproto_stringFromDate:original];
    XCTAssertNotNil(string, @"atproto_stringFromDate: must return a non-nil string");
    XCTAssertGreaterThan(string.length, (NSUInteger)0);

    NSDate *parsed = [NSDateFormatter atproto_dateFromString:string];
    XCTAssertNotNil(parsed, @"atproto_dateFromString: must parse the formatted string");
    XCTAssertEqualWithAccuracy(parsed.timeIntervalSinceReferenceDate,
                                original.timeIntervalSinceReferenceDate,
                                0.001,
                                @"Round-trip timestamp must be within 1 ms");
}

- (void)testStringFromDateContainsTSeparator {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1700000000.0];
    NSString *str = [NSDateFormatter atproto_stringFromDate:date];
    XCTAssertTrue([str containsString:@"T"],
                  @"ATProto ISO 8601 string must contain the 'T' separator");
}

- (void)testISO8601FormatterIsSameSharedInstance {
    NSDateFormatter *a = [NSDateFormatter atproto_iso8601Formatter];
    NSDateFormatter *b = [NSDateFormatter atproto_iso8601Formatter];
    XCTAssertEqual(a, b, @"atproto_iso8601Formatter must return the same shared instance");
}

@end

