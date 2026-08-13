// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file JelczDatabaseTests.m

 @brief Characterization tests for GZJelczDatabase (the SQLite VideoJobStore).

 @discussion GZJelczDatabase shipped with no tests. These pin down its *current*
 observable behaviour through the VideoJobStore interface — the safety net required
 before it can be migrated onto ATProtoDatabaseQueryRunner (and it closes
 architecture-review candidate 10). They capture behaviour exactly as-is, including
 quirks: state / retry updates against a missing job return YES because the UPDATE
 simply matches no rows and still reports SQLITE_DONE (there is no 404 contract, unlike
 ATProtoMediaSQLiteStore's incrementJobRetry).
 */

#import <XCTest/XCTest.h>
#import <sqlite3.h>
#import "Video/JelczDatabase.h"

// Defined (external linkage) in GZJelczDatabase.m; not exported via the header.
extern NSString * const JelczDatabaseErrorDomain;

@interface JelczDatabaseTests : XCTestCase
@property (nonatomic, strong) GZJelczDatabase *db;
@property (nonatomic, copy) NSString *databasePath;
@end

@implementation JelczDatabaseTests

- (void)setUp {
    [super setUp];
    self.databasePath = [NSTemporaryDirectory() stringByAppendingFormat:@"jelcz_test_%@.db", [[NSUUID UUID] UUIDString]];
    NSError *error = nil;
    self.db = [[GZJelczDatabase alloc] initWithDatabasePath:self.databasePath error:&error];
    XCTAssertNotNil(self.db, @"Failed to create JelczDatabase: %@", error);
}

- (void)tearDown {
    [self.db closeDatabase];
    [[NSFileManager defaultManager] removeItemAtPath:self.databasePath error:nil];
    self.db = nil;
    [super tearDown];
}

#pragma mark - Helpers

/// Creates a stock PENDING job with the given id; asserts the create succeeded.
- (void)createJob:(NSString *)jobId {
    NSError *error = nil;
    BOOL ok = [self.db createVideoJobWithId:jobId
                                        did:@"did:plc:tester"
                                    blobCid:@"bafyorig"
                                   mimeType:@"video/mp4"
                                   fileSize:@(12345)
                           serviceAuthToken:@"tok-123"
                                      error:&error];
    XCTAssertTrue(ok, @"create %@: %@", jobId, error);
}

#pragma mark - create / get

- (void)testCreateAndGetRoundTrip {
    [self createJob:@"job-1"];

    NSError *error = nil;
    NSDictionary *job = [self.db getVideoJobById:@"job-1" error:&error];
    XCTAssertNotNil(job, @"get job: %@", error);
    XCTAssertEqualObjects(job[@"job_id"], @"job-1");
    XCTAssertEqualObjects(job[@"did"], @"did:plc:tester");
    XCTAssertEqualObjects(job[@"blob_cid"], @"bafyorig");
    XCTAssertEqualObjects(job[@"mime_type"], @"video/mp4");
    XCTAssertEqualObjects(job[@"file_size"], @(12345));
    XCTAssertEqualObjects(job[@"service_auth_token"], @"tok-123");
    XCTAssertEqualObjects(job[@"state"], @"PENDING");
    XCTAssertEqualObjects(job[@"progress"], @0);
    XCTAssertEqualObjects(job[@"retry_count"], @0);
    // Columns never set on create come back as NSNull, not absent/nil.
    XCTAssertEqualObjects(job[@"message"], [NSNull null]);
    XCTAssertEqualObjects(job[@"width"], [NSNull null]);
    XCTAssertEqualObjects(job[@"processed_blob_cid"], [NSNull null]);
}

- (void)testManifestColumnMigrationPreservesPopulatedRows {
    // Build a pre-Phase-4 schema DB with a populated row, then open via GZJelczDatabase
    // and assert the additive column lands without losing data.
    NSString *legacyPath = [NSTemporaryDirectory() stringByAppendingFormat:@"jelcz_legacy_%@.db",
                            [[NSUUID UUID] UUIDString]];
    sqlite3 *raw = NULL;
    XCTAssertEqual(sqlite3_open(legacyPath.UTF8String, &raw), SQLITE_OK);
    const char *createSQL =
        "CREATE TABLE video_jobs ("
        "job_id TEXT PRIMARY KEY,"
        "did TEXT NOT NULL,"
        "blob_cid TEXT NOT NULL,"
        "original_filename TEXT,"
        "mime_type TEXT,"
        "file_size INTEGER,"
        "duration_seconds INTEGER,"
        "width INTEGER,"
        "height INTEGER,"
        "state TEXT NOT NULL DEFAULT 'PENDING',"
        "progress INTEGER DEFAULT 0,"
        "message TEXT,"
        "error_code TEXT,"
        "error_message TEXT,"
        "thumbnail_blob_cid TEXT,"
        "processed_blob_cid TEXT,"
        "service_auth_token TEXT,"
        "created_at TEXT NOT NULL,"
        "updated_at TEXT NOT NULL,"
        "completed_at TEXT,"
        "expires_at TEXT,"
        "retry_count INTEGER DEFAULT 0"
        ")";
    char *errmsg = NULL;
    XCTAssertEqual(sqlite3_exec(raw, createSQL, NULL, NULL, &errmsg), SQLITE_OK, @"%s", errmsg);
    const char *insertSQL =
        "INSERT INTO video_jobs (job_id, did, blob_cid, mime_type, file_size, state, progress, created_at, updated_at) "
        "VALUES ('legacy-1', 'did:plc:legacy', 'bafylegacy', 'video/mp4', 99, 'PENDING', 0, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')";
    XCTAssertEqual(sqlite3_exec(raw, insertSQL, NULL, NULL, &errmsg), SQLITE_OK, @"%s", errmsg);
    sqlite3_close(raw);

    NSError *error = nil;
    GZJelczDatabase *migrated = [[GZJelczDatabase alloc] initWithDatabasePath:legacyPath error:&error];
    XCTAssertNotNil(migrated, @"%@", error);

    NSDictionary *job = [migrated getVideoJobById:@"legacy-1" error:&error];
    XCTAssertNotNil(job);
    XCTAssertEqualObjects(job[@"did"], @"did:plc:legacy");
    XCTAssertEqualObjects(job[@"blob_cid"], @"bafylegacy");
    XCTAssertEqualObjects(job[@"file_size"], @99);
    XCTAssertEqualObjects(job[@"manifest_blob_cid"], [NSNull null]);

    XCTAssertTrue([migrated updateVideoJobResults:@"legacy-1"
                                 processedBlobCid:@"bafyproc"
                                thumbnailBlobCid:@"bafythumb"
                                 manifestBlobCid:@"bafymanifest"
                                           error:&error], @"%@", error);
    job = [migrated getVideoJobById:@"legacy-1" error:&error];
    XCTAssertEqualObjects(job[@"manifest_blob_cid"], @"bafymanifest");
    XCTAssertEqualObjects(job[@"state"], @"COMPLETED");

    [migrated closeDatabase];
    [[NSFileManager defaultManager] removeItemAtPath:legacyPath error:nil];
}

- (void)testGetNonExistentReturnsNilWithoutError {
    NSError *error = nil;
    NSDictionary *job = [self.db getVideoJobById:@"nope" error:&error];
    XCTAssertNil(job);
    XCTAssertNil(error, @"a missing job is not reported as an error");
}

- (void)testCreateWithNilTokenStoresNull {
    NSError *error = nil;
    BOOL ok = [self.db createVideoJobWithId:@"job-nulltok"
                                        did:@"did:plc:tester"
                                    blobCid:@"bafyorig"
                                   mimeType:@"video/mp4"
                                   fileSize:@(1)
                           serviceAuthToken:nil
                                      error:&error];
    XCTAssertTrue(ok, @"create: %@", error);

    NSDictionary *job = [self.db getVideoJobById:@"job-nulltok" error:&error];
    XCTAssertEqualObjects(job[@"service_auth_token"], [NSNull null]);
}

- (void)testDuplicateJobIdReturnsError {
    [self createJob:@"dup"];

    NSError *error = nil;
    BOOL ok = [self.db createVideoJobWithId:@"dup"
                                        did:@"did:plc:other"
                                    blobCid:@"bafyother"
                                   mimeType:@"video/mp4"
                                   fileSize:@(2)
                           serviceAuthToken:nil
                                      error:&error];
    XCTAssertFalse(ok, @"duplicate primary key fails the insert");
    // Post-migration onto ATProtoDatabaseQueryRunner the constraint is now surfaced —
    // previously the create returned NO but swallowed the error (the old characterization
    // asserted a nil error here).
    XCTAssertEqualObjects(error.domain, JelczDatabaseErrorDomain);
    XCTAssertEqual(error.code, SQLITE_CONSTRAINT);
    // INSERT (not upsert): the rejected duplicate leaves the original row untouched.
    NSDictionary *job = [self.db getVideoJobById:@"dup" error:NULL];
    XCTAssertEqualObjects(job[@"did"], @"did:plc:tester", @"original row preserved");
    XCTAssertEqualObjects(job[@"blob_cid"], @"bafyorig");
}

#pragma mark - state / results / retry

- (void)testUpdateState {
    [self createJob:@"job-s"];

    NSError *error = nil;
    BOOL ok = [self.db updateVideoJobState:@"job-s" state:@"PROCESSING" progress:@(50) message:@"halfway" error:&error];
    XCTAssertTrue(ok, @"update state: %@", error);

    NSDictionary *job = [self.db getVideoJobById:@"job-s" error:&error];
    XCTAssertEqualObjects(job[@"state"], @"PROCESSING");
    XCTAssertEqualObjects(job[@"progress"], @50);
    XCTAssertEqualObjects(job[@"message"], @"halfway");
}

- (void)testUpdateStateOfMissingJobReturnsYes {
    // Characterization: the UPDATE matches no rows but still reports SQLITE_DONE, so a
    // missing job is reported as a successful update and no row is created.
    NSError *error = nil;
    BOOL ok = [self.db updateVideoJobState:@"ghost" state:@"PROCESSING" progress:@(1) message:nil error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil([self.db getVideoJobById:@"ghost" error:&error], @"no row should exist");
}

- (void)testUpdateResultsMarksCompleted {
    [self createJob:@"job-r"];

    NSError *error = nil;
    BOOL ok = [self.db updateVideoJobResults:@"job-r" processedBlobCid:@"bafyproc" thumbnailBlobCid:@"bafythumb" manifestBlobCid:nil error:&error];
    XCTAssertTrue(ok, @"update results: %@", error);

    NSDictionary *job = [self.db getVideoJobById:@"job-r" error:&error];
    XCTAssertEqualObjects(job[@"state"], @"COMPLETED");
    XCTAssertEqualObjects(job[@"progress"], @100);
    XCTAssertEqualObjects(job[@"processed_blob_cid"], @"bafyproc");
    XCTAssertEqualObjects(job[@"thumbnail_blob_cid"], @"bafythumb");
    XCTAssertEqualObjects(job[@"manifest_blob_cid"], [NSNull null]);
}

- (void)testUpdateResultsWithManifestBlobCid {
    [self createJob:@"job-m"];

    NSError *error = nil;
    BOOL ok = [self.db updateVideoJobResults:@"job-m"
                            processedBlobCid:@"bafyproc"
                           thumbnailBlobCid:@"bafythumb"
                            manifestBlobCid:@"bafymanifest"
                                      error:&error];
    XCTAssertTrue(ok, @"update results with manifest: %@", error);

    NSDictionary *job = [self.db getVideoJobById:@"job-m" error:&error];
    XCTAssertEqualObjects(job[@"manifest_blob_cid"], @"bafymanifest");
    XCTAssertEqualObjects(job[@"processed_blob_cid"], @"bafyproc");
}

- (void)testUpdateResultsWithNilCidsStillCompletes {
    [self createJob:@"job-rn"];

    NSError *error = nil;
    BOOL ok = [self.db updateVideoJobResults:@"job-rn" processedBlobCid:nil thumbnailBlobCid:nil manifestBlobCid:nil error:&error];
    XCTAssertTrue(ok, @"update results nil: %@", error);

    NSDictionary *job = [self.db getVideoJobById:@"job-rn" error:&error];
    XCTAssertEqualObjects(job[@"state"], @"COMPLETED");
    XCTAssertEqualObjects(job[@"progress"], @100);
    XCTAssertEqualObjects(job[@"processed_blob_cid"], [NSNull null]);
    XCTAssertEqualObjects(job[@"thumbnail_blob_cid"], [NSNull null]);
    XCTAssertEqualObjects(job[@"manifest_blob_cid"], [NSNull null]);
}

- (void)testIncrementRetryResetsToPendingAndCounts {
    [self createJob:@"job-x"];

    NSError *error = nil;
    XCTAssertTrue([self.db updateVideoJobState:@"job-x" state:@"FAILED" progress:@(0) message:@"boom" error:&error]);

    XCTAssertTrue([self.db incrementVideoJobRetry:@"job-x" error:&error], @"increment: %@", error);
    NSDictionary *job = [self.db getVideoJobById:@"job-x" error:&error];
    XCTAssertEqualObjects(job[@"retry_count"], @1);
    XCTAssertEqualObjects(job[@"state"], @"PENDING", @"increment resets state to PENDING");

    XCTAssertTrue([self.db incrementVideoJobRetry:@"job-x" error:&error]);
    job = [self.db getVideoJobById:@"job-x" error:&error];
    XCTAssertEqualObjects(job[@"retry_count"], @2);
}

- (void)testIncrementRetryOfMissingJobReturnsYes {
    // Characterization: differs from ATProtoMediaSQLiteStore (which returns NO for a
    // missing job). Jelcz's UPDATE matches no rows yet reports SQLITE_DONE -> YES.
    NSError *error = nil;
    XCTAssertTrue([self.db incrementVideoJobRetry:@"ghost" error:&error]);
}

- (void)testUpdateDimensions {
    [self createJob:@"job-d"];

    NSError *error = nil;
    XCTAssertTrue([self.db updateVideoJobDimensions:@"job-d" width:1920 height:1080 error:&error], @"%@", error);

    NSDictionary *job = [self.db getVideoJobById:@"job-d" error:&error];
    XCTAssertEqualObjects(job[@"width"], @1920);
    XCTAssertEqualObjects(job[@"height"], @1080);
}

- (void)testUpdateDuration {
    [self createJob:@"job-t"];

    NSError *error = nil;
    XCTAssertTrue([self.db updateVideoJobDuration:@"job-t" seconds:42 error:&error], @"%@", error);

    NSDictionary *job = [self.db getVideoJobById:@"job-t" error:&error];
    XCTAssertEqualObjects(job[@"duration_seconds"], @42);
}

#pragma mark - queries

- (void)testQueryPendingReturnsOnlyPending {
    [self createJob:@"p1"];
    [self createJob:@"p2"];
    [self createJob:@"p3"];

    NSError *error = nil;
    XCTAssertTrue([self.db updateVideoJobResults:@"p2" processedBlobCid:@"c" thumbnailBlobCid:@"t" manifestBlobCid:nil error:&error]); // -> COMPLETED
    XCTAssertTrue([self.db updateVideoJobState:@"p3" state:@"PROCESSING" progress:@(10) message:nil error:&error]);

    NSArray<NSDictionary *> *pending = [self.db queryPendingJobsWithLimit:10 error:&error];
    XCTAssertEqual(pending.count, 1u);
    XCTAssertEqualObjects(pending.firstObject[@"job_id"], @"p1");
}

- (void)testQueryPendingRespectsLimit {
    [self createJob:@"a"];
    [self createJob:@"b"];
    [self createJob:@"c"];

    NSError *error = nil;
    NSArray<NSDictionary *> *pending = [self.db queryPendingJobsWithLimit:2 error:&error];
    XCTAssertEqual(pending.count, 2u, @"limit is respected");
}

- (void)testQueryPendingEmptyReturnsEmptyArray {
    NSError *error = nil;
    NSArray<NSDictionary *> *pending = [self.db queryPendingJobsWithLimit:10 error:&error];
    XCTAssertNotNil(pending);
    XCTAssertEqual(pending.count, 0u);
}

- (void)testListWithStateFilter {
    [self createJob:@"l1"];
    [self createJob:@"l2"];
    [self createJob:@"l3"];

    NSError *error = nil;
    XCTAssertTrue([self.db updateVideoJobResults:@"l2" processedBlobCid:@"c" thumbnailBlobCid:@"t" manifestBlobCid:nil error:&error]);

    NSArray<NSDictionary *> *pending = [self.db listVideoJobsWithState:@"PENDING" limit:10 offset:0 error:&error];
    XCTAssertEqual(pending.count, 2u);
    NSSet *pendingIds = [NSSet setWithArray:[pending valueForKey:@"job_id"]];
    XCTAssertEqualObjects(pendingIds, ([NSSet setWithArray:@[@"l1", @"l3"]]));

    NSArray<NSDictionary *> *completed = [self.db listVideoJobsWithState:@"COMPLETED" limit:10 offset:0 error:&error];
    XCTAssertEqual(completed.count, 1u);
    XCTAssertEqualObjects(completed.firstObject[@"job_id"], @"l2");
}

- (void)testListWithNilStateReturnsAll {
    [self createJob:@"n1"];
    [self createJob:@"n2"];
    [self createJob:@"n3"];

    NSError *error = nil;
    NSArray<NSDictionary *> *all = [self.db listVideoJobsWithState:nil limit:10 offset:0 error:&error];
    XCTAssertEqual(all.count, 3u);
    NSSet *ids = [NSSet setWithArray:[all valueForKey:@"job_id"]];
    XCTAssertEqualObjects(ids, ([NSSet setWithArray:@[@"n1", @"n2", @"n3"]]));
}

- (void)testListPaginationRespectsLimitAndOffset {
    [self createJob:@"g1"];
    [self createJob:@"g2"];
    [self createJob:@"g3"];

    NSError *error = nil;
    NSArray<NSDictionary *> *page1 = [self.db listVideoJobsWithState:nil limit:2 offset:0 error:&error];
    NSArray<NSDictionary *> *page2 = [self.db listVideoJobsWithState:nil limit:2 offset:2 error:&error];
    XCTAssertEqual(page1.count, 2u);
    XCTAssertEqual(page2.count, 1u);
}

@end
