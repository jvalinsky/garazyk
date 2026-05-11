// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Compat/PlatformShims/Security/SecRandom.h"

@interface Arc4randomTests : XCTestCase
@end

@implementation Arc4randomTests

- (void)testUniformBoundZeroReturnsZero {
    uint32_t result = arc4random_uniform(0);
    XCTAssertEqual(result, 0);
}

- (void)testUniformBoundOneReturnsZero {
    uint32_t result = arc4random_uniform(1);
    XCTAssertEqual(result, 0);
}

- (void)testUniformBoundPowerOfTwo {
    uint32_t bound = 16;
    for (int i = 0; i < 10000; i++) {
        uint32_t result = arc4random_uniform(bound);
        XCTAssertLessThan(result, bound);
    }
}

- (void)testUniformNoBias {
    uint32_t bound = 3;
    int buckets[3] = {0, 0, 0};
    int samples = 100000;

    for (int i = 0; i < samples; i++) {
        uint32_t result = arc4random_uniform(bound);
        buckets[result]++;
    }

    int expected = samples / 3;
    int tolerance = expected / 50;

    for (int i = 0; i < 3; i++) {
        XCTAssertGreaterThanOrEqual(buckets[i], expected - tolerance,
                                   @"Bucket %d has %d samples (expected ~%d)", i, buckets[i], expected);
        XCTAssertLessThanOrEqual(buckets[i], expected + tolerance,
                                @"Bucket %d has %d samples (expected ~%d)", i, buckets[i], expected);
    }
}

- (void)testUniformNoBiasNonPowerOfTwo {
    uint32_t bound = 100;
    int buckets[100];
    memset(buckets, 0, sizeof(buckets));
    int samples = 100000;

    for (int i = 0; i < samples; i++) {
        uint32_t result = arc4random_uniform(bound);
        XCTAssertLessThan(result, bound);
        buckets[result]++;
    }

    int expected = samples / 100;
    int tolerance = expected / 5;

    for (int i = 0; i < 100; i++) {
        XCTAssertGreaterThanOrEqual(buckets[i], expected - tolerance,
                                   @"Bucket %d is out of range", i);
        XCTAssertLessThanOrEqual(buckets[i], expected + tolerance,
                                @"Bucket %d is out of range", i);
    }
}

@end
