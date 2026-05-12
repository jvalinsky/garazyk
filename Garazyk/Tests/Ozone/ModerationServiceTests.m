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
    [self.db executeUnsafeRawSQL:@"CREATE TABLE moderation_events (id TEXT PRIMARY KEY, action TEXT NOT NULL, subject_did TEXT NOT NULL, subject_type TEXT NOT NULL, reason TEXT, created_by TEXT NOT NULL, created_at REAL NOT NULL, details_json TEXT)" error:nil];
    [self.db executeUnsafeRawSQL:@"CREATE TABLE moderation_subjects (subject_did TEXT NOT NULL, subject_type TEXT NOT NULL, review_state TEXT NOT NULL, last_event_id TEXT, updated_at REAL NOT NULL, PRIMARY KEY(subject_did, subject_type))" error:nil];
    [self.db executeUnsafeRawSQL:@"CREATE TABLE admin_audit_log (id INTEGER PRIMARY KEY AUTOINCREMENT, admin_did TEXT NOT NULL, action TEXT NOT NULL, subject_type TEXT NOT NULL, subject_id TEXT NOT NULL, details TEXT, created_at REAL NOT NULL)" error:nil];
    
    self.service = [[ModerationService alloc] initWithDatabase:self.db];
}

- (void)tearDown {
    [self.db close];
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

- (void)testEmitEvent {
    NSDictionary *event = @{
        @"$type": @"tools.ozone.moderation.defs#modEventTakedown",
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
        @"$type": @"tools.ozone.moderation.defs#modEventTakedown",
        @"subject": @{@"$type": @"com.atproto.admin.defs#repoRef", @"did": @"did:plc:badactor"}
    };
    NSError *emitError = nil;
    NSDictionary *emitResult = [self.service emitModerationEvent:event createdBy:@"did:plc:admin" error:&emitError];
    XCTAssertNotNil(emitResult, @"Emit should succeed: %@", emitError);
    
    NSError *error = nil;
    NSDictionary *result = [self.service queryModerationStatuses:@{} limit:10 cursor:nil error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    NSArray *statuses = result[@"statuses"];
    XCTAssertGreaterThan(statuses.count, 0);
}

@end
