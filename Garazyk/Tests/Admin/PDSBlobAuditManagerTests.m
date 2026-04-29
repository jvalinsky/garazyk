#import <XCTest/XCTest.h>
#import "Admin/Diagnostics/BlobAudit/PDSBlobAuditManager.h"
#import "Admin/Diagnostics/BlobAudit/PDSBlobOrphanScanOperation.h"
#import "Admin/Diagnostics/BlobAudit/PDSBlobReferenceScanOperation.h"
#import "Blob/BlobStorage.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Core/CID.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStore+Blob.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"

@interface PDSBlobAuditManagerTests : XCTestCase
@property (nonatomic, strong) PDSBlobAuditManager *auditManager;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong) PDSDatabasePool *userDatabasePool;
@property (nonatomic, strong) BlobStorage *blobStorage;
@property (nonatomic, strong) PDSDiskBlobProvider *blobProvider;
@property (nonatomic, copy) NSString *tempDirectory;
@end

@implementation PDSBlobAuditManagerTests

- (void)setUp {
    [super setUp];

    self.tempDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"BlobAuditTests_%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    self.serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:self.tempDirectory
                                                            serviceMaxSize:4
                                                           didCacheMaxSize:2
                                                         sequencerMaxSize:2];

    NSString *userDbDir = [self.tempDirectory stringByAppendingPathComponent:@"users"];
    self.userDatabasePool = [[PDSDatabasePool alloc] initWithDbDirectory:userDbDir maxSize:4];

    NSURL *blobURL = [NSURL fileURLWithPath:[self.tempDirectory stringByAppendingPathComponent:@"blobs"]];
    self.blobProvider = [[PDSDiskBlobProvider alloc] initWithStorageDirectory:blobURL];
    self.blobStorage = [[BlobStorage alloc] initWithDatabasePool:self.userDatabasePool provider:self.blobProvider];
    self.auditManager = [[PDSBlobAuditManager alloc] initWithBlobStorage:self.blobStorage
                                                        serviceDatabases:self.serviceDatabases];
}

- (void)tearDown {
    [self.auditManager.auditQueue cancelAllOperations];
    [self.serviceDatabases closeAll];
    [self.userDatabasePool closeAll];
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDirectory error:nil];
    [super tearDown];
}

- (PDSDatabase *)serviceDB {
    __autoreleasing NSError *error = nil;
    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:&error];
    XCTAssertNotNil(db, @"Failed to open service DB: %@", error);
    return db;
}

- (void)insertJobWithId:(NSString *)jobId
                   type:(NSString *)type
                 status:(NSString *)status
               progress:(double)progress
                results:(NSString *)results
                  error:(NSString *)errorMessage
              createdAt:(NSTimeInterval)createdAt {
    NSString *sql = @"INSERT INTO blob_audit_jobs "
                    @"(id, job_type, status, progress, results, error, created_at) "
                    @"VALUES (?, ?, ?, ?, ?, ?, ?)";
    __autoreleasing NSError *dbError = nil;
    BOOL success = [[self serviceDB] executeParameterizedUpdate:sql
                                                         params:@[
                                                             jobId,
                                                             type,
                                                             status,
                                                             @(progress),
                                                             results ?: [NSNull null],
                                                             errorMessage ?: [NSNull null],
                                                             @(createdAt)
                                                         ]
                                                          error:&dbError];
    XCTAssertTrue(success, @"Failed to insert audit job: %@", dbError);
}

- (NSInteger)jobCount {
    __autoreleasing NSError *error = nil;
    NSArray<NSDictionary *> *rows = [[self serviceDB] executeParameterizedQuery:@"SELECT COUNT(*) AS count FROM blob_audit_jobs"
                                                                         params:@[]
                                                                          error:&error];
    XCTAssertNil(error);
    return [rows.firstObject[@"count"] integerValue];
}

- (void)createServiceAccountWithDid:(NSString *)did handle:(NSString *)handle {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = did;
    account.handle = handle;
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = account.createdAt;

    __autoreleasing NSError *error = nil;
    XCTAssertTrue([self.serviceDatabases createAccount:account error:&error], @"Failed to create service account: %@", error);
}

