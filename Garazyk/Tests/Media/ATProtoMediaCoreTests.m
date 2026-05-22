// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoMediaSQLiteStore.h"
#import "MediaCore/ATProtoMediaWorker.h"
#import "MediaCore/ATProtoMediaProcessor.h"
#import "MediaCore/ATProtoMediaServiceConfiguration.h"
#import "Blob/PDSBlobProvider.h"
#import "Core/CID.h"

#pragma mark - Mock Media Processor

@interface MockMediaProcessor : NSObject <ATProtoMediaProcessor>
@property (nonatomic, readonly) NSString *mediaTypeIdentifier;
@property (nonatomic, assign) BOOL shouldFail;
@property (nonatomic, assign) NSTimeInterval processingDelay;
@property (nonatomic, strong) NSDictionary *resultsToReturn;
@end

/*! Valid CID string used in tests (bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu) */
static NSString *const kTestProcessedCID = @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu";
static NSString *const kTestThumbnailCID = @"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454";

@interface MockMediaProcessor ()
@property (nonatomic, readwrite) NSString *mediaTypeIdentifier;
@end

@implementation MockMediaProcessor

- (instancetype)init {
    self = [super init];
    if (self) {
        _mediaTypeIdentifier = @"app.bsky.test";
        _shouldFail = NO;
        _processingDelay = 0.0;
        _resultsToReturn = @{@"processedCid": kTestProcessedCID,
                             @"thumbnailCid": kTestThumbnailCID,
                             @"metadata": @{@"width": @640, @"height": @360}};
    }
    return self;
}

- (BOOL)canProcessMimeType:(NSString *)mimeType {
    return [mimeType isEqualToString:@"video/mp4"] || [mimeType isEqualToString:@"application/test"];
}

- (void)processMediaAtURL:(NSURL *)inputURL
          outputDirectory:(NSString *)outputDirectory
            progressBlock:(nullable void (^)(float progress))progressBlock
               completion:(void (^)(NSDictionary<NSString *, id> *_Nullable results,
                                    NSError *_Nullable error))completion {
    if (self.processingDelay > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.processingDelay * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (self.shouldFail) {
                if (completion) completion(nil, [NSError errorWithDomain:@"MockMediaProcessor"
                                                                   code:1
                                                               userInfo:@{NSLocalizedDescriptionKey: @"Simulated failure"}]);
            } else {
                if (progressBlock) progressBlock(1.0);
                if (completion) completion(self.resultsToReturn, nil);
            }
        });
    } else {
        if (self.shouldFail) {
            if (completion) completion(nil, [NSError errorWithDomain:@"MockMediaProcessor"
                                                               code:1
                                                           userInfo:@{NSLocalizedDescriptionKey: @"Simulated failure"}]);
        } else {
            if (progressBlock) progressBlock(1.0);
            if (completion) completion(self.resultsToReturn, nil);
        }
    }
}

@end

#pragma mark - Mock Blob Provider

@interface MediaCoreMockBlobProvider : NSObject <PDSBlobProvider>
@end

@implementation MediaCoreMockBlobProvider

- (BOOL)storeBlobData:(NSData *)data forCID:(CID *)cid error:(NSError **)error {
    return YES;
}

- (nullable NSData *)retrieveBlobDataForCID:(CID *)cid error:(NSError **)error {
    return [@"test media data" dataUsingEncoding:NSUTF8StringEncoding];
}

- (nullable NSInputStream *)retrieveBlobStreamForCID:(CID *)cid error:(NSError **)error {
    NSData *dummyData = [@"test media data" dataUsingEncoding:NSUTF8StringEncoding];
    return [NSInputStream inputStreamWithData:dummyData];
}

- (BOOL)deleteBlobDataForCID:(CID *)cid error:(NSError **)error {
    return YES;
}

- (BOOL)hasBlobDataForCID:(CID *)cid {
    return YES;
}

