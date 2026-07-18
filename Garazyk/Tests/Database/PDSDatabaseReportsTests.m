// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"

@interface PDSDatabaseReportsTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSDatabaseReportsTests

- (void)setUp {
    [super setUp];
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"reports_test_%@", [[NSUUID UUID] UUIDString]]]];
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

#pragma mark - Create & Get

- (void)testCreateAndGetReport {
    NSDictionary *report = @{
        @"reason_type": @"com.atproto.moderation.defs#reasonSpam",
        @"reason": @"Spam posts",
        @"subject_type": @"record",
        @"subject_uri": @"at://did:plc:reported/app.bsky.feed.post/record1",
        @"reported_by_did": @"did:plc:reporter1",
    };

    NSError *error = nil;
    NSString *reportId = [self.database createReport:report error:&error];
    XCTAssertNotNil(reportId, @"createReport should return a report ID");
    XCTAssertNil(error);

    NSDictionary *fetched = [self.database getReportById:reportId error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(fetched);
    XCTAssertEqualObjects(fetched[@"reason"], @"Spam posts");
}

- (void)testGetReportNotFound {
    NSError *error = nil;
    NSDictionary *fetched = [self.database getReportById:@"nonexistent-report" error:&error];
    XCTAssertNil(fetched, @"Should return nil for nonexistent report");
    XCTAssertNil(error);
}

#pragma mark - List

- (void)testListReports {
    for (int i = 0; i < 3; i++) {
        NSDictionary *report = @{
            @"reason_type": @"com.atproto.moderation.defs#reasonSpam",
            @"reason": [NSString stringWithFormat:@"Report %d", i],
            @"subject_type": @"record",
            @"subject_uri": [NSString stringWithFormat:@"at://did:plc:listreporter/app.bsky.feed.post/rec%d", i],
            @"reported_by_did": @"did:plc:listreporter",
        };
        [self.database createReport:report error:nil];
    }

    NSError *error = nil;
    NSArray<NSDictionary *> *reports = [self.database queryReports:@{}
                                                            limit:10
                                                           cursor:nil
                                                            error:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(reports.count, 3);
}

#pragma mark - Update Status

- (void)testUpdateReportStatus {
    NSDictionary *report = @{
        @"reason_type": @"com.atproto.moderation.defs#reasonSpam",
        @"reason": @"Needs review",
        @"subject_type": @"record",
        @"subject_uri": @"at://did:plc:updatereporter/app.bsky.feed.post/rec1",
        @"reported_by_did": @"did:plc:reporter2",
    };
    NSString *reportId = [self.database createReport:report error:nil];

    NSError *error = nil;
    BOOL updated = [self.database updateReportStatus:reportId
                                              status:@"resolved"
                                         resolvedBy:@"did:plc:admin1"
                                              notes:@"Handled"
                                              error:&error];
    XCTAssertTrue(updated, @"updateReportStatus should succeed");
    XCTAssertNil(error);

    NSDictionary *fetched = [self.database getReportById:reportId error:nil];
    XCTAssertNotNil(fetched);
}

@end
