// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"

@interface PDSDatabaseModerationTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSDatabaseModerationTests

- (void)setUp {
    [super setUp];
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"moderation_test_%@", [[NSUUID UUID] UUIDString]]]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempDirURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    NSURL *dbURL = [self.tempDirURL URLByAppendingPathComponent:@"test.db"];
    self.database = [PDSDatabase databaseAtURL:dbURL];
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Failed to open database: %@", error);
    XCTAssertNil(error);
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempDirURL error:nil];
    [super tearDown];
}

#pragma mark - Takedown

- (void)testTakeDownAndActivateAccount {
    NSString *did = @"did:plc:mod-takedown";

    NSError *error = nil;
    BOOL takenDown = [self.database takeDownAccount:did reason:@"spam" takedownRef:nil error:&error];
    XCTAssertTrue(takenDown, @"takeDownAccount should succeed");
    XCTAssertNil(error);

    BOOL isActive = [self.database isAccountTakedownActive:did error:&error];
    XCTAssertTrue(isActive, @"Account should be in takedown state");
    XCTAssertNil(error);

    BOOL activated = [self.database activateAccount:did error:&error];
    XCTAssertTrue(activated, @"activateAccount should succeed");
    XCTAssertNil(error);

    isActive = [self.database isAccountTakedownActive:did error:&error];
    XCTAssertFalse(isActive, @"Account should no longer be in takedown state");
}

- (void)testDeactivateAndReinstateAccount {
    NSString *did = @"did:plc:mod-deactivate";

    NSError *error = nil;
    BOOL deactivated = [self.database deactivateAccount:did error:&error];
    XCTAssertTrue(deactivated, @"deactivateAccount should succeed");
    XCTAssertNil(error);

    NSString *status = [self.database accountStatusForDid:did error:&error];
    XCTAssertNotNil(status);
    XCTAssertNil(error);

    BOOL reinstated = [self.database reinstateAccount:did error:&error];
    XCTAssertTrue(reinstated, @"reinstateAccount should succeed");
    XCTAssertNil(error);
}

- (void)testIsRecordTakedownActive {
    NSString *uri = @"at://did:plc:recordmod/app.bsky.feed.post/record1";

    NSError *error = nil;
    BOOL isActive = [self.database isRecordTakedownActive:uri error:&error];
    XCTAssertFalse(isActive, @"Record should not be in takedown initially");
    XCTAssertNil(error);
}

#pragma mark - Labels

- (void)testCreateLabel {
    NSDictionary *label = @{
        @"uri": @"at://did:plc:labeluser/app.bsky.feed.post/record1",
        @"src": @"did:plc:modbot",
        @"val": @"spam",
    };

    NSError *error = nil;
    BOOL created = [self.database createLabel:label error:&error];
    XCTAssertTrue(created, @"createLabel should succeed");
    XCTAssertNil(error);
}

- (void)testGetLabelsWithFilters {
    NSDictionary *label = @{
        @"uri": @"at://did:plc:labelfilter/app.bsky.feed.post/rec1",
        @"src": @"did:plc:modbot",
        @"val": @"spam",
    };
    [self.database createLabel:label error:nil];

    NSError *error = nil;
    NSArray<NSDictionary *> *labels = [self.database getLabelsWithPatterns:@[@"at://did:plc:labelfilter/*"]
                                                                 sources:@[@"did:plc:modbot"]
                                                                   limit:10
                                                                  cursor:nil
                                                                   error:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(labels.count, 1);
}

@end