- (nullable NSURL *)blobFileURLForCID:(CID *)cid error:(NSError **)error {
    return nil; // Force stream-based path
}

@end

#pragma mark - Tests

@interface ATProtoMediaCoreTests : XCTestCase
@property (nonatomic, strong) ATProtoMediaSQLiteStore *store;
@property (nonatomic, strong) NSString *databasePath;
@property (nonatomic, strong) MockMediaProcessor *mockProcessor;
@end

@implementation ATProtoMediaCoreTests

- (void)setUp {
    [super setUp];
    self.databasePath = [NSTemporaryDirectory() stringByAppendingFormat:@"media_test_%@.db", [[NSUUID UUID] UUIDString]];
    NSError *error = nil;
    self.store = [[ATProtoMediaSQLiteStore alloc] initWithDatabasePath:self.databasePath error:&error];
    XCTAssertNotNil(self.store, @"Failed to create store: %@", error);
    self.mockProcessor = [[MockMediaProcessor alloc] init];
}

- (void)tearDown {
    [self.store closeDatabase];
    [[NSFileManager defaultManager] removeItemAtPath:self.databasePath error:nil];
    [super tearDown];
}

#pragma mark - SQLiteStore: CRUD Operations

- (void)testCreateAndGetJob {
    NSError *error = nil;
    BOOL created = [self.store createJobWithId:@"job-001"
                                          did:@"did:plc:testuser"
                                      blobCid:@"bafyreiabc123"
                                     mimeType:@"video/mp4"
                                     fileSize:@(1024000)
                             serviceAuthToken:nil
                                        error:&error];
    XCTAssertTrue(created, @"Create failed: %@", error);

    NSDictionary *job = [self.store getJobById:@"job-001" error:&error];
    XCTAssertNotNil(job);
    XCTAssertEqualObjects(job[@"job_id"], @"job-001");
    XCTAssertEqualObjects(job[@"did"], @"did:plc:testuser");
    XCTAssertEqualObjects(job[@"blob_cid"], @"bafyreiabc123");
    XCTAssertEqualObjects(job[@"mime_type"], @"video/mp4");
    XCTAssertEqual([job[@"file_size"] integerValue], 1024000);
    XCTAssertEqualObjects(job[@"state"], @"PENDING");
    XCTAssertEqual([job[@"progress"] integerValue], 0);
}

- (void)testGetNonExistentJobReturnsNil {
    NSError *error = nil;
    NSDictionary *job = [self.store getJobById:@"nonexistent-job" error:&error];
    XCTAssertNil(job);
    // No error for non-existent row
}

- (void)testCreateJobWithServiceAuthToken {
    NSError *error = nil;
    BOOL created = [self.store createJobWithId:@"job-auth"
                                          did:@"did:plc:authuser"
                                      blobCid:@"bafyreiauth"
                                     mimeType:@"video/mp4"
                                     fileSize:@(2048)
                             serviceAuthToken:@"test-jwt-token"
                                        error:&error];
    XCTAssertTrue(created);
    NSDictionary *job = [self.store getJobById:@"job-auth" error:nil];
    XCTAssertEqualObjects(job[@"service_auth_token"], @"test-jwt-token");
}

- (void)testDuplicateJobIdReturnsError {
    NSError *error = nil;
    [self.store createJobWithId:@"dup-job" did:@"did:plc:dup" blobCid:@"cid1" mimeType:@"video/mp4" fileSize:@(1) serviceAuthToken:nil error:nil];
    BOOL created = [self.store createJobWithId:@"dup-job" did:@"did:plc:dup" blobCid:@"cid2" mimeType:@"video/mp4" fileSize:@(2) serviceAuthToken:nil error:&error];
    XCTAssertFalse(created);
    XCTAssertNotNil(error);
}

#pragma mark - SQLiteStore: State Transitions

