// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
// Phase 17 slice 4 (workstream 01 § S10): PDS_FIREHOSE_MAX_PENDING_SENDS and
// PDS_FIREHOSE_MAX_PENDING_BYTES previously parsed with -integerValue, which
// silently returns 0 for a typo'd non-numeric value. These tests assert an
// invalid override is rejected loudly (default kept) rather than becoming 0,
// and that a valid override still applies.
#import <XCTest/XCTest.h>
#import <stdlib.h>
#import "Sync/Firehose/SubscribeReposHandler.h"

@interface SubscribeReposHandler (EnvLimitsTestAccess)
@property (nonatomic, assign) NSUInteger maxPendingSendsPerConnection;
@property (nonatomic, assign) NSUInteger maxPendingBytesPerConnection;
@end

@interface SubscribeReposHandlerEnvLimitsTests : XCTestCase
@end

@implementation SubscribeReposHandlerEnvLimitsTests

- (void)tearDown {
    unsetenv("PDS_FIREHOSE_MAX_PENDING_SENDS");
    unsetenv("PDS_FIREHOSE_MAX_PENDING_BYTES");
    [super tearDown];
}

- (void)testInvalidMaxPendingSendsKeepsDefaultRatherThanZero {
    setenv("PDS_FIREHOSE_MAX_PENDING_SENDS", "not-a-number", 1);

    SubscribeReposHandler *handler = [[SubscribeReposHandler alloc] init];

    XCTAssertGreaterThan(handler.maxPendingSendsPerConnection, (NSUInteger)0,
                          @"a typo'd env override must not silently become 0");
}

- (void)testInvalidMaxPendingBytesKeepsDefaultRatherThanZero {
    setenv("PDS_FIREHOSE_MAX_PENDING_BYTES", "not-a-number", 1);

    SubscribeReposHandler *handler = [[SubscribeReposHandler alloc] init];

    XCTAssertGreaterThan(handler.maxPendingBytesPerConnection, (NSUInteger)0,
                          @"a typo'd env override must not silently become 0");
}

- (void)testZeroMaxPendingSendsRejectedAsInvalid {
    // 0 is syntactically a valid non-negative integer but a nonsensical
    // limit; SubscribeReposParsePositiveIntegerEnv treats it as invalid so
    // it falls back to the default rather than disabling the connection.
    setenv("PDS_FIREHOSE_MAX_PENDING_SENDS", "0", 1);

    SubscribeReposHandler *handler = [[SubscribeReposHandler alloc] init];

    XCTAssertGreaterThan(handler.maxPendingSendsPerConnection, (NSUInteger)0);
}

- (void)testValidMaxPendingSendsOverrideApplies {
    setenv("PDS_FIREHOSE_MAX_PENDING_SENDS", "777", 1);

    SubscribeReposHandler *handler = [[SubscribeReposHandler alloc] init];

    XCTAssertEqual(handler.maxPendingSendsPerConnection, (NSUInteger)777);
}

- (void)testValidMaxPendingBytesOverrideApplies {
    setenv("PDS_FIREHOSE_MAX_PENDING_BYTES", "123456", 1);

    SubscribeReposHandler *handler = [[SubscribeReposHandler alloc] init];

    XCTAssertEqual(handler.maxPendingBytesPerConnection, (NSUInteger)123456);
}

@end
