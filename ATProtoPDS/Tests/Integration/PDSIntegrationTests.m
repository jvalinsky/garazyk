#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "Database/PDSDatabase.h"

@interface PDSIntegrationTests : XCTestCase

@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) NSURL *tempURL;
@property (nonatomic, copy) NSString *did;
@property (nonatomic, strong) NSDictionary *recordResult;
@property (nonatomic, strong) NSDictionary *sessionResult;
@property (nonatomic, strong) NSDictionary *blobResult;

@end

@implementation PDSIntegrationTests

- (void)setUp {
    [super setUp];

    self.tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    self.tempURL = [self.tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    self.tempURL = [self.tempURL URLByAppendingPathExtension:@"db"];

    NSError *dbError = nil;
    self.database = [PDSDatabase databaseAtURL:self.tempURL];
    XCTAssertTrue([self.database openWithError:&dbError], @"Database should open: %@", dbError);

    self.controller = [[PDSController alloc] initWithDatabase:self.database];
}

- (void)tearDown {
    [self.database close];
    [super tearDown];
}

- (void)testAccountCreation {
    NSError *error = nil;
    NSDictionary *accountResult = [self.controller createAccountForEmail:@"test@example.com"
                                                               password:@"testpass123"
                                                                handle:@"test.example.com"
                                                                   did:nil
                                                                 error:&error];

    XCTAssertNotNil(accountResult, @"Account should be created");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(accountResult[@"did"], @"Account should have DID");

    self.did = accountResult[@"did"];
}

- (void)testSessionCreation {
    XCTAssertNotNil(self.did, @"Account should be created first");

    NSError *error = nil;
    self.sessionResult = [self.controller createSessionForIdentifier:@"test@example.com"
                                                           password:@"testpass123"
                                                            handle:@"test.example.com"
                                                              did:self.did
                                                             error:&error];

    XCTAssertNotNil(self.sessionResult, @"Session should be created");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(self.sessionResult[@"accessJwt"], @"Session should have access token");
}

- (void)testRecordCreation {
    XCTAssertNotNil(self.did, @"Account should be created first");

    NSError *error = nil;
    NSDictionary *recordBody = @{
        @"text": @"Hello, ATProto!",
        @"createdAt": @"2024-01-01T00:00:00.000Z"
    };

    self.recordResult = [self.controller createRecordForDid:self.did collection:@"app.bsky.feed.post" record:recordBody error:&error];

    XCTAssertNotNil(self.recordResult, @"Record should be created");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(self.recordResult[@"cid"], @"Record should have CID");
}

- (void)testRecordRetrieval {
    XCTAssertNotNil(self.recordResult, @"Record should be created first");

    NSString *rkey = self.recordResult[@"uri"];
    NSArray *uriComponents = [rkey componentsSeparatedByString:@"/"];
    NSString *recordKey = uriComponents.lastObject;

    NSError *error = nil;
    NSDictionary *retrievedRecord = [self.controller getRecordForDid:self.did collection:@"app.bsky.feed.post" rkey:recordKey error:&error];

    XCTAssertNotNil(retrievedRecord, @"Record should be retrieved");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertEqualObjects(retrievedRecord[@"value"][@"text"], @"Hello, ATProto!", @"Record text should match");
}

- (void)testRecordListing {
    XCTAssertNotNil(self.did, @"Account should be created first");

    NSError *error = nil;
    NSArray *listResult = [self.controller listRecordsForDid:self.did collection:@"app.bsky.feed.post" limit:10 cursor:nil error:&error];

    XCTAssertNotNil(listResult, @"List should not be nil");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertGreaterThan(listResult.count, 0, @"Should have at least one record");
}

- (void)testBlobUpload {
    XCTAssertNotNil(self.did, @"Account should be created first");

    NSError *error = nil;
    self.blobResult = [self.controller uploadBlob:[@"test data" dataUsingEncoding:NSUTF8StringEncoding]
                                        mimeType:@"text/plain"
                                             did:self.did
                                          error:&error];

    XCTAssertNotNil(self.blobResult, @"Blob should be uploaded");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(self.blobResult[@"cid"], @"Blob should have CID");
}

- (void)testBlobRetrieval {
    XCTAssertNotNil(self.blobResult, @"Blob should be uploaded first");

    NSError *error = nil;
    NSDictionary *retrievedBlob = [self.controller getBlobWithCID:self.blobResult[@"cid"] did:self.did error:&error];

    XCTAssertNotNil(retrievedBlob, @"Blob should be retrieved");
    XCTAssertNil(error, @"No error should occur");
}

- (void)testRecordValidationValidPost {
    NSError *error = nil;
    NSDictionary *validRecord = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"This is a valid post",
        @"createdAt": @"2024-01-01T00:00:00.000Z"
    };

    BOOL isValid = [self.controller validateRecord:validRecord forCollection:@"app.bsky.feed.post" error:&error];

    XCTAssertTrue(isValid, @"Valid post should pass validation");
    XCTAssertNil(error, @"No error should occur");
}