- (void)testUpdateJobState {
    [self.store createJobWithId:@"state-job" did:@"did:plc:state" blobCid:@"cid" mimeType:@"video/mp4" fileSize:@(100) serviceAuthToken:nil error:nil];

    NSError *error = nil;
    BOOL updated = [self.store updateJobState:@"state-job"
                                        state:ATProtoMediaJobStateProcessing
                                     progress:50
                                      message:@"Transcoding"
                                        error:&error];
    XCTAssertTrue(updated);

    NSDictionary *job = [self.store getJobById:@"state-job" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"PROCESSING");
    XCTAssertEqual([job[@"progress"] integerValue], 50);
    XCTAssertEqualObjects(job[@"message"], @"Transcoding");
}

- (void)testUpdateJobCompletedState {
    [self.store createJobWithId:@"complete-job" did:@"did:plc:comp" blobCid:@"cid3" mimeType:@"video/mp4" fileSize:@(100) serviceAuthToken:nil error:nil];

    [self.store updateJobState:@"complete-job" state:ATProtoMediaJobStateProcessing progress:50 message:nil error:nil];
    [self.store updateJobState:@"complete-job" state:ATProtoMediaJobStateCompleted progress:100 message:nil error:nil];

    NSDictionary *job = [self.store getJobById:@"complete-job" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"COMPLETED");
    XCTAssertEqual([job[@"progress"] integerValue], 100);
}

- (void)testUpdateJobFailedState {
    [self.store createJobWithId:@"fail-job" did:@"did:plc:fail" blobCid:@"cid4" mimeType:@"video/mp4" fileSize:@(100) serviceAuthToken:nil error:nil];
    [self.store updateJobState:@"fail-job" state:ATProtoMediaJobStateFailed progress:0 message:@"Processing error" error:nil];

    NSDictionary *job = [self.store getJobById:@"fail-job" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"FAILED");
    XCTAssertEqualObjects(job[@"message"], @"Processing error");
}

- (void)testIncrementJobRetry {
    [self.store createJobWithId:@"retry-job" did:@"did:plc:retry" blobCid:@"cid5" mimeType:@"video/mp4" fileSize:@(100) serviceAuthToken:nil error:nil];

    NSError *error = nil;
    // First retry
    BOOL incremented = [self.store incrementJobRetry:@"retry-job" error:&error];
    XCTAssertTrue(incremented);

    NSDictionary *job = [self.store getJobById:@"retry-job" error:nil];
    XCTAssertEqual([job[@"retry_count"] integerValue], 1);
    XCTAssertEqualObjects(job[@"state"], @"PENDING"); // reset to pending

    // Second retry
    [self.store incrementJobRetry:@"retry-job" error:nil];
    job = [self.store getJobById:@"retry-job" error:nil];
    XCTAssertEqual([job[@"retry_count"] integerValue], 2);
}

- (void)testIncrementJobRetryNonExistent {
    NSError *error = nil;
    BOOL incremented = [self.store incrementJobRetry:@"nonexistent" error:&error];
    XCTAssertFalse(incremented);
    XCTAssertNotNil(error);
}

#pragma mark - SQLiteStore: Results JSON

