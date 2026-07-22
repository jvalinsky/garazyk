// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"

@interface PDSDatabaseAdminAuditTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSDatabaseAdminAuditTests

- (void)setUp {
    [super setUp];
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"adminaudit_test_%@", [[NSUUID UUID] UUIDString]]]];
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

#pragma mark - Insert & Query

- (void)testInsertAuditLogEntry {
    NSDictionary *entry = @{
        @"admin_did": @"did:plc:admin1",
        @"action": @"account.takedown",
        @"subject_id": @"did:plc:target1",
        @"details": @"Spam account",
    };

    NSError *error = nil;
    BOOL inserted = [self.database insertAuditLogEntry:entry error:&error];
    XCTAssertTrue(inserted, @"insertAuditLogEntry should succeed");
    XCTAssertNil(error);
}

- (void)testQueryAuditLog {
    NSDictionary *entry = @{
        @"admin_did": @"did:plc:admin2",
        @"action": @"account.suspend",
        @"subject_id": @"did:plc:target2",
        @"details": @"Review pending",
    };
    [self.database insertAuditLogEntry:entry error:nil];

    NSError *error = nil;
    NSArray<NSDictionary *> *results = [self.database queryAuditLog:@{}
                                                             limit:10
                                                            cursor:nil
                                                             error:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(results.count, 1);
}

- (void)testQueryAuditLogFiltered {
    NSDictionary *entry1 = @{
        @"admin_did": @"did:plc:admin3",
        @"action": @"account.takedown",
        @"subject_id": @"did:plc:target3",
    };
    NSDictionary *entry2 = @{
        @"admin_did": @"did:plc:admin3",
        @"action": @"record.delete",
        @"subject_id": @"did:plc:target4",
    };
    [self.database insertAuditLogEntry:entry1 error:nil];
    [self.database insertAuditLogEntry:entry2 error:nil];

    NSError *error = nil;
    NSArray<NSDictionary *> *results = [self.database queryAuditLog:@{@"action": @"account.takedown"}
                                                             limit:10
                                                            cursor:nil
                                                             error:&error];
    XCTAssertNil(error);
    for (NSDictionary *result in results) {
        XCTAssertEqualObjects(result[@"action"], @"account.takedown");
    }
}

#pragma mark - Cleanup

- (void)testDeleteAuditLogsOlderThanDays {
    NSDictionary *entry = @{
        @"admin_did": @"did:plc:admin4",
        @"action": @"config.update",
        @"subject_id": @"pds.mode",
    };
    [self.database insertAuditLogEntry:entry error:nil];

    NSError *error = nil;
    BOOL deleted = [self.database deleteAuditLogsOlderThanDays:0 error:&error];
    XCTAssertTrue(deleted, @"deleteAuditLogsOlderThanDays should succeed");
    XCTAssertNil(error);
}

@end