- (void)testRecordValidationInvalidPost {
    NSError *error = nil;
    NSDictionary *invalidRecord = @{
        @"$type": @"app.bsky.feed.post",
        @"createdAt": @"2024-01-01T00:00:00.000Z"
    };

    BOOL isInvalid = [self.controller validateRecord:invalidRecord forCollection:@"app.bsky.feed.post" error:&error];

    XCTAssertFalse(isInvalid, @"Invalid post should fail validation");
    XCTAssertNotNil(error, @"Error should be set");
}

- (void)testRecordValidationWrongType {
    NSError *error = nil;
    NSDictionary *wrongTypeRecord = @{
        @"$type": @"app.bsky.feed.invalid",
        @"text": @"This has wrong type"
    };

    BOOL wrongTypeValid = [self.controller validateRecord:wrongTypeRecord forCollection:@"app.bsky.feed.post" error:&error];

    XCTAssertFalse(wrongTypeValid, @"Wrong type should fail validation");
    XCTAssertNotNil(error, @"Error should be set");
}

- (void)testConcurrentOperations {
    XCTAssertNotNil(self.did, @"Account should be created first");

    dispatch_queue_t queue = dispatch_queue_create("test.queue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();

    __block BOOL concurrentTestPassed = YES;
    __block NSUInteger operationsCompleted = 0;

    for (int i = 0; i < 5; i++) {
        dispatch_group_async(group, queue, ^{
            @autoreleasepool {
                NSDictionary *concurrentRecord = @{
                    @"$type": @"app.bsky.feed.post",
                    @"text": [NSString stringWithFormat:@"Concurrent post %d", i],
                    @"createdAt": @"2024-01-01T00:00:00.000Z"
                };

                __block NSDictionary *result = nil;
                __block NSError *blockError = nil;
                dispatch_sync(dispatch_get_main_queue(), ^{
                    result = [self.controller createRecordForDid:self.did collection:@"app.bsky.feed.post" record:concurrentRecord error:&blockError];
                });
                if (!result || blockError) {
                    concurrentTestPassed = NO;
                }
                operationsCompleted++;
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    XCTAssertTrue(concurrentTestPassed, @"Concurrent operations should pass");
    XCTAssertEqual(operationsCompleted, 5, @"All operations should complete");
}

- (void)testRepositoryDescription {
    XCTAssertNotNil(self.did, @"Account should be created first");

    NSError *error = nil;
    NSDictionary *repoDesc = [self.controller describeRepo:self.did error:&error];

    XCTAssertNotNil(repoDesc, @"Repo description should be retrieved");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(repoDesc[@"handle"], @"Repo should have handle");
}

- (void)testSessionRefresh {
    XCTAssertNotNil(self.sessionResult, @"Session should be created first");

    NSError *error = nil;
    NSDictionary *refreshResult = [self.controller refreshSessionWithRefreshToken:self.sessionResult[@"refreshJwt"] error:&error];

    XCTAssertNotNil(refreshResult, @"Session refresh should succeed");
    XCTAssertNil(error, @"No error should occur");
    XCTAssertNotNil(refreshResult[@"accessJwt"], @"Should have new access token");
}

- (void)testRecordDeletion {
    XCTAssertNotNil(self.recordResult, @"Record should be created first");

    NSString *rkey = self.recordResult[@"uri"];
    NSArray *uriComponents = [rkey componentsSeparatedByString:@"/"];
    NSString *recordKey = uriComponents.lastObject;

    NSError *error = nil;
    BOOL deleteSuccess = [self.controller deleteRecordForDid:self.did collection:@"app.bsky.feed.post" rkey:recordKey error:&error];

    XCTAssertTrue(deleteSuccess, @"Record deletion should succeed");
    XCTAssertNil(error, @"No error should occur");
}

@end
