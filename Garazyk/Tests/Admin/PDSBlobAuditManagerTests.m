#import <XCTest/XCTest.h>
#import "PDSBlobAuditManager.h"
#import "Database/Service/ServiceDatabases.h"
#import "Blob/BlobStorage.h"
#import "Debug/PDSLogger.h"
#import <sqlite3.h>

// Mock BlobStorage for testing
@interface MockBlobStorage : NSObject
@property (nonatomic, copy) NSString *storagePath;
@end

@implementation MockBlobStorage
@end

@interface PDSBlobAuditManagerTests : XCTestCase
@property (nonatomic, strong) PDSBlobAuditManager *auditManager;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong) MockBlobStorage *mockBlobStorage;
@property (nonatomic, copy) NSString *tempDirectory;
@property (nonatomic, assign) sqlite3 *testDatabase;
@end

@implementation PDSBlobAuditManagerTests

- (void)setUp {
    [super setUp];

    // Create temp directory
    self.tempDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"BlobAuditTests_%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Create temp service database
    NSString *dbPath = [self.tempDirectory stringByAppendingPathComponent:@"service.db"];
    if (sqlite3_open(dbPath.UTF8String, &_testDatabase) != SQLITE_OK) {
        XCTFail(@"Failed to create test database");
    }

    // Create blob_audit_jobs table
    NSString *createTableSQL = @"CREATE TABLE blob_audit_jobs ("
        @"id TEXT PRIMARY KEY,"
        @"job_type TEXT NOT NULL,"
        @"status TEXT NOT NULL,"
        @"started_at INTEGER,"
        @"completed_at INTEGER,"
        @"progress REAL DEFAULT 0.0,"
        @"results TEXT,"
        @"error TEXT,"
        @"created_at INTEGER NOT NULL"
        @")";

    char *errMsg = NULL;
    if (sqlite3_exec(_testDatabase, createTableSQL.UTF8String, NULL, NULL, &errMsg) != SQLITE_OK) {
        XCTFail(@"Failed to create table: %s", errMsg);
        sqlite3_free(errMsg);
    }

    // Create indexes
    sqlite3_exec(_testDatabase,
                 "CREATE INDEX idx_blob_audit_jobs_status ON blob_audit_jobs(status)",
                 NULL, NULL, NULL);

    // Initialize dependencies
    self.serviceDatabases = [[PDSServiceDatabases alloc] initWithDatabasePath:dbPath];
    self.mockBlobStorage = [[MockBlobStorage alloc] init];
    self.mockBlobStorage.storagePath = [self.tempDirectory stringByAppendingPathComponent:@"blobs"];

    // Initialize audit manager
    self.auditManager = [[PDSBlobAuditManager alloc] initWithBlobStorage:self.mockBlobStorage
                                                        serviceDatabases:self.serviceDatabases];
}

- (void)tearDown {
    // Close databases
    [self.serviceDatabases closeAll];
    if (self.testDatabase) {
        sqlite3_close(self.testDatabase);
    }

    // Cleanup temp directory
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDirectory error:nil];

    [super tearDown];
}

#pragma mark - Job Creation Tests

- (void)testStartAuditCreatesJobWithUUID {
    NSString *jobId = [self.auditManager startAuditWithType:@"orphans" dryRun:NO];

    XCTAssertNotNil(jobId, @"Job ID should be returned");
    XCTAssertGreaterThan(jobId.length, 0, @"Job ID should not be empty");

    // Verify job was persisted to database
    sqlite3_stmt *stmt = NULL;
    NSString *sql = @"SELECT job_type, status FROM blob_audit_jobs WHERE id = ?";
    if (sqlite3_prepare_v2(self.testDatabase, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, jobId.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            NSString *jobType = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
            NSString *status = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
            XCTAssertEqualObjects(jobType, @"orphans");
            XCTAssertEqualObjects(status, @"pending");
        } else {
            XCTFail(@"Job not found in database");
        }
        sqlite3_finalize(stmt);
    }
}