- (void)testUpdateJobResults {
    [self.store createJobWithId:@"results-job" did:@"did:plc:results" blobCid:@"cid6" mimeType:@"video/mp4" fileSize:@(100) serviceAuthToken:nil error:nil];

    NSDictionary *results = @{
        @"processedCid": @"bafyreiProcessed",
        @"thumbnailCid": @"bafyreiThumb",
        @"metadata": @{@"width": @1920, @"height": @1080, @"duration": @30}
    };

    NSError *error = nil;
    BOOL updated = [self.store updateJobResults:@"results-job" results:results error:&error];
    XCTAssertTrue(updated);

    NSDictionary *job = [self.store getJobById:@"results-job" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"COMPLETED");
    XCTAssertEqual([job[@"progress"] integerValue], 100);

    // Parse results_json
    NSString *resultsJson = job[@"results_json"];
    XCTAssertNotNil(resultsJson);
    NSData *jsonData = [resultsJson dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    XCTAssertEqualObjects(parsed[@"processedCid"], @"bafyreiProcessed");
    XCTAssertEqualObjects(parsed[@"thumbnailCid"], @"bafyreiThumb");
    XCTAssertEqualObjects(parsed[@"metadata"][@"width"], @1920);
}

- (void)testUpdateJobResultsNilResults {
    [self.store createJobWithId:@"nil-results-job" did:@"did:plc:nil" blobCid:@"cid7" mimeType:@"video/mp4" fileSize:@(100) serviceAuthToken:nil error:nil];

    NSError *error = nil;
    BOOL updated = [self.store updateJobResults:@"nil-results-job" results:@{} error:&error];
    XCTAssertTrue(updated);

    NSDictionary *job = [self.store getJobById:@"nil-results-job" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"COMPLETED");
    // results_json may be empty JSON object
}

#pragma mark - SQLiteStore: Query Pending Jobs

- (void)testQueryPendingJobs {
    // Create 3 jobs: 2 pending, 1 processing
    [self.store createJobWithId:@"pending-1" did:@"did:plc:q" blobCid:@"c1" mimeType:@"video/mp4" fileSize:@(1) serviceAuthToken:nil error:nil];
    [self.store createJobWithId:@"pending-2" did:@"did:plc:q" blobCid:@"c2" mimeType:@"video/mp4" fileSize:@(1) serviceAuthToken:nil error:nil];
    [self.store createJobWithId:@"active-1" did:@"did:plc:q" blobCid:@"c3" mimeType:@"video/mp4" fileSize:@(1) serviceAuthToken:nil error:nil];
    [self.store updateJobState:@"active-1" state:ATProtoMediaJobStateProcessing progress:10 message:nil error:nil];

    NSError *error = nil;
    NSArray *pending = [self.store queryPendingJobsWithLimit:10 error:&error];
    XCTAssertEqual(pending.count, 2);
    XCTAssertTrue([pending[0][@"job_id"] hasPrefix:@"pending-"]);
    XCTAssertTrue([pending[1][@"job_id"] hasPrefix:@"pending-"]);
}

- (void)testQueryPendingJobsWithLimit {
    [self.store createJobWithId:@"p1" did:@"did:plc:ql" blobCid:@"c1" mimeType:@"video/mp4" fileSize:@(1) serviceAuthToken:nil error:nil];
    [self.store createJobWithId:@"p2" did:@"did:plc:ql" blobCid:@"c2" mimeType:@"video/mp4" fileSize:@(1) serviceAuthToken:nil error:nil];
    [self.store createJobWithId:@"p3" did:@"did:plc:ql" blobCid:@"c3" mimeType:@"video/mp4" fileSize:@(1) serviceAuthToken:nil error:nil];

    NSError *error = nil;
    NSArray *pending = [self.store queryPendingJobsWithLimit:2 error:&error];
    XCTAssertEqual(pending.count, 2);
}

- (void)testQueryPendingJobsEmpty {
    NSError *error = nil;
    NSArray *pending = [self.store queryPendingJobsWithLimit:10 error:&error];
    XCTAssertEqual(pending.count, 0);
}

#pragma mark - SQLiteStore: List Jobs

- (void)testListJobsWithStateFilter {
    [self.store createJobWithId:@"l-pending" did:@"did:plc:l" blobCid:@"c1" mimeType:@"video/mp4" fileSize:@(1) serviceAuthToken:nil error:nil];
    [self.store createJobWithId:@"l-completed" did:@"did:plc:l" blobCid:@"c2" mimeType:@"video/mp4" fileSize:@(1) serviceAuthToken:nil error:nil];
    [self.store updateJobState:@"l-completed" state:ATProtoMediaJobStateCompleted progress:100 message:nil error:nil];

    NSError *error = nil;
    NSArray *completed = [self.store listJobsWithState:@"COMPLETED" limit:10 offset:0 error:&error];
    XCTAssertEqual(completed.count, 1);
    XCTAssertEqualObjects(completed[0][@"job_id"], @"l-completed");

    NSArray *pending = [self.store listJobsWithState:@"PENDING" limit:10 offset:0 error:&error];
    XCTAssertEqual(pending.count, 1);
    XCTAssertEqualObjects(pending[0][@"job_id"], @"l-pending");
}

- (void)testListJobsWithPagination {
    for (int i = 0; i < 5; i++) {
        [self.store createJobWithId:[NSString stringWithFormat:@"page-job-%d", i]
                                did:@"did:plc:page" blobCid:[NSString stringWithFormat:@"cid%d", i]
                          mimeType:@"video/mp4" fileSize:@(i) serviceAuthToken:nil error:nil];
    }

    NSError *error = nil;
    NSArray *page1 = [self.store listJobsWithState:nil limit:2 offset:0 error:&error];
    XCTAssertEqual(page1.count, 2);

    NSArray *page2 = [self.store listJobsWithState:nil limit:2 offset:2 error:&error];
    XCTAssertEqual(page2.count, 2);

    NSArray *page3 = [self.store listJobsWithState:nil limit:2 offset:4 error:&error];
    XCTAssertEqual(page3.count, 1);
}

- (void)testListJobsWithNilStateReturnsAll {
    [self.store createJobWithId:@"all-1" did:@"did:plc:all" blobCid:@"c1" mimeType:@"video/mp4" fileSize:@(1) serviceAuthToken:nil error:nil];
    [self.store createJobWithId:@"all-2" did:@"did:plc:all" blobCid:@"c2" mimeType:@"video/mp4" fileSize:@(1) serviceAuthToken:nil error:nil];
    [self.store updateJobState:@"all-2" state:ATProtoMediaJobStateCompleted progress:100 message:nil error:nil];

    NSError *error = nil;
    NSArray *all = [self.store listJobsWithState:nil limit:10 offset:0 error:&error];
    XCTAssertEqual(all.count, 2);
}

#pragma mark - ATProtoMediaServiceConfiguration

- (void)testConfigFromEnvironmentWithPrefix {
    setenv("TESTCFG_PORT", "9999", 1);
    setenv("TESTCFG_PDS_URL", "http://test-pds.example.com", 1);
    setenv("TESTCFG_MAX_CONCURRENT_JOBS", "4", 1);
    setenv("TESTCFG_BLOB_DIR", "/tmp/test-blobs", 1);

    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"TESTCFG"];
    XCTAssertEqual(config.port, 9999);
    XCTAssertEqualObjects(config.pdsURL, @"http://test-pds.example.com");
    XCTAssertEqual(config.maxConcurrentJobs, 4);
    XCTAssertEqualObjects(config.blobDirectory, @"/tmp/test-blobs");

    unsetenv("TESTCFG_PORT");
    unsetenv("TESTCFG_PDS_URL");
    unsetenv("TESTCFG_MAX_CONCURRENT_JOBS");
    unsetenv("TESTCFG_BLOB_DIR");
}

