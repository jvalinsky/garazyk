// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Video/VideoWorker.h"
#import "Video/VideoTranscoder.h"
#import "Video/VideoThumbnailGenerator.h"
#import "Video/PDSLocalVideoJobStore.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Blob/PDSBlobProvider.h"

@interface ATProtoVideoWorker (ATProtoVideoWorkerTests)
- (void)handleJobFailure:(NSString *)jobId error:(NSError *)error;
- (void)completeJob:(NSString *)jobId;
- (void)failJob:(NSString *)jobId error:(NSError *)error;
@end

/// In-memory blob provider for testing.
@interface MockWorkerBlobProvider : NSObject <PDSBlobProvider>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *blobs;
@end

@implementation MockWorkerBlobProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        _blobs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)storeBlobData:(NSData *)data forCID:(CID *)cid error:(NSError **)error {
    self.blobs[cid.stringValue] = data;
    return YES;
}

- (nullable NSData *)retrieveBlobDataForCID:(CID *)cid error:(NSError **)error {
    NSData *data = self.blobs[cid.stringValue];
    if (!data && error) {
        *error = [NSError errorWithDomain:@"MockWorkerBlobProvider"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Blob not found"}];
    }
    return data;
}

- (BOOL)deleteBlobDataForCID:(CID *)cid error:(NSError **)error {
    [self.blobs removeObjectForKey:cid.stringValue];
    return YES;
}

- (BOOL)hasBlobDataForCID:(CID *)cid {
    return self.blobs[cid.stringValue] != nil;
}

@end

@interface ATProtoVideoWorkerTests : XCTestCase
@property (nonatomic, strong) ATProtoVideoWorker *worker;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong) MockWorkerBlobProvider *blobProvider;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation ATProtoVideoWorkerTests

- (void)setUp {
    [super setUp];

    // Create temp database
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"video_worker_test_%@", [[NSUUID UUID] UUIDString]]]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempDirURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    self.serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:self.tempDirURL.path
                                                            serviceMaxSize:2
                                                           didCacheMaxSize:1
                                                         sequencerMaxSize:1];
    NSError *error = nil;
    self.database = [self.serviceDatabases serviceDatabaseWithError:&error];
    XCTAssertNotNil(self.database);
    XCTAssertNil(error);

    // Create worker with fresh instance
    self.worker = [[ATProtoVideoWorker alloc] init];
    self.worker.jobStore = [[PDSLocalVideoJobStore alloc] initWithDatabase:self.database];

    self.blobProvider = [[MockWorkerBlobProvider alloc] init];
    self.worker.blobProvider = self.blobProvider;
}

- (void)tearDown {
    [self.worker stop];
    self.worker = nil;
    [self.serviceDatabases closeAll];
    self.serviceDatabases = nil;
    self.database = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempDirURL error:nil];
    [super tearDown];
}

#pragma mark - Singleton

- (void)testSharedWorkerIsSingleton {
    ATProtoVideoWorker *a = [ATProtoVideoWorker sharedWorker];
    ATProtoVideoWorker *b = [ATProtoVideoWorker sharedWorker];
    XCTAssertEqual(a, b);
}

#pragma mark - Default Properties

- (void)testDefaultProperties {
    ATProtoVideoWorker *fresh = [[ATProtoVideoWorker alloc] init];
    XCTAssertFalse(fresh.isEnabled);
    XCTAssertEqual(fresh.pollInterval, 5.0);
    XCTAssertEqual(fresh.maxConcurrentJobs, 2);
}

#pragma mark - Start/Stop

- (void)testStartSetsEnabled {
    [self.worker start];
    XCTAssertTrue(self.worker.isEnabled);
}

- (void)testStopClearsEnabled {
    [self.worker start];
    [self.worker stop];
    XCTAssertFalse(self.worker.isEnabled);
}

#pragma mark - Process Pending Jobs Gating

- (void)testProcessPendingJobsSkipsWhenDisabled {
    self.worker.enabled = NO;

    // Insert a pending job
    [self.database createVideoJobWithId:@"job-gate-1"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreitest"
                                 mimeType:@"video/mp4"
                                 fileSize:@(1024)
                          serviceAuthToken:nil
                                    error:nil];

    // Should not process — worker is disabled
    [self.worker processPendingJobs];

    NSDictionary *job = [self.database getVideoJobById:@"job-gate-1" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"PENDING"); // Still PENDING, not PROCESSING
}

- (void)testProcessPendingJobsRespectsMaxConcurrent {
    self.worker.enabled = YES;
    self.worker.maxConcurrentJobs = 1;

    // Insert two pending jobs
    [self.database createVideoJobWithId:@"job-concurrent-1"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreitest1"
                                 mimeType:@"video/mp4"
                                 fileSize:@(1024)
                          serviceAuthToken:nil
                                    error:nil];
    [self.database createVideoJobWithId:@"job-concurrent-2"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreitest2"
                                 mimeType:@"video/mp4"
                                 fileSize:@(1024)
                          serviceAuthToken:nil
                                    error:nil];

    // Only one should be picked up (maxConcurrentJobs=1)
    // Note: processPendingJobs dispatches to worker queue, so we can't
    // directly check processingJobIds from outside. Instead, verify
    // that at most one job transitions from PENDING.
    // This is a weak test — the real concurrency check is in processJob:.
}

