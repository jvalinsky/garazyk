// SPDX-License-Identifier: MIT
// ... (standard header omitted for brevity)

#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoMediaXrpcPack.h"
#import "Network/XrpcRoutePackServices.h"

@interface ATProtoMediaXrpcPackTests : XCTestCase
@property (nonatomic, strong) ATProtoMediaXrpcPack *pack;
@end

@implementation ATProtoMediaXrpcPackTests

- (void)setUp
{
    [super setUp];
    self.pack = [[ATProtoMediaXrpcPack alloc] init];
}

- (void)tearDown
{
    self.pack = nil;
    [super tearDown];
}

// MARK: - init

- (void)testInit_SetsDefaultProperties
{
    XCTAssertNotNil(self.pack, @"Default init should produce non-nil pack");
    XCTAssertNil(self.pack.methodMappings, @"methodMappings should be nil by default");
    XCTAssertNil(self.pack.contentValidator, @"contentValidator should be nil by default");
}

// MARK: - methodMappings

- (void)testMethodMappings_GetSet
{
    NSDictionary *mappings = @{
        @"upload": @"app.bsky.video.uploadVideo",
        @"getJobStatus": @"app.bsky.video.getJobStatus",
        @"getUploadLimits": @"app.bsky.video.getUploadLimits",
    };
    self.pack.methodMappings = mappings;
    XCTAssertEqualObjects(self.pack.methodMappings, mappings);
    XCTAssertEqual(self.pack.methodMappings.count, 3);
}

- (void)testMethodMappings_Nil_DoesNotCrash
{
    XCTAssertNoThrow(self.pack.methodMappings = nil, @"Setting nil mappings should not crash");
    XCTAssertNil(self.pack.methodMappings);
}

- (void)testMethodMappings_AudioMappings
{
    NSDictionary *mappings = @{
        @"upload": @"app.bsky.audio.uploadAudio",
        @"getJobStatus": @"app.bsky.audio.getJobStatus",
    };
    self.pack.methodMappings = mappings;
    XCTAssertEqualObjects(self.pack.methodMappings[@"upload"], @"app.bsky.audio.uploadAudio");
    XCTAssertEqualObjects(self.pack.methodMappings[@"getJobStatus"], @"app.bsky.audio.getJobStatus");
    XCTAssertNil(self.pack.methodMappings[@"getUploadLimits"]);
}

- (void)testMethodMappings_EmptyDictionary
{
    self.pack.methodMappings = @{};
    XCTAssertNotNil(self.pack.methodMappings);
    XCTAssertEqual(self.pack.methodMappings.count, 0);
}

// MARK: - contentValidator

- (void)testContentValidator_GetSet
{
    __block BOOL validatorCalled = NO;
    self.pack.contentValidator = ^BOOL(NSData *data, NSString *mimeType) {
        validatorCalled = YES;
        return [mimeType hasPrefix:@"image/"];
    };

    XCTAssertNotNil(self.pack.contentValidator);

    NSData *sampleData = [NSData data];
    BOOL result = self.pack.contentValidator(sampleData, @"image/jpeg");
    XCTAssertTrue(result, @"Validator should return YES for image mime");
    XCTAssertTrue(validatorCalled, @"Validator block should have been called");
}

- (void)testContentValidator_RejectsNonMedia
{
    self.pack.contentValidator = ^BOOL(NSData *data, NSString *mimeType) {
        return [mimeType hasPrefix:@"image/"] || [mimeType hasPrefix:@"video/"];
    };

    XCTAssertFalse(self.pack.contentValidator([NSData data], @"application/pdf"),
                   @"Should reject non-media types");
    XCTAssertTrue(self.pack.contentValidator([NSData data], @"video/mp4"),
                  @"Should accept video types");
}

- (void)testContentValidator_NilValidator_DoesNotCrash
{
    XCTAssertNoThrow(self.pack.contentValidator = nil, @"Setting nil validator should not crash");
    XCTAssertNil(self.pack.contentValidator);
}

