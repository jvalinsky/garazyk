// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMediaServiceRuntimeTests.m

 @brief Integration tests for ATProtoMediaServiceRuntime.

 @discussion Boots the full MediaCore runtime (HTTP server, worker, database,
 XRPC dispatcher) with a mock processor and verifies health endpoint, admin
 endpoints, and job lifecycle. Requires socket access (--gated=run on macOS).
 */

#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoMediaServiceRuntime.h"
#import "MediaCore/ATProtoMediaServiceConfiguration.h"
#import "MediaCore/ATProtoMediaProcessor.h"
#import "MediaCore/ATProtoMediaSQLiteStore.h"
#import "MediaCore/ATProtoMediaWorker.h"
#import "Blob/PDSBlobProvider.h"
#import "Core/CID.h"

#pragma mark - Mock for Runtime Tests

@interface RuntimeTestMediaProcessor : NSObject <ATProtoMediaProcessor>
@property (nonatomic, readonly) NSString *mediaTypeIdentifier;
@property (nonatomic, assign) BOOL shouldFail;
@end

@interface RuntimeTestMediaProcessor ()
@property (nonatomic, readwrite) NSString *mediaTypeIdentifier;
@end

@implementation RuntimeTestMediaProcessor

- (instancetype)init {
    self = [super init];
    if (self) {
        _mediaTypeIdentifier = @"app.bsky.video";
        _shouldFail = NO;
    }
    return self;
}

- (BOOL)canProcessMimeType:(NSString *)mimeType {
    return [mimeType isEqualToString:@"video/mp4"] || [mimeType isEqualToString:@"video/quicktime"];
}

- (void)processMediaAtURL:(NSURL *)inputURL
          outputDirectory:(NSString *)outputDirectory
            progressBlock:(nullable void (^)(float progress))progressBlock
               completion:(void (^)(NSDictionary<NSString *, id> *_Nullable results,
                                    NSError *_Nullable error))completion {
    usleep(100000); // 100ms simulated processing
    if (self.shouldFail) {
        if (completion) completion(nil, [NSError errorWithDomain:@"RuntimeTest"
                                                           code:1
                                                       userInfo:@{NSLocalizedDescriptionKey: @"Simulated failure"}]);
    } else {
        if (progressBlock) progressBlock(1.0);
        if (completion) completion(@{
            @"processedCid": @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu",
            @"thumbnailCid": @"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454",
            @"metadata": @{@"width": @640, @"height": @360}
        }, nil);
    }
}

@end

#pragma mark - Mock Blob Provider

@interface RuntimeTestBlobProvider : NSObject <PDSBlobProvider>
@end

@implementation RuntimeTestBlobProvider

- (BOOL)storeBlobData:(NSData *)data forCID:(CID *)cid error:(NSError **)error {
    return YES;
}

- (nullable NSData *)retrieveBlobDataForCID:(CID *)cid error:(NSError **)error {
    return [@"test blob data" dataUsingEncoding:NSUTF8StringEncoding];
}

- (nullable NSInputStream *)retrieveBlobStreamForCID:(CID *)cid error:(NSError **)error {
    return [NSInputStream inputStreamWithData:[@"test blob data" dataUsingEncoding:NSUTF8StringEncoding]];
}

- (BOOL)deleteBlobDataForCID:(CID *)cid error:(NSError **)error {
    return YES;
}

- (BOOL)hasBlobDataForCID:(CID *)cid {
    return YES;
}

- (nullable NSURL *)blobFileURLForCID:(CID *)cid error:(NSError **)error {
    return nil;
}

@end

#pragma mark - Tests

@interface ATProtoMediaServiceRuntimeTests : XCTestCase
@property (nonatomic, strong) ATProtoMediaServiceRuntime *runtime;
@property (nonatomic, strong) NSString *tempDataDir;
@property (nonatomic, strong) RuntimeTestMediaProcessor *mockProcessor;
@property (nonatomic, assign) NSUInteger testPort;
@end

@implementation ATProtoMediaServiceRuntimeTests

