#import <XCTest/XCTest.h>
#import "Core/NSDateFormatter+ATProto.h"

@interface NSDateFormatterATProtoTests : XCTestCase
@end

@implementation NSDateFormatterATProtoTests

- (void)testDateFromStringParsesZuluWithoutFractionalSeconds {
    NSDate *date = [NSDateFormatter atproto_dateFromString:@"2026-02-26T04:25:53Z"];
    XCTAssertNotNil(date);
}

- (void)testDateFromStringParsesZuluWithFractionalSeconds {
    NSDate *date = [NSDateFormatter atproto_dateFromString:@"2026-02-26T04:25:53.123Z"];
    XCTAssertNotNil(date);
}

- (void)testDateFromStringParsesOffsetWithoutFractionalSeconds {
    NSDate *date = [NSDateFormatter atproto_dateFromString:@"2026-02-26T04:25:53+00:00"];
    XCTAssertNotNil(date);
}

- (void)testDateFromStringParsesOffsetWithFractionalSeconds {
    NSDate *date = [NSDateFormatter atproto_dateFromString:@"2026-02-26T04:25:53.123+00:00"];
    XCTAssertNotNil(date);
}

- (void)testDateFromStringParsesLongFractionalSeconds {
    NSDate *date = [NSDateFormatter atproto_dateFromString:@"2026-02-26T04:25:53.123456789Z"];
    XCTAssertNotNil(date);
}

- (void)testDateFromStringRejectsInvalidString {
    NSDate *date = [NSDateFormatter atproto_dateFromString:@"not-a-datetime"];
    XCTAssertNil(date);
}

@end

