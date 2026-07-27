// SPDX-License-Identifier: MIT
// ... (standard header omitted for brevity)

#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoMediaSQLiteStore.h"

@interface ATProtoMediaSQLiteStoreTests : XCTestCase
@property (nonatomic, strong) ATProtoMediaSQLiteStore *store;
@property (nonatomic, copy) NSString *dbPath;
@end

@implementation ATProtoMediaSQLiteStoreTests

- (void)setUp
{
    [super setUp];
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"mediacore_tests_%u", arc4random_uniform(1000000)]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.dbPath = [dir stringByAppendingPathComponent:@"test.db"];
    NSError *error = nil;
    self.store = [[ATProtoMediaSQLiteStore alloc] initWithDatabasePath:self.dbPath error:&error];
    if (!self.store) {
        NSLog(@"Failed to create store: %@", error);
    }
}

- (void)tearDown
{
    [self.store closeDatabase];
    NSString *dir = [self.dbPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
    self.store = nil;
    self.dbPath = nil;
    [super tearDown];
}

// MARK: - Init

- (void)testInit_WithValidPath_CreatesStore
{
    XCTAssertNotNil(self.store, @"Store should init with valid path");
}

// MARK: - createJob / getJobById

- (void)testCreateAndGetJob
{
    NSError *error = nil;
    BOOL created = [self.store createJobWithId:@"job-001"
                                           did:@"did:plc:testuser"
                                       blobCid:@"bafkreia123"
                                      mimeType:@"image/jpeg"
                                      fileSize:@(1024)
                              serviceAuthToken:nil
                                         error:&error];
    XCTAssertTrue(created, @"createJob should succeed");
    XCTAssertNil(error);

    NSDictionary *job = [self.store getJobById:@"job-001" error:&error];
    XCTAssertNotNil(job, @"getJob should find the created job");
    XCTAssertNil(error);
    XCTAssertEqualObjects(job[@"job_id"], @"job-001");
    XCTAssertEqualObjects(job[@"did"], @"did:plc:testuser");
    XCTAssertEqualObjects(job[@"blob_cid"], @"bafkreia123");
    XCTAssertEqualObjects(job[@"mime_type"], @"image/jpeg");
    XCTAssertEqualObjects(job[@"file_size"], @(1024));
    XCTAssertEqualObjects(job[@"state"], @"PENDING");
    XCTAssertEqualObjects(job[@"progress"], @(0));
}

- (void)testGetJob_NonExistent_ReturnsNil
{
    NSError *error = nil;
    NSDictionary *job = [self.store getJobById:@"nonexistent" error:&error];
    XCTAssertNil(job, @"Non-existent job should return nil");
}

- (void)testCreateJob_WithServiceAuthToken
{
    NSError *error = nil;
    BOOL created = [self.store createJobWithId:@"job-auth"
                                           did:@"did:plc:authuser"
                                       blobCid:@"bafkreiabc"
                                      mimeType:@"video/mp4"
                                      fileSize:@(2048)
                              serviceAuthToken:@"tok_abc123"
                                         error:&error];
    XCTAssertTrue(created);
    XCTAssertNil(error);

    NSDictionary *job = [self.store getJobById:@"job-auth" error:&error];
    XCTAssertNotNil(job);
    XCTAssertEqualObjects(job[@"service_auth_token"], @"tok_abc123");
}

- (void)testCreateJob_DuplicateId_ReturnsError
{
    NSError *error = nil;
    [self.store createJobWithId:@"dup"
                            did:@"did:plc:a"
                        blobCid:@"cid1"
                       mimeType:@"image/png"
                       fileSize:@(100)
               serviceAuthToken:nil
                          error:&error];

    error = nil;
    BOOL created = [self.store createJobWithId:@"dup"
                                           did:@"did:plc:b"
                                       blobCid:@"cid2"
                                      mimeType:@"image/png"
                                      fileSize:@(200)
                              serviceAuthToken:nil
                                         error:&error];
    XCTAssertFalse(created, @"Duplicate job_id should fail");
    XCTAssertNotNil(error, @"Should set an error on duplicate");
}

// MARK: - updateJobState

- (void)testUpdateJobState
{
    [self.store createJobWithId:@"job-state"
                            did:@"did:plc:test"
                        blobCid:@"cid"
                       mimeType:@"text/plain"
                       fileSize:@(50)
               serviceAuthToken:nil
                          error:nil];

    NSError *error = nil;
    BOOL updated = [self.store updateJobState:@"job-state"
                                        state:ATProtoMediaJobStateProcessing
                                     progress:50
                                      message:@"processing..."
                                        error:&error];
    XCTAssertTrue(updated);
    XCTAssertNil(error);

    NSDictionary *job = [self.store getJobById:@"job-state" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"PROCESSING");
    XCTAssertEqualObjects(job[@"progress"], @(50));
    XCTAssertEqualObjects(job[@"message"], @"processing...");
}

- (void)testUpdateJobState_NonExistent_ReturnsNoRowError
{
    NSError *error = nil;
    BOOL updated = [self.store updateJobState:@"nonexistent"
                                        state:ATProtoMediaJobStateCompleted
                                     progress:100
                                      message:@"done"
                                        error:&error];
    XCTAssertFalse(updated, @"Update non-existent should return NO");
    XCTAssertNotNil(error, @"Should set error on non-existent update");
    XCTAssertEqual(error.code, 404, @"Should be 404 no-row error");
}

- (void)testUpdateJobState_AllStates
{
    [self.store createJobWithId:@"job-all-states"
                            did:@"did:plc:test"
                        blobCid:@"cid"
                       mimeType:@"image/gif"
                       fileSize:@(10)
               serviceAuthToken:nil
                          error:nil];

    ATProtoMediaJobState states[] = {
        ATProtoMediaJobStatePending,
        ATProtoMediaJobStateProcessing,
        ATProtoMediaJobStateCompleted,
        ATProtoMediaJobStateFailed
    };
    NSString *expected[] = {@"PENDING", @"PROCESSING", @"COMPLETED", @"FAILED"};

    for (int i = 0; i < 4; i++) {
        NSError *error = nil;
        XCTAssertTrue([self.store updateJobState:@"job-all-states"
                                           state:states[i]
                                        progress:(NSInteger)(i * 33)
                                         message:expected[i]
                                           error:&error]);
        NSDictionary *job = [self.store getJobById:@"job-all-states" error:nil];
        XCTAssertEqualObjects(job[@"state"], expected[i]);
        XCTAssertEqualObjects(job[@"progress"], @(i * 33));
    }
}

// MARK: - updateJobResults

- (void)testUpdateJobResults
{
    [self.store createJobWithId:@"job-results"
                            did:@"did:plc:test"
                        blobCid:@"cid"
                       mimeType:@"image/jpeg"
                       fileSize:@(100)
               serviceAuthToken:nil
                          error:nil];

    NSDictionary *results = @{@"width": @(1920), @"height": @(1080), @"size": @"large"};
    NSError *error = nil;
    BOOL updated = [self.store updateJobResults:@"job-results" results:results error:&error];
    XCTAssertTrue(updated);
    XCTAssertNil(error);

    NSDictionary *job = [self.store getJobById:@"job-results" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"COMPLETED");
    XCTAssertEqualObjects(job[@"progress"], @(100));
    XCTAssertNotNil(job[@"results_json"]);
}

- (void)testUpdateJobResults_NilResults
{
    [self.store createJobWithId:@"job-nil-results"
                            did:@"did:plc:test"
                        blobCid:@"cid"
                       mimeType:@"image/jpeg"
                       fileSize:@(50)
               serviceAuthToken:nil
                          error:nil];

    NSError *error = nil;
    BOOL updated = [self.store updateJobResults:@"job-nil-results" results:nil error:&error];
    XCTAssertTrue(updated, @"Nil results should still succeed");
    XCTAssertNil(error);
}

// MARK: - incrementJobRetry

- (void)testIncrementJobRetry
{
    [self.store createJobWithId:@"job-retry"
                            did:@"did:plc:test"
                        blobCid:@"cid"
                       mimeType:@"image/png"
                       fileSize:@(200)
               serviceAuthToken:nil
                          error:nil];

    NSError *error = nil;
    BOOL retried = [self.store incrementJobRetry:@"job-retry" error:&error];
    XCTAssertTrue(retried);
    XCTAssertNil(error);

    NSDictionary *job = [self.store getJobById:@"job-retry" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"PENDING", @"Retry resets state to PENDING");
    XCTAssertEqualObjects(job[@"retry_count"], @(1));
    // SQLite NULL columns may be returned as nil or NSNull depending on the query runner
    id errorMsg = job[@"error_message"];
    XCTAssertTrue(errorMsg == nil || errorMsg == [NSNull null],
                  @"error_message should be nil or NSNull after retry");
}

- (void)testIncrementJobRetry_MultipleTimes
{
    [self.store createJobWithId:@"job-multi-retry"
                            did:@"did:plc:test"
                        blobCid:@"cid"
                       mimeType:@"image/jpeg"
                       fileSize:@(100)
               serviceAuthToken:nil
                          error:nil];

    for (int i = 1; i <= 3; i++) {
        NSError *error = nil;
        XCTAssertTrue([self.store incrementJobRetry:@"job-multi-retry" error:&error]);
        NSDictionary *job = [self.store getJobById:@"job-multi-retry" error:nil];
        XCTAssertEqualObjects(job[@"retry_count"], @(i));
    }
}

- (void)testIncrementJobRetry_NonExistent_ReturnsNoRowError
{
    NSError *error = nil;
    BOOL retried = [self.store incrementJobRetry:@"nonexistent" error:&error];
    XCTAssertFalse(retried);
    XCTAssertNotNil(error);
}

// MARK: - queryPendingJobs

- (void)testQueryPendingJobs_ReturnsPendingOrderedByCreatedAt
{
    [self.store createJobWithId:@"job-3" did:@"did:plc:c" blobCid:@"cid3"
                       mimeType:@"image/png" fileSize:@(300) serviceAuthToken:nil error:nil];
    usleep(2000);
    [self.store createJobWithId:@"job-1" did:@"did:plc:a" blobCid:@"cid1"
                       mimeType:@"image/jpeg" fileSize:@(100) serviceAuthToken:nil error:nil];
    usleep(2000);
    [self.store createJobWithId:@"job-2" did:@"did:plc:b" blobCid:@"cid2"
                       mimeType:@"image/gif" fileSize:@(200) serviceAuthToken:nil error:nil];

    [self.store updateJobState:@"job-2" state:ATProtoMediaJobStateProcessing progress:10
                       message:nil error:nil];

    NSError *error = nil;
    NSArray *pending = [self.store queryPendingJobsWithLimit:10 error:&error];
    XCTAssertNotNil(pending);
    XCTAssertNil(error);
    XCTAssertEqual(pending.count, 2, @"Should only return PENDING jobs");
    XCTAssertEqualObjects(pending[0][@"job_id"], @"job-3");
    XCTAssertEqualObjects(pending[1][@"job_id"], @"job-1");
}

- (void)testQueryPendingJobs_WithLimit
{
    for (int i = 0; i < 5; i++) {
        [self.store createJobWithId:[NSString stringWithFormat:@"job-%d", i]
                                did:@"did:plc:test"
                            blobCid:@"cid"
                           mimeType:@"image/jpeg"
                           fileSize:@(100)
                   serviceAuthToken:nil
                              error:nil];
    }

    NSError *error = nil;
    NSArray *pending = [self.store queryPendingJobsWithLimit:3 error:&error];
    XCTAssertEqual(pending.count, 3, @"Should respect limit");
}

- (void)testQueryPendingJobs_NoPending_ReturnsEmpty
{
    NSError *error = nil;
    NSArray *pending = [self.store queryPendingJobsWithLimit:10 error:&error];
    XCTAssertNotNil(pending);
    XCTAssertEqual(pending.count, 0, @"Empty store should return empty array");
}

// MARK: - listJobs

- (void)testListJobs_WithStateFilter
{
    [self.store createJobWithId:@"job-pending" did:@"did:plc:a" blobCid:@"cid"
                       mimeType:@"image/png" fileSize:@(100) serviceAuthToken:nil error:nil];
    [self.store createJobWithId:@"job-failed" did:@"did:plc:b" blobCid:@"cid"
                       mimeType:@"image/jpeg" fileSize:@(200) serviceAuthToken:nil error:nil];
    [self.store updateJobState:@"job-failed" state:ATProtoMediaJobStateFailed
                       progress:0 message:@"error" error:nil];

    NSError *error = nil;
    NSArray *failed = [self.store listJobsWithState:@"FAILED" limit:10 offset:0 error:&error];
    XCTAssertEqual(failed.count, 1);
    XCTAssertEqualObjects(failed[0][@"job_id"], @"job-failed");
}

- (void)testListJobs_NoState_ReturnsAll
{
    [self.store createJobWithId:@"job-a" did:@"did:plc:a" blobCid:@"cid"
                       mimeType:@"image/png" fileSize:@(100) serviceAuthToken:nil error:nil];
    [self.store createJobWithId:@"job-b" did:@"did:plc:b" blobCid:@"cid"
                       mimeType:@"image/jpeg" fileSize:@(200) serviceAuthToken:nil error:nil];

    NSError *error = nil;
    NSArray *all = [self.store listJobsWithState:nil limit:10 offset:0 error:&error];
    XCTAssertEqual(all.count, 2);
}

- (void)testListJobs_WithOffset
{
    for (int i = 0; i < 5; i++) {
        [self.store createJobWithId:[NSString stringWithFormat:@"job-%d", i]
                                did:@"did:plc:test"
                            blobCid:@"cid"
                           mimeType:@"image/jpeg"
                           fileSize:@(100)
                   serviceAuthToken:nil
                              error:nil];
    }

    NSError *error = nil;
    NSArray *page = [self.store listJobsWithState:nil limit:2 offset:2 error:&error];
    XCTAssertEqual(page.count, 2);
}

// MARK: - closeDatabase

- (void)testCloseDatabase_DoesNotCrash
{
    XCTAssertNoThrow([self.store closeDatabase], @"closeDatabase should not throw");
}

- (void)testCloseDatabase_MultipleCalls_DoesNotCrash
{
    XCTAssertNoThrow([self.store closeDatabase]);
    XCTAssertNoThrow([self.store closeDatabase], @"Double close should not crash");
}

@end
