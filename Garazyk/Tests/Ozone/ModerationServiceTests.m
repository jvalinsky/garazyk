// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Ozone/Services/ModerationService.h"
#import "Database/PDSDatabase.h"

@interface ModerationServiceTests : XCTestCase
@property (nonatomic, strong) NSString *tempDir;
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, strong) ModerationService *service;
@end

@implementation ModerationServiceTests

- (void)setUp {
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSURL *dbURL = [NSURL fileURLWithPath:[self.tempDir stringByAppendingPathComponent:@"moderation.db"]];
    self.db = [PDSDatabase databaseAtURL:dbURL];
    [self.db openWithError:nil];
    
    // Initialize schema
    [self.db executeRawSQL:@"CREATE TABLE moderation_events (id TEXT PRIMARY KEY, type TEXT, subject TEXT, created_by TEXT, created_at TEXT, details TEXT)" error:nil];
    [self.db executeRawSQL:@"CREATE TABLE moderation_statuses (subject TEXT PRIMARY KEY, status TEXT, last_updated TEXT)" error:nil];
    
    self.service = [[ModerationService alloc] initWithDatabase:self.db];
}

- (void)tearDown {
    [self.db close];
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

- (void)testEmitEvent {
    NSDictionary *event = @{
        @"type": @"tools.ozone.moderation.defs#eventTakedown",
        @"subject": @{@"$type": @"com.atproto.admin.defs#repoRef", @"did": @"did:plc:badactor"}
    };
    NSError *error = nil;
    NSDictionary *result = [self.service emitModerationEvent:event createdBy:@"did:plc:admin" error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertEqualObjects(result[@"createdBy"], @"did:plc:admin");
}

- (void)testQueryStatuses {
    NSDictionary *event = @{
        @"type": @"tools.ozone.moderation.defs#eventTakedown",
        @"subject": @{@"$type": @"com.atproto.admin.defs#repoRef", @"did": @"did:plc:badactor"}
    };
    [self.service emitModerationEvent:event createdBy:@"did:plc:admin" error:nil];
    
    NSError *error = nil;
    NSDictionary *result = [self.service queryModerationStatuses:@{} limit:10 cursor:nil error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    NSArray *statuses = result[@"subjectStatuses"];
    XCTAssertGreaterThan(statuses.count, 0);
}

@end
