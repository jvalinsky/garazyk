// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"
#import "Database/ActorStore/ActorStore.h"

@interface CharacterizationTestBase : XCTestCase

@property (nonatomic, strong) PDSDatabase *testDatabase;
@property (nonatomic, strong) PDSActorStore *testActorStore;
@property (nonatomic, strong) NSString *testDatabasePath;

- (void)setupTestData;
- (void)cleanupTestData;

@end
