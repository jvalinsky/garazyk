// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "CharacterizationTestBase.h"

@implementation CharacterizationTestBase

- (void)setUp {
    [super setUp];
    [self setupTestData];
}

- (void)tearDown {
    [self cleanupTestData];
    [super tearDown];
}

- (void)setupTestData {
    // Create unique temp file for this test run
    NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
    self.testDatabasePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"test_%@.db", guid]];
    
    // Initialize database
    NSError *error = nil;
    NSURL *dbURL = [NSURL fileURLWithPath:self.testDatabasePath];
    self.testDatabase = [PDSDatabase databaseAtURL:dbURL];
    BOOL success = [self.testDatabase openWithError:&error];
    
    // Using XCTAssert in setUp requires the test to stop if initialization fails
    if (!success) {
        XCTFail(@"Database schema initialization failed: %@", error);
        return;
    }
    
    // Initialize ActorStore
    NSString *testDid = @"did:plc:test";
    self.testActorStore = [PDSActorStore storeWithDid:testDid dbPath:self.testDatabasePath error:&error];
    if (!self.testActorStore) {
        XCTFail(@"Failed to initialize ActorStore: %@", error);
        return;
    }
    
    if (![self.testActorStore openWithError:&error]) {
        XCTFail(@"Failed to open ActorStore: %@", error);
    }
}

- (void)cleanupTestData {
    self.testActorStore = nil;
    self.testDatabase = nil;
    
    if (self.testDatabasePath) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:self.testDatabasePath error:&error];
        if (error) {
            NSLog(@"Failed to cleanup test database at %@: %@", self.testDatabasePath, error);
        }
    }
}

@end
