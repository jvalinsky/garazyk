// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/Relay/RelayEventBuffer.h"

@interface RelayEventBufferTests : XCTestCase
@end

@implementation RelayEventBufferTests

- (void)testDefaultRetention {
    RelayEventBuffer *buffer = [[RelayEventBuffer alloc] initWithRetentionHours:72 maxEvents:100000];
    XCTAssertEqual(buffer.retentionSeconds, 259200);
}

- (void)testCustomRetentionWindow {
    RelayEventBuffer *buffer = [[RelayEventBuffer alloc] initWithRetentionHours:24 maxEvents:10000];
    XCTAssertEqual(buffer.retentionSeconds, 86400);
}

- (void)testAddAndRetrieveEvent {
    RelayEventBuffer *buffer = [[RelayEventBuffer alloc] initWithRetentionHours:72 maxEvents:100000];
    NSDictionary *event = @{@"repo": @"did:plc:test", @"commit": @{@"rev": @"3"}};
    [buffer appendEvent:event seq:1 timestamp:[NSDate date]];
    XCTAssertEqual(buffer.eventCount, 1);
}

- (void)testEventOrdering {
    RelayEventBuffer *buffer = [[RelayEventBuffer alloc] initWithRetentionHours:72 maxEvents:100000];
    NSDate *now = [NSDate date];
    [buffer appendEvent:@{@"repo": @"did:plc:a"} seq:1 timestamp:now];
    [buffer appendEvent:@{@"repo": @"did:plc:b"} seq:2 timestamp:now];
    XCTAssertEqual([buffer oldestSequence], 1);
    XCTAssertEqual([buffer newestSequence], 2);
}

- (void)testClearBuffer {
    RelayEventBuffer *buffer = [[RelayEventBuffer alloc] initWithRetentionHours:72 maxEvents:100000];
    [buffer appendEvent:@{@"repo": @"did:plc:test"} seq:1 timestamp:[NSDate date]];
    [buffer clear];
    XCTAssertEqual(buffer.eventCount, 0);
}

@end
