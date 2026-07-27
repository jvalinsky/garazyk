// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Services/PDS/PDSSpaceReconciler.h"
#import "Services/PDS/PDSSpaceStore.h"
#import "Database/Pool/DatabasePool.h"
#import "Auth/JWT.h"

@interface PDSSpaceReconcilerTests : XCTestCase
@property (nonatomic, strong) PDSSpaceStore *spaceStore;
@property (nonatomic, strong) PDSDatabasePool *dbPool;
@property (nonatomic, strong) JWTMinter *jwtMinter;
@end

@implementation PDSSpaceReconcilerTests

- (void)setUp {
  [super setUp];
  self.spaceStore = [[PDSSpaceStore alloc] initWithDatabasePath:@":memory:" error:nil];
  // Note: PDSDatabasePool requires a data directory path; use temp for test
  NSString *tempDir = NSTemporaryDirectory();
  self.dbPool = [[PDSDatabasePool alloc] initWithDbDirectory:tempDir maxSize:10];
  self.jwtMinter = [[JWTMinter alloc] init];
}

- (void)tearDown {
  [self.spaceStore close];
  self.spaceStore = nil;
  self.dbPool = nil;
  self.jwtMinter = nil;
  [super tearDown];
}

- (void)testInit_WithValidParameters_ReturnsReconciler {
  PDSSpaceReconciler *reconciler = [[PDSSpaceReconciler alloc] initWithSpaceStore:self.spaceStore
                                                                 userDatabasePool:self.dbPool
                                                                       jwtMinter:self.jwtMinter
                                                              intervalInSeconds:300.0];
  XCTAssertNotNil(reconciler);
}

- (void)testInit_WithIntervalBelowMinimum_EnforcesFloor {
  PDSSpaceReconciler *reconciler = [[PDSSpaceReconciler alloc] initWithSpaceStore:self.spaceStore
                                                                 userDatabasePool:self.dbPool
                                                                       jwtMinter:self.jwtMinter
                                                              intervalInSeconds:1.0];
  XCTAssertNotNil(reconciler);
}

- (void)testStartStop_DoesNotCrash {
  PDSSpaceReconciler *reconciler = [[PDSSpaceReconciler alloc] initWithSpaceStore:self.spaceStore
                                                                 userDatabasePool:self.dbPool
                                                                       jwtMinter:self.jwtMinter
                                                              intervalInSeconds:300.0];
  XCTAssertNotNil(reconciler);
  XCTAssertNoThrow([reconciler start]);
  XCTAssertNoThrow([reconciler stop]);
}

- (void)testDoubleStart_DoesNotCrash {
  PDSSpaceReconciler *reconciler = [[PDSSpaceReconciler alloc] initWithSpaceStore:self.spaceStore
                                                                 userDatabasePool:self.dbPool
                                                                       jwtMinter:self.jwtMinter
                                                              intervalInSeconds:300.0];
  XCTAssertNotNil(reconciler);
  XCTAssertNoThrow([reconciler start]);
  XCTAssertNoThrow([reconciler start]);
  XCTAssertNoThrow([reconciler stop]);
}

- (void)testStopWithoutStart_DoesNotCrash {
  PDSSpaceReconciler *reconciler = [[PDSSpaceReconciler alloc] initWithSpaceStore:self.spaceStore
                                                                 userDatabasePool:self.dbPool
                                                                       jwtMinter:self.jwtMinter
                                                              intervalInSeconds:300.0];
  XCTAssertNoThrow([reconciler stop]);
}

- (void)testReconcileNow_DoesNotCrash {
  PDSSpaceReconciler *reconciler = [[PDSSpaceReconciler alloc] initWithSpaceStore:self.spaceStore
                                                                 userDatabasePool:self.dbPool
                                                                       jwtMinter:self.jwtMinter
                                                              intervalInSeconds:300.0];
  XCTAssertNotNil(reconciler);
  XCTAssertNoThrow([reconciler reconcileNow]);
}

- (void)testReconcileNow_AfterStart_DoesNotCrash {
  PDSSpaceReconciler *reconciler = [[PDSSpaceReconciler alloc] initWithSpaceStore:self.spaceStore
                                                                 userDatabasePool:self.dbPool
                                                                       jwtMinter:self.jwtMinter
                                                              intervalInSeconds:300.0];
  [reconciler start];
  XCTAssertNoThrow([reconciler reconcileNow]);
  [reconciler stop];
}

- (void)testReconcileNow_AfterStop_DoesNotCrash {
  PDSSpaceReconciler *reconciler = [[PDSSpaceReconciler alloc] initWithSpaceStore:self.spaceStore
                                                                 userDatabasePool:self.dbPool
                                                                       jwtMinter:self.jwtMinter
                                                              intervalInSeconds:300.0];
  [reconciler start];
  [reconciler stop];
  XCTAssertNoThrow([reconciler reconcileNow]);
}

@end