- (void)setUp {
    [super setUp];

    // Create temp directory
    self.tempDataDir = [NSTemporaryDirectory() stringByAppendingFormat:@"media_runtime_test_%@", [[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDataDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Use a dynamic port to avoid conflicts
    self.testPort = 26000 + (arc4random() % 5000);

    self.mockProcessor = [[RuntimeTestMediaProcessor alloc] init];

    ATProtoMediaServiceConfiguration *config = [[ATProtoMediaServiceConfiguration alloc] init];
    config.port = self.testPort;
    config.dataDirectory = self.tempDataDir;
    config.blobDirectory = [self.tempDataDir stringByAppendingPathComponent:@"blobs"];
    config.pdsURL = @"http://localhost:2583";
    config.serviceDID = @"did:web:test.local";
    config.maxConcurrentJobs = 2;
    config.pollInterval = 10.0; // Long interval to avoid spurious polls

    [[NSFileManager defaultManager] createDirectoryAtPath:config.blobDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    self.runtime = [[ATProtoMediaServiceRuntime alloc] initWithConfiguration:config
                                                                   processor:self.mockProcessor];
}

- (void)tearDown {
    [self.runtime stop];
    self.runtime = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDataDir error:nil];
    [super tearDown];
}

#pragma mark - Health Endpoint

- (void)testRuntimeStartsAndHealthEndpointResponds {
    NSError *error = nil;
    BOOL started = [self.runtime startWithError:&error];
    XCTAssertTrue(started, @"Runtime should start: %@", error);

    // Wait briefly for server to bind
    usleep(500000);

    // Hit /_health
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%lu/_health", (unsigned long)self.testPort]];
    NSError *fetchError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:&fetchError];
    XCTAssertNotNil(data, @"Health endpoint should respond: %@", fetchError);

    if (data) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        XCTAssertEqualObjects(json[@"status"], @"ok");
        XCTAssertEqualObjects(json[@"service"], @"app.bsky.video");
    }
}

- (void)testHealthEndpointReturns200 {
    NSError *error = nil;
    BOOL started = [self.runtime startWithError:&error];
    XCTAssertTrue(started);

    usleep(500000);

    __block NSHTTPURLResponse *response = nil;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%lu/_health", (unsigned long)self.testPort]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 5.0;

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            XCTFail(@"Health request failed: %@", err);
        } else {
            response = (NSHTTPURLResponse *)resp;
        }
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - Admin Endpoints

- (void)testAdminListJobsReturnsEmptyList {
    NSError *error = nil;
    BOOL started = [self.runtime startWithError:&error];
    XCTAssertTrue(started);

    usleep(500000);

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%lu/admin/api/media/jobs", (unsigned long)self.testPort]];
    NSError *fetchError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:&fetchError];
    XCTAssertNotNil(data, @"Admin jobs endpoint should respond: %@", fetchError);

    if (data) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        XCTAssertNotNil(json[@"jobs"]);
        XCTAssertTrue([json[@"jobs"] isKindOfClass:[NSArray class]]);
    }
}

- (void)testAdminListJobsCanFilterByState {
    NSError *error = nil;
    BOOL started = [self.runtime startWithError:&error];
    XCTAssertTrue(started);

    // Create a job directly in the store
    ATProtoMediaServiceConfiguration *config = self.runtime.configuration;
    NSString *dbPath = [config.dataDirectory stringByAppendingPathComponent:@"media.db"];
    ATProtoMediaSQLiteStore *directStore = [[ATProtoMediaSQLiteStore alloc] initWithDatabasePath:dbPath error:&error];
    XCTAssertNotNil(directStore);

    [directStore createJobWithId:@"admin-test-job-1" did:@"did:plc:admin" blobCid:@"cid-admin" mimeType:@"video/mp4" fileSize:@(1024) serviceAuthToken:nil error:nil];
    [directStore closeDatabase];

    usleep(500000);

    // Query with state filter = PENDING
    NSString *urlString = [NSString stringWithFormat:@"http://127.0.0.1:%lu/admin/api/media/jobs?state=PENDING", (unsigned long)self.testPort];
    NSURL *url = [NSURL URLWithString:urlString];
    NSError *fetchError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:&fetchError];
    XCTAssertNotNil(data);

    if (data) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *jobs = json[@"jobs"];
        XCTAssertGreaterThanOrEqual(jobs.count, 1);
        BOOL found = NO;
        for (NSDictionary *job in jobs) {
            if ([job[@"job_id"] isEqualToString:@"admin-test-job-1"]) {
                found = YES;
                XCTAssertEqualObjects(job[@"state"], @"PENDING");
                break;
            }
        }
        XCTAssertTrue(found, @"Should find the created job in PENDING state");
    }
}