- (void)testContentValidator_WithData
{
    self.pack.contentValidator = ^BOOL(NSData *data, NSString *mimeType) {
        return data.length > 0 && mimeType.length > 0;
    };

    NSData *testData = [NSData dataWithBytes:"hello" length:5];
    XCTAssertTrue(self.pack.contentValidator(testData, @"text/plain"));
    XCTAssertFalse(self.pack.contentValidator([NSData data], @"text/plain"), @"Empty data should fail");
}

// MARK: - formatJobResponse

- (void)testFormatJobResponse_CompletedJob
{
    NSString *jsonStr = @"{\"processedCid\":\"bafyreiabc\",\"metadata\":{\"width\":1920,\"height\":1080}}";
    NSDictionary *job = @{
        @"job_id": @"abc-123",
        @"did": @"did:plc:test",
        @"state": @"COMPLETED",
        @"progress": @100,
        @"mime_type": @"video/mp4",
        @"file_size": @(1024),
        @"results_json": jsonStr
    };
    NSDictionary *formatted = [self.pack formatJobResponse:job];
    XCTAssertNotNil(formatted);
    XCTAssertEqualObjects(formatted[@"jobId"], @"abc-123");
    XCTAssertEqualObjects(formatted[@"state"], @"JOB_STATE_COMPLETED");
    XCTAssertEqualObjects(formatted[@"progress"], @100);
    XCTAssertNotNil(formatted[@"blob"]);
    XCTAssertEqualObjects(formatted[@"blob"][@"ref"][@"$link"], @"bafyreiabc");
    XCTAssertNotNil(formatted[@"metadata"]);
}

- (void)testFormatJobResponse_NilInput_DoesNotCrash
{
    XCTAssertNoThrow([self.pack formatJobResponse:nil],
                     @"Nil input to formatJobResponse should not crash");
}

- (void)testFormatJobResponse_EmptyInput
{
    NSDictionary *formatted = [self.pack formatJobResponse:@{}];
    XCTAssertNotNil(formatted, @"Empty input should produce non-nil output");
}

- (void)testFormatJobResponse_AllStates
{
    NSDictionary *stateTests = @{
        @"PENDING": @"JOB_STATE_PENDING",
        @"PROCESSING": @"JOB_STATE_PROCESSING",
        @"COMPLETED": @"JOB_STATE_COMPLETED",
        @"FAILED": @"JOB_STATE_FAILED",
    };

    for (NSString *dbState in stateTests) {
        NSDictionary *job = @{@"job_id": @"id", @"did": @"did", @"state": dbState, @"progress": @50};
        NSDictionary *formatted = [self.pack formatJobResponse:job];
        XCTAssertEqualObjects(formatted[@"state"], stateTests[dbState],
                              @"State %@ should map to %@", dbState, stateTests[dbState]);
    }
}

- (void)testFormatJobResponse_IncludesErrorForFailedJobs
{
    NSDictionary *job = @{
        @"job_id": @"failed-job",
        @"did": @"did:plc:fail",
        @"state": @"FAILED",
        @"progress": @0,
        @"error_message": @"Processing timeout"
    };
    NSDictionary *formatted = [self.pack formatJobResponse:job];
    XCTAssertEqualObjects(formatted[@"error"], @"Processing timeout");
}

// MARK: - registerWithDispatcher:services:

- (void)testRegisterWithDispatcher_BothNil_DoesNotCrash
{
    // Objective-C nil messaging: sending messages to nil returns nil/NO/0.
    // A nil services object returns nil for videoJobStore and blobProvider,
    // so registerWithDispatcher:nil services:nil is safe.
    XCTAssertNoThrow([self.pack registerWithDispatcher:nil services:nil],
                     @"Both nil args should not crash");
}



// MARK: - class method registerWithDispatcher:services:

- (void)testClassRegisterWithDispatcher_NilArgs_DoesNotCrash
{
    XCTAssertNoThrow([ATProtoMediaXrpcPack registerWithDispatcher:nil services:nil]);
}

@end
