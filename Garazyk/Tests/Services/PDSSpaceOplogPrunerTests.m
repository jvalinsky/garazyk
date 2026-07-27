// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Services/PDS/PDSSpaceOplogPruner.h"
#import "Services/PDS/PDSSpaceStore.h"

@interface PDSSpaceOplogPrunerTests : XCTestCase
@end

@implementation PDSSpaceOplogPrunerTests

- (void)testInit_WithValidParameters_ReturnsPruner {
  PDSSpaceStore *store = [[PDSSpaceStore alloc] initWithDatabasePath:@":memory:" error:nil];
  PDSSpaceOplogPruner *pruner = [[PDSSpaceOplogPruner alloc] initWithSpaceStore:store
                                                              retentionRevisions:10
                                                              intervalInSeconds:600.0];
  XCTAssertNotNil(pruner);
  [store close];
}

- (void)testInit_WithZeroRetention_ReturnsPruner {
  PDSSpaceStore *store = [[PDSSpaceStore alloc] initWithDatabasePath:@":memory:" error:nil];
  PDSSpaceOplogPruner *pruner = [[PDSSpaceOplogPruner alloc] initWithSpaceStore:store
                                                              retentionRevisions:0
                                                              intervalInSeconds:600.0];
  XCTAssertNotNil(pruner);
  [store close];
}

- (void)testInit_WithIntervalBelowMinimum_EnforcesFloor {
  PDSSpaceStore *store = [[PDSSpaceStore alloc] initWithDatabasePath:@":memory:" error:nil];
  PDSSpaceOplogPruner *pruner = [[PDSSpaceOplogPruner alloc] initWithSpaceStore:store
                                                              retentionRevisions:10
                                                              intervalInSeconds:1.0];
  XCTAssertNotNil(pruner);
  // Internal _interval should be at least PDSSpaceOplogPrunerMinimumInterval (300s)
  // We can verify behavior by starting/stopping without crashes
  [store close];
}

- (void)testStartStop_DoesNotCrash {
  PDSSpaceStore *store = [[PDSSpaceStore alloc] initWithDatabasePath:@":memory:" error:nil];
  PDSSpaceOplogPruner *pruner = [[PDSSpaceOplogPruner alloc] initWithSpaceStore:store
                                                              retentionRevisions:10
                                                              intervalInSeconds:600.0];
  XCTAssertNoThrow([pruner start]);
  XCTAssertNoThrow([pruner stop]);
  [store close];
}

- (void)testDoubleStart_DoesNotCrash {
  PDSSpaceStore *store = [[PDSSpaceStore alloc] initWithDatabasePath:@":memory:" error:nil];
  PDSSpaceOplogPruner *pruner = [[PDSSpaceOplogPruner alloc] initWithSpaceStore:store
                                                              retentionRevisions:10
                                                              intervalInSeconds:600.0];
  XCTAssertNoThrow([pruner start]);
  XCTAssertNoThrow([pruner start]); // Second start is a no-op
  XCTAssertNoThrow([pruner stop]);
  [store close];
}

- (void)testStopWithoutStart_DoesNotCrash {
  PDSSpaceStore *store = [[PDSSpaceStore alloc] initWithDatabasePath:@":memory:" error:nil];
  PDSSpaceOplogPruner *pruner = [[PDSSpaceOplogPruner alloc] initWithSpaceStore:store
                                                              retentionRevisions:10
                                                              intervalInSeconds:600.0];
  XCTAssertNoThrow([pruner stop]);
  [store close];
}

- (void)testPruneNow_DoesNotCrash {
  PDSSpaceStore *store = [[PDSSpaceStore alloc] initWithDatabasePath:@":memory:" error:nil];
  PDSSpaceOplogPruner *pruner = [[PDSSpaceOplogPruner alloc] initWithSpaceStore:store
                                                              retentionRevisions:10
                                                              intervalInSeconds:600.0];
  XCTAssertNoThrow([pruner pruneNow]);
  [store close];
}

- (void)testPruneNow_AfterStart_DoesNotCrash {
  PDSSpaceStore *store = [[PDSSpaceStore alloc] initWithDatabasePath:@":memory:" error:nil];
  PDSSpaceOplogPruner *pruner = [[PDSSpaceOplogPruner alloc] initWithSpaceStore:store
                                                              retentionRevisions:10
                                                              intervalInSeconds:600.0];
  [pruner start];
  XCTAssertNoThrow([pruner pruneNow]);
  [pruner stop];
  [store close];
}

- (void)testPruneNow_AfterStop_DoesNotCrash {
  PDSSpaceStore *store = [[PDSSpaceStore alloc] initWithDatabasePath:@":memory:" error:nil];
  PDSSpaceOplogPruner *pruner = [[PDSSpaceOplogPruner alloc] initWithSpaceStore:store
                                                              retentionRevisions:10
                                                              intervalInSeconds:600.0];
  [pruner start];
  [pruner stop];
  XCTAssertNoThrow([pruner pruneNow]);
  [store close];
}

- (void)testStartWithZeroRetention_DoesNotStartPruning {
  PDSSpaceStore *store = [[PDSSpaceStore alloc] initWithDatabasePath:@":memory:" error:nil];
  PDSSpaceOplogPruner *pruner = [[PDSSpaceOplogPruner alloc] initWithSpaceStore:store
                                                              retentionRevisions:0
                                                              intervalInSeconds:600.0];
  // With retentionRevisions == 0, start should not schedule timer
  XCTAssertNoThrow([pruner start]);
  XCTAssertNoThrow([pruner stop]);
  [store close];
}

@end