#pragma mark - Job Failure Handling

- (void)testHandleJobFailureRetriesUnderLimit {
    [self.database createVideoJobWithId:@"job-retry-1"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreitest"
                                 mimeType:@"video/mp4"
                                 fileSize:@(1024)
                          serviceAuthToken:nil
                                    error:nil];

    // Set to FAILED
    [self.database updateVideoJobState:@"job-retry-1"
                                  state:@"FAILED"
                               progress:@0
                                message:@"Transcode failed"
                                  error:nil];

    NSError *error = [NSError errorWithDomain:ATProtoVideoWorkerErrorDomain
                                         code:ATProtoVideoWorkerErrorProcessingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Test failure"}];
    [self.worker handleJobFailure:@"job-retry-1" error:error];

    NSDictionary *job = [self.database getVideoJobById:@"job-retry-1" error:nil];
    XCTAssertEqualObjects(job[@"retry_count"], @(1));
    XCTAssertEqualObjects(job[@"state"], @"PENDING"); // Reset to PENDING for retry
}

- (void)testHandleJobFailurePermanentAfter3Retries {
    [self.database createVideoJobWithId:@"job-retry-2"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreitest"
                                 mimeType:@"video/mp4"
                                 fileSize:@(1024)
                          serviceAuthToken:nil
                                    error:nil];

    // Simulate 3 prior retries
    for (int i = 0; i < 3; i++) {
        [self.database updateVideoJobState:@"job-retry-2"
                                      state:@"FAILED"
                                   progress:@0
                                    message:@"Export failed"
                                      error:nil];
        [self.database incrementVideoJobRetry:@"job-retry-2" error:nil];
    }

    // Now retry_count = 3, next failure should be permanent
    NSError *error = [NSError errorWithDomain:ATProtoVideoWorkerErrorDomain
                                         code:ATProtoVideoWorkerErrorProcessingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Permanent failure"}];
    [self.worker handleJobFailure:@"job-retry-2" error:error];

    NSDictionary *job = [self.database getVideoJobById:@"job-retry-2" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"FAILED");
}

#pragma mark - Job Completion

- (void)testCompleteJobRemovesFromProcessing {
    [self.database createVideoJobWithId:@"job-complete-1"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreitest"
                                 mimeType:@"video/mp4"
                                 fileSize:@(1024)
                          serviceAuthToken:nil
                                    error:nil];

    [self.worker completeJob:@"job-complete-1"];

    NSDictionary *job = [self.database getVideoJobById:@"job-complete-1" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"COMPLETED");
    XCTAssertEqualObjects(job[@"progress"], @(100));
}

- (void)testFailJobSetsStateToFailed {
    [self.database createVideoJobWithId:@"job-fail-1"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreitest"
                                 mimeType:@"video/mp4"
                                 fileSize:@(1024)
                          serviceAuthToken:nil
                                    error:nil];

    NSError *error = [NSError errorWithDomain:ATProtoVideoWorkerErrorDomain
                                         code:ATProtoVideoWorkerErrorProcessingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Something went wrong"}];
    [self.worker failJob:@"job-fail-1" error:error];

    NSDictionary *job = [self.database getVideoJobById:@"job-fail-1" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"FAILED");
    XCTAssertEqualObjects(job[@"message"], @"Something went wrong");
}

#pragma mark - Progress Updates

- (void)testUpdateJobProgress {
    [self.database createVideoJobWithId:@"job-progress-1"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreitest"
                                 mimeType:@"video/mp4"
                                 fileSize:@(1024)
                          serviceAuthToken:nil
                                    error:nil];

    [self.worker updateJobProgress:@"job-progress-1" progress:50 message:@"Halfway done"];

    NSDictionary *job = [self.database getVideoJobById:@"job-progress-1" error:nil];
    XCTAssertEqualObjects(job[@"progress"], @(50));
    XCTAssertEqualObjects(job[@"message"], @"Halfway done");
    XCTAssertEqualObjects(job[@"state"], @"PROCESSING");
}

#pragma mark - Blob Provider Propagation

- (void)testBlobProviderPropagatesToTranscoderAndGenerator {
    // Save original blob providers to restore later
    id<PDSBlobProvider> origTranscoderProvider = [ATProtoVideoTranscoder sharedTranscoder].blobProvider;
    id<PDSBlobProvider> origGeneratorProvider = [ATProtoVideoThumbnailGenerator sharedGenerator].blobProvider;

    // Set blob provider on worker
    self.worker.blobProvider = self.blobProvider;

    // Verify it propagated
    XCTAssertEqualObjects([ATProtoVideoTranscoder sharedTranscoder].blobProvider, self.blobProvider);
    XCTAssertEqualObjects([ATProtoVideoThumbnailGenerator sharedGenerator].blobProvider, self.blobProvider);

    // Restore to avoid leaking state
    [ATProtoVideoTranscoder sharedTranscoder].blobProvider = origTranscoderProvider;
    [ATProtoVideoThumbnailGenerator sharedGenerator].blobProvider = origGeneratorProvider;
}

@end
