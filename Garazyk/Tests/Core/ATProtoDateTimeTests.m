// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Core/ATProtoValidator.h"
#import "Core/NSDateFormatter+ATProto.h"

@interface ATProtoDateTimeTests : XCTestCase
@end

@implementation ATProtoDateTimeTests

- (void)testDatetimeValidation {
    NSArray *valid = @[
        @"2023-11-23T12:34:56.789Z",
        @"2023-11-23T12:34:56Z",
        @"2023-11-23T12:34:56.12345678901234567890Z", // 20 digits
        @"2023-11-23T12:34:60Z", // Leap second
        @"2023-11-23T12:34:56.789+05:30",
        @"2023-11-23T12:34:56.789-08:00",
        @"0000-01-01T00:00:00Z",
        @"9999-12-31T23:59:59.999Z"
    ];

    for (NSString *dt in valid) {
        NSError *error = nil;
        XCTAssertTrue([ATProtoValidator validateDatetime:dt error:&error], @"Should be valid: %@ (error: %@)", dt, error);
    }

    NSArray *invalid = @[
        @"2023-11-23 12:34:56Z", // Missing T
        @"2023-11-23T12:34:56", // Missing TZ
        @"2023-11-23T12:34:56-00:00", // Prohibited -00:00
        @"2023-13-23T12:34:56Z", // Invalid month
        @"2023-11-32T12:34:56Z", // Invalid day
        @"2023-11-23T24:34:56Z", // Invalid hour
        @"2023-11-23T12:60:56Z", // Invalid minute
        @"2023-11-23T12:34:56.123456789012345678901Z", // 21 digits (too many)
        @"abcd-ef-ghThh:mm:ssZ"
    ];

    for (NSString *dt in invalid) {
        XCTAssertFalse([ATProtoValidator validateDatetime:dt error:nil], @"Should be invalid: %@", dt);
    }
}

- (void)testDateParsing {
    NSString *dt = @"2023-11-23T12:34:56.789Z";
    NSDate *date = [NSDateFormatter atproto_dateFromString:dt];
    XCTAssertNotNil(date);
    
    NSString *output = [NSDateFormatter atproto_stringFromDate:date];
    // Note: fractional seconds might be truncated or rounded depending on implementation, 
    // but basic format should match.
    XCTAssertTrue([output hasPrefix:@"2023-11-23T12:34:56"]);
    XCTAssertTrue([output hasSuffix:@"Z"]);
}

@end