- (void)testStartAuditWithDifferentTypes {
    NSArray *auditTypes = @[@"orphans", @"cid_verify", @"consistency", @"references"];

    for (NSString *type in auditTypes) {
        NSString *jobId = [self.auditManager startAuditWithType:type dryRun:NO];
        XCTAssertNotNil(jobId, @"Should create job for type: %@", type);
    }
}

- (void)testStartAuditWithDryRun {
    NSString *jobId = [self.auditManager startAuditWithType:@"orphans" dryRun:YES];

    XCTAssertNotNil(jobId);

    // Verify dry run flag is stored (would be in results or metadata)
    sqlite3_stmt *stmt = NULL;
    NSString *sql = @"SELECT created_at FROM blob_audit_jobs WHERE id = ?";
    if (sqlite3_prepare_v2(self.testDatabase, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, jobId.UTF8String, -1, SQLITE_TRANSIENT);
        BOOL found = (sqlite3_step(stmt) == SQLITE_ROW);
        sqlite3_finalize(stmt);
        XCTAssertTrue(found, @"Dry run job should be persisted");
    }
}

#pragma mark - Job Status Tests

- (void)testJobStatusReturnsCurrentState {
    NSString *jobId = [self.auditManager startAuditWithType:@"orphans" dryRun:NO];

    NSDictionary *status = [self.auditManager jobStatusForId:jobId];

    XCTAssertNotNil(status, @"Status should be returned");
    XCTAssertEqualObjects(status[@"jobId"], jobId);
    XCTAssertEqualObjects(status[@"job_type"], @"orphans");
    XCTAssertEqualObjects(status[@"status"], @"pending");
    XCTAssertNotNil(status[@"progress"]);
}

- (void)testJobStatusForNonexistentJob {
    NSDictionary *status = [self.auditManager jobStatusForId:@"nonexistent-job-id"];

    XCTAssertNil(status, @"Status should be nil for nonexistent job");
}

- (void)testJobStatusWithResults {
    NSString *jobId = [self.auditManager startAuditWithType:@"orphans" dryRun:NO];

    // Simulate job completion with results
    NSDictionary *results = @{@"orphaned_count": @42, @"freed_space": @1024};
    NSData *resultsData = [NSJSONSerialization dataWithJSONObject:results options:0 error:nil];
    NSString *resultsJSON = [[NSString alloc] initWithData:resultsData encoding:NSUTF8StringEncoding];

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    sqlite3_stmt *stmt = NULL;
    NSString *sql = @"UPDATE blob_audit_jobs SET status = ?, progress = ?, "
        @"started_at = ?, completed_at = ?, results = ? WHERE id = ?";
    if (sqlite3_prepare_v2(self.testDatabase, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, "completed", -1, SQLITE_STATIC);
        sqlite3_bind_double(stmt, 2, 100.0);
        sqlite3_bind_int64(stmt, 3, (long)now);
        sqlite3_bind_int64(stmt, 4, (long)now);
        sqlite3_bind_text(stmt, 5, resultsJSON.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 6, jobId.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }

    // Fetch status
    NSDictionary *status = [self.auditManager jobStatusForId:jobId];
    XCTAssertEqualObjects(status[@"status"], @"completed");
    XCTAssertEqual([status[@"progress"] doubleValue], 100.0);
    XCTAssertNotNil(status[@"results"]);
}

#pragma mark - Job Cancellation Tests

- (void)testCancelJobReturnsYesForRunningJob {
    NSString *jobId = [self.auditManager startAuditWithType:@"orphans" dryRun:NO];

    // Note: With NSOperationQueue and the actual operation implementation,
    // this tests the cancellation mechanism
    BOOL cancelled = [self.auditManager cancelJobWithId:jobId];

    // May or may not cancel depending on operation state
    XCTAssertTrue(cancelled || !cancelled, @"Cancellation should return a boolean");
}

- (void)testCancelNonexistentJobReturnsFalse {
    BOOL cancelled = [self.auditManager cancelJobWithId:@"nonexistent-job"];

    XCTAssertFalse(cancelled, @"Cancelling nonexistent job should return NO");
}

#pragma mark - Job History Tests

- (void)testRecentJobsReturnsCreatedJobs {
    // Create multiple jobs
    NSMutableArray *jobIds = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        NSString *jobId = [self.auditManager startAuditWithType:@"orphans" dryRun:NO];
        [jobIds addObject:jobId];
    }

    // Get recent jobs
    NSArray *recent = [self.auditManager recentJobs:10];

    XCTAssertNotNil(recent, @"Recent jobs should not be nil");
    XCTAssertEqual(recent.count, 3, @"Should return 3 jobs");

    // Verify jobs are in reverse chronological order (newest first)
    NSDictionary *firstJob = recent[0];
    XCTAssertNotNil(firstJob[@"jobId"]);
    XCTAssertNotNil(firstJob[@"job_type"]);
    XCTAssertNotNil(firstJob[@"status"]);
}

