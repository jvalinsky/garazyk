#import <XCTest/XCTest.h>
#import "Video/VideoWorker.h"
#import "Video/VideoTranscoder.h"
#import "Video/VideoThumbnailGenerator.h"
#import "Video/PDSLocalVideoJobStore.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Core/CID.h"
#import "Media/PDSVideoTranscoderIntegrationTests.h" // for VideoIntegrationTestBase

@interface ATProtoVideoWorkerIntegrationTests : VideoIntegrationTestBase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong) PDSDiskBlobProvider *blobProvider;
@property (nonatomic, strong) NSURL *blobStorageURL;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation ATProtoVideoWorkerIntegrationTests

- (void)setUp {
    [super setUp];

    // Create temp database
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"video_worker_integ_%@", [[NSUUID UUID] UUIDString]]]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempDirURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    self.serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:self.tempDirURL.path
                                                            serviceMaxSize:2
                                                           didCacheMaxSize:1
                                                         sequencerMaxSize:1];
    NSError *dbError = nil;
    self.database = [self.serviceDatabases serviceDatabaseWithError:&dbError];
    XCTAssertNotNil(self.database);
    XCTAssertNil(dbError);

    // Create disk blob provider
    self.blobStorageURL = [self.tempDirURL URLByAppendingPathComponent:@"blobs"];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.blobStorageURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    self.blobProvider = [[PDSDiskBlobProvider alloc] initWithStorageDirectory:self.blobStorageURL];
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempDirURL error:nil];
    [super tearDown];
}

- (void)testProcessJobEndToEnd {
    if (!self.testVideoURL) { XCTSkip(@"No test video available"); }

    // Read the test video data
    NSData *videoData = [NSData dataWithContentsOfURL:self.testVideoURL];
    XCTAssertNotNil(videoData);

    // Store the video blob
    CID *inputCid = [CID sha256:videoData];
    NSError *error = nil;
    BOOL stored = [self.blobProvider storeBlobData:videoData forCID:inputCid error:&error];
    XCTAssertTrue(stored);

    // Create a video job
    NSString *jobId = [[NSUUID UUID] UUIDString];
    [self.database createVideoJobWithId:jobId
                                    did:@"did:web:test.example.com"
                                 blobCid:inputCid.stringValue
                                mimeType:@"video/mp4"
                                fileSize:@(videoData.length)
                         serviceAuthToken:nil
                                    error:&error];
    XCTAssertNil(error);

    // Configure worker
    ATProtoVideoWorker *worker = [[ATProtoVideoWorker alloc] init];
    worker.jobStore = [[PDSLocalVideoJobStore alloc] initWithDatabase:self.database];
    worker.blobProvider = self.blobProvider;

    // Process the job
    [worker processJob:jobId];

    // Wait for the job to complete (poll the database)
    XCTestExpectation *expectation = [self expectationWithDescription:@"Job completed"];
    __block NSInteger attempts = 0;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self pollForJobCompletion:jobId expectation:expectation attempts:&attempts maxAttempts:30];
    });

    [self waitForExpectationsWithTimeout:60 handler:nil];

    // Verify final state
    NSDictionary *job = [self.database getVideoJobById:jobId error:nil];
    XCTAssertNotNil(job);
    XCTAssertEqualObjects(job[@"state"], @"COMPLETED");
    XCTAssertNotNil(job[@"processed_blob_cid"]);
}

- (void)pollForJobCompletion:(NSString *)jobId
                 expectation:(XCTestExpectation *)expectation
                    attempts:(NSInteger *)attempts
                maxAttempts:(NSInteger)maxAttempts {
    *attempts += 1;

    NSDictionary *job = [self.database getVideoJobById:jobId error:nil];
    NSString *state = job[@"state"];

    if ([state isEqualToString:@"COMPLETED"] || [state isEqualToString:@"FAILED"] || *attempts >= maxAttempts) {
        [expectation fulfill];
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self pollForJobCompletion:jobId expectation:expectation attempts:attempts maxAttempts:maxAttempts];
    });
}

@end
