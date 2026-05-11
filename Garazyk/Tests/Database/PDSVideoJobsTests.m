// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"
#import "Database/Schema.h"

@interface PDSVideoJobsTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSVideoJobsTests

- (void)setUp {
    [super setUp];

    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"video_jobs_test_%@", [[NSUUID UUID] UUIDString]]]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempDirURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    NSURL *dbURL = [self.tempDirURL URLByAppendingPathComponent:@"test.db"];
    self.database = [PDSDatabase databaseAtURL:dbURL];
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error]);
    XCTAssertNil(error);
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempDirURL error:nil];
    [super tearDown];
}

#pragma mark - Create

- (void)testCreateVideoJob {
    NSError *error = nil;
    BOOL created = [self.database createVideoJobWithId:@"job-1"
                                                    did:@"did:web:test.example.com"
                                                 blobCid:@"bafyreiabc123"
                                                mimeType:@"video/mp4"
                                                fileSize:@(1024)
                                    serviceAuthToken:nil
                                                    error:&error];
    XCTAssertTrue(created);
    XCTAssertNil(error);

    NSDictionary *job = [self.database getVideoJobById:@"job-1" error:&error];
    XCTAssertNotNil(job);
    XCTAssertNil(error);
    XCTAssertEqualObjects(job[@"job_id"], @"job-1");
    XCTAssertEqualObjects(job[@"did"], @"did:web:test.example.com");
    XCTAssertEqualObjects(job[@"blob_cid"], @"bafyreiabc123");
    XCTAssertEqualObjects(job[@"mime_type"], @"video/mp4");
    XCTAssertEqualObjects(job[@"file_size"], @(1024));
    XCTAssertEqualObjects(job[@"state"], @"PENDING");
    XCTAssertEqualObjects(job[@"progress"], @(0));
}

- (void)testGetVideoJobByIdNotFound {
    NSError *error = nil;
    NSDictionary *job = [self.database getVideoJobById:@"nonexistent" error:&error];
    XCTAssertNil(job);
    XCTAssertNil(error);
}

#pragma mark - State Updates

- (void)testUpdateVideoJobState {
    [self.database createVideoJobWithId:@"job-2"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreiabc123"
                                 mimeType:@"video/mp4"
                                 fileSize:@(2048)
                                    serviceAuthToken:nil
                                     error:nil];

    NSError *error = nil;
    BOOL updated = [self.database updateVideoJobState:@"job-2"
                                                state:@"PROCESSING"
                                             progress:@(25)
                                              message:@"Transcoding"
                                                error:&error];
    XCTAssertTrue(updated);
    XCTAssertNil(error);

    NSDictionary *job = [self.database getVideoJobById:@"job-2" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"PROCESSING");
    XCTAssertEqualObjects(job[@"progress"], @(25));
    XCTAssertEqualObjects(job[@"message"], @"Transcoding");
}

- (void)testUpdateVideoJobResults {
    [self.database createVideoJobWithId:@"job-3"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreiabc123"
                                 mimeType:@"video/mp4"
                                 fileSize:@(4096)
                                    serviceAuthToken:nil
                                     error:nil];

    NSError *error = nil;
    BOOL updated = [self.database updateVideoJobResults:@"job-3"
                                       processedBlobCid:@"bafyreiprocessed"
                                      thumbnailBlobCid:@"bafyreithumbnail"
                                                   error:&error];
    XCTAssertTrue(updated);
    XCTAssertNil(error);

    NSDictionary *job = [self.database getVideoJobById:@"job-3" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"COMPLETED");
    XCTAssertEqualObjects(job[@"progress"], @(100));
    XCTAssertEqualObjects(job[@"processed_blob_cid"], @"bafyreiprocessed");
    XCTAssertEqualObjects(job[@"thumbnail_blob_cid"], @"bafyreithumbnail");
}

#pragma mark - Retry Logic

- (void)testIncrementVideoJobRetry {
    [self.database createVideoJobWithId:@"job-4"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreiabc123"
                                 mimeType:@"video/mp4"
                                 fileSize:@(8192)
                                    serviceAuthToken:nil
                                     error:nil];

    // Set to FAILED first
    [self.database updateVideoJobState:@"job-4"
                                  state:@"FAILED"
                               progress:@0
                                message:@"Export failed"
                                  error:nil];

    NSError *error = nil;
    BOOL incremented = [self.database incrementVideoJobRetry:@"job-4" error:&error];
    XCTAssertTrue(incremented);
    XCTAssertNil(error);

    NSDictionary *job = [self.database getVideoJobById:@"job-4" error:nil];
    XCTAssertEqualObjects(job[@"retry_count"], @(1));
    XCTAssertEqualObjects(job[@"state"], @"PENDING");
}

- (void)testIncrementVideoJobRetryMultipleTimes {
    [self.database createVideoJobWithId:@"job-5"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreiabc123"
                                 mimeType:@"video/mp4"
                                 fileSize:@(8192)
                                    serviceAuthToken:nil
                                     error:nil];

    for (int i = 0; i < 3; i++) {
        [self.database updateVideoJobState:@"job-5"
                                      state:@"FAILED"
                                   progress:@0
                                    message:@"Export failed"
                                      error:nil];
        [self.database incrementVideoJobRetry:@"job-5" error:nil];
    }

    NSDictionary *job = [self.database getVideoJobById:@"job-5" error:nil];
    XCTAssertEqualObjects(job[@"retry_count"], @(3));
    XCTAssertEqualObjects(job[@"state"], @"PENDING");
}

#pragma mark - Lifecycle

- (void)testVideoJobStateTransitions {
    [self.database createVideoJobWithId:@"job-6"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreiabc123"
                                 mimeType:@"video/mp4"
                                 fileSize:@(16384)
                                    serviceAuthToken:nil
                                     error:nil];

    // PENDING -> PROCESSING
    [self.database updateVideoJobState:@"job-6"
                                  state:@"PROCESSING"
                               progress:@(10)
                                message:@"Loading"
                                  error:nil];
    NSDictionary *job = [self.database getVideoJobById:@"job-6" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"PROCESSING");

    // PROCESSING -> COMPLETED
    [self.database updateVideoJobResults:@"job-6"
                        processedBlobCid:@"bafyreidone"
                       thumbnailBlobCid:@"bafyreithumb"
                                    error:nil];
    job = [self.database getVideoJobById:@"job-6" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"COMPLETED");
    XCTAssertEqualObjects(job[@"progress"], @(100));
}

- (void)testVideoJobFailedState {
    [self.database createVideoJobWithId:@"job-7"
                                     did:@"did:web:test.example.com"
                                  blobCid:@"bafyreiabc123"
                                 mimeType:@"video/mp4"
                                 fileSize:@(2048)
                                    serviceAuthToken:nil
                                     error:nil];

    [self.database updateVideoJobState:@"job-7"
                                  state:@"FAILED"
                               progress:@0
                                message:@"Transcoding failed: unsupported codec"
                                  error:nil];

    NSDictionary *job = [self.database getVideoJobById:@"job-7" error:nil];
    XCTAssertEqualObjects(job[@"state"], @"FAILED");
    XCTAssertEqualObjects(job[@"message"], @"Transcoding failed: unsupported codec");
}

@end