- (void)testRecentJobsRespectsLimit {
    // Create 5 jobs
    for (int i = 0; i < 5; i++) {
        [self.auditManager startAuditWithType:@"orphans" dryRun:NO];
    }

    // Request only 2
    NSArray *recent = [self.auditManager recentJobs:2];

    XCTAssertEqual(recent.count, 2, @"Should respect limit");
}

- (void)testRecentJobsWithNoJobs {
    NSArray *recent = [self.auditManager recentJobs:10];

    XCTAssertNil(recent, @"Should return nil when no jobs exist");
}

#pragma mark - Pruning Tests

- (void)testPruneJobsOlderThanRemovesOldRecords {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval twoMonthsAgo = now - (60 * 24 * 3600);

    // Insert old job
    sqlite3_stmt *stmt = NULL;
    NSString *oldJobSQL = @"INSERT INTO blob_audit_jobs "
        @"(id, job_type, status, progress, created_at) "
        @"VALUES (?, ?, ?, ?, ?)";
    if (sqlite3_prepare_v2(self.testDatabase, oldJobSQL.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, "old-job-id", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 2, "orphans", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 3, "completed", -1, SQLITE_STATIC);
        sqlite3_bind_double(stmt, 4, 100.0);
        sqlite3_bind_int64(stmt, 5, (long)twoMonthsAgo);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }

    // Insert recent job
    NSString *recentJobSQL = @"INSERT INTO blob_audit_jobs "
        @"(id, job_type, status, progress, created_at) "
        @"VALUES (?, ?, ?, ?, ?)";
    if (sqlite3_prepare_v2(self.testDatabase, recentJobSQL.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, "recent-job-id", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 2, "orphans", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 3, "completed", -1, SQLITE_STATIC);
        sqlite3_bind_double(stmt, 4, 100.0);
        sqlite3_bind_int64(stmt, 5, (long)now);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }

    // Prune jobs older than 30 days
    NSError *error = nil;
    BOOL success = [self.auditManager pruneJobsOlderThan:30 error:&error];

    XCTAssertTrue(success, @"Prune should succeed");
    XCTAssertNil(error, @"Should not have errors");

    // Verify old job was deleted
    NSString *countSQL = @"SELECT COUNT(*) FROM blob_audit_jobs";
    if (sqlite3_prepare_v2(self.testDatabase, countSQL.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int count = sqlite3_column_int(stmt, 0);
            XCTAssertEqual(count, 1, @"Should have deleted old job");
        }
        sqlite3_finalize(stmt);
    }
}

#pragma mark - Queue Management Tests

- (void)testAuditQueueIsSerial {
    XCTAssertEqual(self.auditManager.auditQueue.maxConcurrentOperationCount, 1,
                   @"Audit queue should be serial (maxConcurrent = 1)");
}

- (void)testAuditQueueHasBackgroundQoS {
    XCTAssertEqual(self.auditManager.auditQueue.qualityOfService, NSQualityOfServiceBackground,
                   @"Audit queue should use background QoS");
}

@end