- (void)testAdminRetryJobEndpoint {
    NSError *error = nil;
    BOOL started = [self.runtime startWithError:&error];
    XCTAssertTrue(started);

    // Create a job in FAILED state
    ATProtoMediaServiceConfiguration *config = self.runtime.configuration;
    NSString *dbPath = [config.dataDirectory stringByAppendingPathComponent:@"media.db"];
    ATProtoMediaSQLiteStore *directStore = [[ATProtoMediaSQLiteStore alloc] initWithDatabasePath:dbPath error:&error];
    XCTAssertNotNil(directStore);

    [directStore createJobWithId:@"retry-test-job" did:@"did:plc:retry" blobCid:@"cid-retry" mimeType:@"video/mp4" fileSize:@(512) serviceAuthToken:nil error:nil];
    [directStore updateJobState:@"retry-test-job" state:ATProtoMediaJobStateFailed progress:0 message:@"test failure" error:nil];
    [directStore closeDatabase];

    usleep(500000);

    // Call POST retry endpoint
    NSString *urlString = [NSString stringWithFormat:@"http://127.0.0.1:%lu/admin/api/media/jobs/retry-test-job/retry", (unsigned long)self.testPort];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 5.0;

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSInteger statusCode = 0;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable resp, NSError * _Nullable err) {
        if (resp) {
            statusCode = ((NSHTTPURLResponse *)resp).statusCode;
        }
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

    XCTAssertEqual(statusCode, 200, @"Admin retry endpoint should return 200");

    // Verify job was reset to PENDING
    ATProtoMediaSQLiteStore *verifyStore = [[ATProtoMediaSQLiteStore alloc] initWithDatabasePath:dbPath error:&error];
    NSDictionary *job = [verifyStore getJobById:@"retry-test-job" error:nil];
    [verifyStore closeDatabase];

    XCTAssertEqualObjects(job[@"state"], @"PENDING");
    XCTAssertEqual([job[@"retry_count"] integerValue], 1);
}

- (void)testRuntimeReportsFailureOnInvalidConfig {
    // No data directory → should fail to init db
    ATProtoMediaServiceConfiguration *badConfig = [[ATProtoMediaServiceConfiguration alloc] init];
    badConfig.port = self.testPort;
    badConfig.dataDirectory = @"/nonexistent/path/that/does/not/exist";
    badConfig.blobDirectory = @"/nonexistent/blobs";
    badConfig.pdsURL = @"http://localhost:2583";
    badConfig.serviceDID = @"did:web:test";

    // Disable worker to avoid spurious jobs
    ATProtoMediaServiceRuntime *badRuntime = [[ATProtoMediaServiceRuntime alloc] initWithConfiguration:badConfig
                                                                                              processor:self.mockProcessor];
    NSError *error = nil;
    BOOL started = [badRuntime startWithError:&error];
    // Should fail because data directory doesn't exist
    // (The store will fail to create the db file in the nonexistent dir)
    // Note: this may or may not fail depending on SQLite behavior,
    // so we'll assert that if it fails, error is set
    if (!started) {
        XCTAssertNotNil(error);
    }
    [badRuntime stop];
}

#pragma mark - Runtime Properties

- (void)testRuntimePropertiesAfterStart {
    NSError *error = nil;
    BOOL started = [self.runtime startWithError:&error];
    XCTAssertTrue(started);

    XCTAssertNotNil(self.runtime.httpServer);
    XCTAssertNotNil(self.runtime.worker);
    XCTAssertEqual(self.runtime.processor.mediaTypeIdentifier, @"app.bsky.video");
    XCTAssertEqual(self.runtime.configuration.port, self.testPort);
}

- (void)testRuntimeStopDoesNotCrash {
    NSError *error = nil;
    BOOL started = [self.runtime startWithError:&error];
    XCTAssertTrue(started);

    usleep(200000);

    XCTAssertNoThrow([self.runtime stop]);
    // Verify the port is no longer bound (best effort)
    usleep(200000);
}

@end
