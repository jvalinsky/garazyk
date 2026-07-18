// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"

@interface PDSDatabaseVideoJobsTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSDatabaseVideoJobsTests

- (void)setUp {
    [super setUp];
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"videojobs_test_%@", [[NSUUID UUID] UUIDString]]]];
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

- (void)testCreateAndGetVideoJob {
    NSString *jobId = @"job-1";
    NSString *did = @"did:plc:videouser";
    NSString *blobCid = @"bafyreiblob1";

    NSError *error = nil;
    BOOL created = [self.database createVideoJobWithId:jobId
                                                   did:did
                                              blobCid:blobCid
                                             mimeType:@"video/mp4"
                                             fileSize:@(1024)
                                      serviceAuthToken:nil
                                                error:&error];
    XCTAssertTrue(created, @"createVideoJobWithId should succeed");
    XCTAssertNil(error);

    NSDictionary *job = [self.database getVideoJobById:jobId error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(job);
}

- (void)testGetVideoJobNotFound {
    NSError *error = nil;
    NSDictionary *job = [self.database getVideoJobById:@"nonexistent-job" error:&error];
    XCTAssertNil(job, @"Should return nil for nonexistent job");
    XCTAssertNil(error);
}

#pragma mark - Update State

- (void)testUpdateVideoJobState {
    NSString *jobId = @"job-state-1";
    [self.database createVideoJobWithId:jobId
                                    did:@"did:plc:vuser2"
                                 blobCid:@"bafyreiblob2"
                                mimeType:@"video/mp4"
                                fileSize:@(2048)
                         serviceAuthToken:nil
                                   error:nil];

    NSError *error = nil;
    BOOL updated = [self.database updateVideoJobState:jobId
                                               state:@"processing"
                                            progress:@(50)
                                             message:@"Halfway done"
                                               error:&error];
    XCTAssertTrue(updated, @"updateVideoJobState should succeed");
    XCTAssertNil(error);

    NSDictionary *job = [self.database getVideoJobById:jobId error:nil];
    XCTAssertNotNil(job);
}

#pragma mark - Update Results

- (void)testUpdateVideoJobResults {
    NSString *jobId = @"job-results-1";
    [self.database createVideoJobWithId:jobId
                                    did:@"did:plc:vuser3"
                                 blobCid:@"bafyreiblob3"
                                mimeType:@"video/mp4"
                                fileSize:@(4096)
                         serviceAuthToken:nil
                                   error:nil];

    NSError *error = nil;
    BOOL updated = [self.database updateVideoJobResults:jobId
                                     processedBlobCid:@"bafyriprocessed1"
                                    thumbnailBlobCid:@"bafyrithumb1"
                                              error:&error];
    XCTAssertTrue(updated, @"updateVideoJobResults should succeed");
    XCTAssertNil(error);
}

#pragma mark - Increment Retry

- (void)testIncrementVideoJobRetry {
    NSString *jobId = @"job-retry-1";
    [self.database createVideoJobWithId:jobId
                                    did:@"did:plc:vuser4"
                                 blobCid:@"bafyreiblob4"
                                mimeType:@"video/mp4"
                                fileSize:@(8192)
                         serviceAuthToken:nil
                                   error:nil];

    NSError *error = nil;
    BOOL incremented = [self.database incrementVideoJobRetry:jobId error:&error];
    XCTAssertTrue(incremented, @"incrementVideoJobRetry should succeed");
    XCTAssertNil(error);
}

#pragma mark - List

- (void)testListVideoJobs {
    for (int i = 0; i < 3; i++) {
        NSString *jobId = [NSString stringWithFormat:@"job-list-%d", i];
        [self.database createVideoJobWithId:jobId
                                        did:@"did:plc:vuser5"
                                     blobCid:[NSString stringWithFormat:@"bafyreiblob%d", i]
                                    mimeType:@"video/mp4"
                                    fileSize:@(1024)
                             serviceAuthToken:nil
                                       error:nil];
    }

    NSError *error = nil;
    NSArray<NSDictionary *> *jobs = [self.database listVideoJobsWithState:nil
                                                                   limit:10
                                                                  offset:0
                                                                   error:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(jobs.count, 3);
}

#pragma mark - Parse Limit

- (void)testParseLimit {
    NSUInteger outLimit = 0;
    [PDSDatabase parseLimit:@"50" outLimit:&outLimit];
    XCTAssertEqual(outLimit, 50);

    [PDSDatabase parseLimit:nil outLimit:&outLimit];
    XCTAssertEqual(outLimit, 0);
}

@end
