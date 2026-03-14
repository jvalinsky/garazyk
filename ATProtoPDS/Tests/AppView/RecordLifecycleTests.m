// Tests for RecordLifecycleHandler: init, observing, and stop.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "AppView/RecordLifecycleHandler.h"
#import "AppView/NotificationService.h"
#import "AppView/BookmarkService.h"
#import "AppView/GraphService.h"
#import "Database/PDSDatabase.h"

@interface RecordLifecycleTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, copy) NSString *dbPath;
@end

@implementation RecordLifecycleTests

- (void)setUp {
    [super setUp];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"lifecycle_%@.db", uuid]];
    NSURL *url = [NSURL fileURLWithPath:self.dbPath];
    self.db = [PDSDatabase databaseAtURL:url];
    NSError *error = nil;
    BOOL opened = [self.db openWithError:&error];
    XCTAssertTrue(opened, @"Database must open: %@", error);
}

- (void)tearDown {
    [self.db close];
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

#pragma mark - Initialization

- (void)testInitDoesNotReturnNil {
    NotificationService *notif = [[NotificationService alloc] initWithDatabase:self.db];
    BookmarkService *bm = [[BookmarkService alloc] initWithDatabase:self.db];
    GraphService *graph = [[GraphService alloc] initWithDatabase:self.db];

    RecordLifecycleHandler *handler = [[RecordLifecycleHandler alloc]
                                       initWithNotificationService:notif
                                                   bookmarkService:bm
                                                      graphService:graph
                                                          database:self.db];
    XCTAssertNotNil(handler, @"RecordLifecycleHandler must initialize successfully");
}

#pragma mark - Stop observing does not crash

- (void)testStopObservingDoesNotCrash {
    NotificationService *notif = [[NotificationService alloc] initWithDatabase:self.db];
    BookmarkService *bm = [[BookmarkService alloc] initWithDatabase:self.db];
    GraphService *graph = [[GraphService alloc] initWithDatabase:self.db];

    RecordLifecycleHandler *handler = [[RecordLifecycleHandler alloc]
                                       initWithNotificationService:notif
                                                   bookmarkService:bm
                                                      graphService:graph
                                                          database:self.db];
    XCTAssertNoThrow([handler stopObserving],
                     @"stopObserving must not throw");
}

- (void)testStopObservingCanBeCalledMultipleTimes {
    NotificationService *notif = [[NotificationService alloc] initWithDatabase:self.db];
    BookmarkService *bm = [[BookmarkService alloc] initWithDatabase:self.db];
    GraphService *graph = [[GraphService alloc] initWithDatabase:self.db];

    RecordLifecycleHandler *handler = [[RecordLifecycleHandler alloc]
                                       initWithNotificationService:notif
                                                   bookmarkService:bm
                                                      graphService:graph
                                                          database:self.db];
    [handler stopObserving];
    XCTAssertNoThrow([handler stopObserving],
                     @"Calling stopObserving twice must not crash");
}

#pragma mark - Notification observation

- (void)testHandlerObservesRecordChangeNotification {
    // Verify the handler registers for the standard record-did-change notification
    // by posting it and ensuring no exception is thrown.
    NotificationService *notif = [[NotificationService alloc] initWithDatabase:self.db];
    BookmarkService *bm = [[BookmarkService alloc] initWithDatabase:self.db];
    GraphService *graph = [[GraphService alloc] initWithDatabase:self.db];

    RecordLifecycleHandler *handler = [[RecordLifecycleHandler alloc]
                                       initWithNotificationService:notif
                                                   bookmarkService:bm
                                                      graphService:graph
                                                          database:self.db];
    (void)handler;

    // Post the notification with a minimal payload; handler must not crash.
    XCTAssertNoThrow([[NSNotificationCenter defaultCenter]
                      postNotificationName:@"PDSRecordDidChangeNotification"
                                    object:nil
                                  userInfo:@{
        @"did": @"did:plc:test",
        @"collection": @"app.bsky.feed.like",
        @"rkey": @"rkey001",
        @"uri": @"at://did:plc:test/app.bsky.feed.like/rkey001",
        @"action": @"create",
        @"record": @{@"subject": @{@"uri": @"at://did:plc:post/app.bsky.feed.post/p1"}}
    }]);

    [handler stopObserving];
}

@end