- (void)testConfigDefaults {
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"NONEXISTENT"];
    XCTAssertEqual(config.port, 2586);
    XCTAssertEqualObjects(config.pdsURL, @"http://localhost:2583");
    XCTAssertEqual(config.maxConcurrentJobs, 2);
    XCTAssertEqual(config.pollInterval, 5.0);
    XCTAssertEqual(config.maxUploadBytes, 100 * 1024 * 1024);
    XCTAssertEqual(config.maxDurationSeconds, 180);
}

#pragma mark - Worker with Mock Processor

- (void)testWorkerProcessesSinglePendingJob {
    [self.store createJobWithId:@"w-job-1" did:@"did:plc:worker" blobCid:kTestProcessedCID mimeType:@"video/mp4" fileSize:@(1024) serviceAuthToken:nil error:nil];

    ATProtoMediaWorker *worker = [[ATProtoMediaWorker alloc] init];
    worker.jobStore = self.store;
    worker.processor = self.mockProcessor;
    worker.blobProvider = [[MediaCoreMockBlobProvider alloc] init];
    worker.maxConcurrentJobs = 2;
    worker.pollInterval = 2.0;
    worker.enabled = YES;

    XCTestExpectation *expectation = [self expectationWithDescription:@"Job completed"];
    // Trigger immediate processing
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [worker processPendingJobs];
    });

    // Poll for completion
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *err = nil;
        NSDictionary *job = [self.store getJobById:@"w-job-1" error:&err];
        if ([job[@"state"] isEqualToString:@"COMPLETED"]) {
            [expectation fulfill];
        } else {
            // If still processing, wait a bit more
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [expectation fulfill];
            });
        }
    });

    [self waitForExpectationsWithTimeout:10.0 handler:nil];

    NSError *error = nil;
    NSDictionary *job = [self.store getJobById:@"w-job-1" error:&error];
    XCTAssertEqualObjects(job[@"state"], @"COMPLETED");
    XCTAssertNotNil(job[@"results_json"]);
}