- (void)testJobStatusHandlesNullableResultAndErrorColumns {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    [self insertJobWithId:@"pending-job" type:@"orphans" status:@"pending" progress:0.0 results:nil error:nil createdAt:now];
    [self insertJobWithId:@"running-job" type:@"references" status:@"running" progress:0.5 results:nil error:nil createdAt:now];
    [self insertJobWithId:@"failed-job" type:@"cid_verify" status:@"failed" progress:1.0 results:nil error:@"boom" createdAt:now];
    [self insertJobWithId:@"completed-job" type:@"consistency" status:@"completed" progress:1.0 results:@"{\"ok\":true}" error:nil createdAt:now];

    NSDictionary *pending = [self.auditManager jobStatusForId:@"pending-job"];
    XCTAssertEqualObjects(pending[@"status"], @"pending");
    XCTAssertNil(pending[@"results"]);
    XCTAssertNil(pending[@"error"]);

    NSDictionary *running = [self.auditManager jobStatusForId:@"running-job"];
    XCTAssertEqualObjects(running[@"status"], @"running");
    XCTAssertNil(running[@"results"]);

    NSDictionary *failed = [self.auditManager jobStatusForId:@"failed-job"];
    XCTAssertEqualObjects(failed[@"error"], @"boom");

    NSDictionary *completed = [self.auditManager jobStatusForId:@"completed-job"];
    NSDictionary *completedResults = completed[@"results"];
    XCTAssertEqualObjects(completedResults[@"ok"], @YES);
}

- (void)testUnsupportedAuditTypeCreatesNoJob {
    NSString *jobId = [self.auditManager startAuditWithType:@"unsupported" dryRun:YES];
    XCTAssertNil(jobId);
    XCTAssertEqual([self jobCount], 0);
}

