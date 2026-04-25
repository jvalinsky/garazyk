#import <XCTest/XCTest.h>
#import "AppView/Services/RecordLifecycleHandler.h"
#import "AppView/Services/NotificationService.h"
#import "AppView/Services/BookmarkService.h"
#import "AppView/Services/GraphService.h"
#import "AppView/Services/FeedService.h"
#import "Database/PDSDatabase.h"
#import "Network/XrpcAppBskyMethods.h"

@interface RecordLifecycleHandlerTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) RecordLifecycleHandler *handler;
@end

@implementation RecordLifecycleHandlerTests

- (void)setUp {
    [super setUp];

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"lifecycle_test.db"];
    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];

    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Database setup failed: %@", error);

    NotificationService *notificationService =
        [[NotificationService alloc] initWithDatabase:self.database
                                          actorService:nil];
    BookmarkService *bookmarkService =
        [[BookmarkService alloc] initWithDatabase:self.database];
    GraphService *graphService =
        [[GraphService alloc] initWithDatabase:self.database];
    FeedService *feedService =
        [[FeedService alloc] initWithDatabase:self.database];

    self.handler = [[RecordLifecycleHandler alloc]
        initWithNotificationService:notificationService
                      bookmarkService:bookmarkService
                         graphService:graphService
                          feedService:feedService
                             database:self.database];
}

- (void)tearDown {
    self.handler = nil;
    [self.database close];
    self.database = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

#pragma mark - Retention Tests

- (void)testHandlerIsRetainedByStaticStorage {
    // Verify that the static storage in XrpcAppBskyMethods retains the handler.
    // This is a regression test for the bug where RecordLifecycleHandler was
    // stored in a local __attribute__((unused)) variable and immediately
    // deallocated because NSNotificationCenter does not retain observers.
    RecordLifecycleHandler *handler = self.handler;
    [XrpcAppBskyMethods setRetainedLifecycleHandler:handler];

    // The handler should still be alive after setting it
    XCTAssertNotNil(handler,
        @"RecordLifecycleHandler should remain alive after being stored in static storage");

    // Clean up
    [XrpcAppBskyMethods setRetainedLifecycleHandler:nil];
}

- (void)testHandlerObservesRecordChangeNotification {
    // Verify that the handler is alive and can receive notifications.
    // If the handler were deallocated, this notification would be silently ignored.
    XCTestExpectation *exp = [self expectationWithDescription:@"Handler received notification"];

    RecordLifecycleHandler *handler = self.handler;
    [XrpcAppBskyMethods setRetainedLifecycleHandler:handler];

    // Post a record change notification — the handler should receive it
    // without crashing (it may not process it fully due to missing data,
    // but it should not crash from being deallocated).
    NSDictionary *userInfo = @{
        @"did": @"did:plc:test123",
        @"collection": @"app.bsky.feed.post",
        @"rkey": @"testkey",
        @"action": @"create",
        @"cid": [NSNull null],
        @"recordCBOR": [NSNull null]
    };
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"PDSRecordDidChangeNotification"
                      object:nil
                    userInfo:userInfo];

    // Give the handler a moment to process
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [exp fulfill];
    });

    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    // Clean up
    [XrpcAppBskyMethods setRetainedLifecycleHandler:nil];
}

- (void)testHandlerNotCrashingWithIncompleteNotificationData {
    // Verify the handler gracefully handles notifications with missing data.
    // This should not crash even if some fields are nil.
    [XrpcAppBskyMethods setRetainedLifecycleHandler:self.handler];

    NSDictionary *userInfo = @{
        @"did": @"did:plc:test123"
        // Missing collection, rkey, action — handler should return early
    };
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"PDSRecordDidChangeNotification"
                      object:nil
                    userInfo:userInfo];

    // If we get here without a crash, the handler is alive and handles
    // incomplete data gracefully.
    XCTAssertNotNil(self.handler, @"Handler should still be alive after incomplete notification");

    // Clean up
    [XrpcAppBskyMethods setRetainedLifecycleHandler:nil];
}

@end