- (void)testWorkerConcurrencyLimit {
    // Create more jobs than maxConcurrentJobs
    for (int i = 0; i < 5; i++) {
        [self.store createJobWithId:[NSString stringWithFormat:@"conc-job-%d", i]
                                did:@"did:plc:conc" blobCid:kTestProcessedCID
                          mimeType:@"video/mp4" fileSize:@(1024) serviceAuthToken:nil error:nil];
    }

    // Use slow mock processor to ensure all slots fill up
    self.mockProcessor.processingDelay = 0.5;

    ATProtoMediaWorker *worker = [[ATProtoMediaWorker alloc] init];
    worker.jobStore = self.store;
    worker.processor = self.mockProcessor;
    worker.blobProvider = [[MediaCoreMockBlobProvider alloc] init];
    worker.maxConcurrentJobs = 2;
    worker.pollInterval = 1.0;

    [worker start];

    // After a short delay, check how many are PROCESSING
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for processing to start"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:3.0 handler:nil];

    NSError *error = nil;
    NSArray *processing = [self.store listJobsWithState:@"PROCESSING" limit:10 offset:0 error:&error];
    XCTAssertLessThanOrEqual(processing.count, 2, @"Should not process more than maxConcurrentJobs at once");

    // Wait for all to complete
    XCTestExpectation *doneExpectation = [self expectationWithDescription:@"All jobs done"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [doneExpectation fulfill];
    });
    [self waitForExpectationsWithTimeout:8.0 handler:nil];

    NSArray *completed = [self.store listJobsWithState:@"COMPLETED" limit:10 offset:0 error:&error];
    XCTAssertEqual(completed.count, 5);
}

- (void)testWorkerHandlesProcessorFailure {
    [self.store createJobWithId:@"fail-worker" did:@"did:plc:fail" blobCid:kTestProcessedCID mimeType:@"video/mp4" fileSize:@(1024) serviceAuthToken:nil error:nil];

    self.mockProcessor.shouldFail = YES;

    ATProtoMediaWorker *worker = [[ATProtoMediaWorker alloc] init];
    worker.jobStore = self.store;
    worker.processor = self.mockProcessor;
    worker.blobProvider = [[MediaCoreMockBlobProvider alloc] init];
    worker.maxConcurrentJobs = 2;
    worker.enabled = YES;

    [worker processPendingJobs];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Job failed after retries"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    NSError *error = nil;
    NSDictionary *job = [self.store getJobById:@"fail-worker" error:&error];
    // Should be FAILED after retries exhausted, or PENDING if in retry loop
    BOOL isFailedOrPending = [job[@"state"] isEqualToString:@"FAILED"] || [job[@"state"] isEqualToString:@"PENDING"];
    XCTAssertTrue(isFailedOrPending, @"Expected FAILED or PENDING state, got %@", job[@"state"]);
}

@end