- (void)testPruneRejectsNegativeDays {
    [self insertJobWithId:@"job" type:@"orphans" status:@"pending" progress:0 results:nil error:nil createdAt:[[NSDate date] timeIntervalSince1970]];

    __autoreleasing NSError *error = nil;
    XCTAssertFalse([self.auditManager pruneJobsOlderThan:-1 error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual([self jobCount], 1);
}

- (void)testPruneUsesUnixEpochCutoff {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    [self insertJobWithId:@"old-job" type:@"orphans" status:@"completed" progress:1 results:@"{}" error:nil createdAt:now - (10 * 24 * 3600)];
    [self insertJobWithId:@"new-job" type:@"orphans" status:@"completed" progress:1 results:@"{}" error:nil createdAt:now];

    __autoreleasing NSError *error = nil;
    XCTAssertTrue([self.auditManager pruneJobsOlderThan:7 error:&error], @"Prune failed: %@", error);
    XCTAssertNil([self.auditManager jobStatusForId:@"old-job"]);
    XCTAssertNotNil([self.auditManager jobStatusForId:@"new-job"]);
}

- (void)testOrphanScanEnumeratesServiceDatabaseAccounts {
    NSString *did = @"did:plc:serviceaccount";
    [self createServiceAccountWithDid:did handle:@"service.example.com"];

    __autoreleasing NSError *uploadError = nil;
    CID *cid = [self.blobStorage uploadBlob:[@"hello" dataUsingEncoding:NSUTF8StringEncoding]
                                   mimeType:@"text/plain"
                                        did:did
                                      error:&uploadError];
    XCTAssertNotNil(cid, @"Upload failed: %@", uploadError);

    [self insertJobWithId:@"orphan-job" type:@"orphans" status:@"pending" progress:0 results:nil error:nil createdAt:[[NSDate date] timeIntervalSince1970]];
    PDSBlobOrphanScanOperation *operation = [[PDSBlobOrphanScanOperation alloc] initWithJobId:@"orphan-job"
                                                                                    auditType:@"orphans"
                                                                                  blobStorage:self.blobStorage
                                                                              serviceDatabases:self.serviceDatabases
                                                                                       dryRun:YES];
    [operation main];

    NSDictionary *status = [self.auditManager jobStatusForId:@"orphan-job"];
    NSDictionary *results = status[@"results"];
    XCTAssertEqual([results[@"totalOrphans"] integerValue], 0);
    NSArray *invalidMetadataCIDs = results[@"invalidMetadataCIDs"];
    XCTAssertEqual(invalidMetadataCIDs.count, 0);
}

- (void)testReferenceScanReportsUnreferencedAndInvalidMetadataCIDs {
    NSString *did = @"did:plc:references";
    [self createServiceAccountWithDid:did handle:@"references.example.com"];

    CID *referencedCID = [CID sha256:[@"referenced" dataUsingEncoding:NSUTF8StringEncoding]];
    CID *unreferencedCID = [CID sha256:[@"unreferenced" dataUsingEncoding:NSUTF8StringEncoding]];

    __autoreleasing NSError *txError = nil;
    [self.userDatabasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        PDSDatabaseBlob *referencedBlob = [[PDSDatabaseBlob alloc] init];
        referencedBlob.cid = [referencedCID bytes];
        referencedBlob.did = did;
        referencedBlob.mimeType = @"text/plain";
        referencedBlob.size = 10;
        referencedBlob.createdAt = [NSDate date];
        XCTAssertTrue([store saveBlob:referencedBlob error:innerError]);

        PDSDatabaseBlob *unreferencedBlob = [[PDSDatabaseBlob alloc] init];
        unreferencedBlob.cid = [unreferencedCID bytes];
        unreferencedBlob.did = did;
        unreferencedBlob.mimeType = @"text/plain";
        unreferencedBlob.size = 10;
        unreferencedBlob.createdAt = [NSDate date];
        XCTAssertTrue([store saveBlob:unreferencedBlob error:innerError]);

        PDSDatabaseBlob *invalidBlob = [[PDSDatabaseBlob alloc] init];
        invalidBlob.cid = [@"not-a-cid" dataUsingEncoding:NSUTF8StringEncoding];
        invalidBlob.did = did;
        invalidBlob.mimeType = @"text/plain";
        invalidBlob.size = 10;
        invalidBlob.createdAt = [NSDate date];
        XCTAssertTrue([store saveBlob:invalidBlob error:innerError]);

        NSDictionary *recordJSON = @{
            @"$type": @"app.bsky.feed.post",
            @"text": @"hello",
            @"embed": @{
                @"$type": @"blob",
                @"ref": @{@"$link": referencedCID.stringValue}
            }
        };
        NSData *recordData = [NSJSONSerialization dataWithJSONObject:recordJSON options:0 error:nil];
        PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
        record.uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/ref", did];
        record.did = did;
        record.collection = @"app.bsky.feed.post";
        record.rkey = @"ref";
        record.cid = [CID sha256:recordData].stringValue;
        record.value = [[NSString alloc] initWithData:recordData encoding:NSUTF8StringEncoding];
        record.createdAt = [NSDate date];
        XCTAssertTrue([transactor putRecord:record forDid:did error:innerError]);
    } error:&txError];
    XCTAssertNil(txError);

    [self insertJobWithId:@"reference-job" type:@"references" status:@"pending" progress:0 results:nil error:nil createdAt:[[NSDate date] timeIntervalSince1970]];
    PDSBlobReferenceScanOperation *operation = [[PDSBlobReferenceScanOperation alloc] initWithJobId:@"reference-job"
                                                                                          auditType:@"references"
                                                                                        blobStorage:self.blobStorage
                                                                                    serviceDatabases:self.serviceDatabases
                                                                                             dryRun:YES];
    [operation main];

    NSDictionary *status = [self.auditManager jobStatusForId:@"reference-job"];
    NSDictionary *results = status[@"results"];
    XCTAssertEqual([results[@"totalUnreferenced"] integerValue], 1);
    NSArray *unreferencedBlobs = results[@"unreferencedBlobs"];
    NSDictionary *firstUnreferenced = unreferencedBlobs.firstObject;
    XCTAssertEqualObjects(firstUnreferenced[@"cid"], unreferencedCID.stringValue);
    NSArray *invalidMetadataCIDs = results[@"invalidMetadataCIDs"];
    XCTAssertEqual(invalidMetadataCIDs.count, 1);
}

@end
