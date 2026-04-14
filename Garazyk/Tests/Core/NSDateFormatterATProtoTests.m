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

@end

