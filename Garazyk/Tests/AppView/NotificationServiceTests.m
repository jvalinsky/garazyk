#import <XCTest/XCTest.h>
#import "AppView/NotificationService.h"
#import "Database/PDSDatabase.h"

@interface NotificationServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NotificationService *service;
@end

@implementation NotificationServiceTests

- (void)setUp {
    [super setUp];
    
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"notification_service_test.db"];
    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Database setup failed: %@", error);
    
    self.service = [[NotificationService alloc] initWithDatabase:self.database];
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (void)testServiceInitializationConfiguresDatabase {
    XCTAssertNotNil(self.service);
    XCTAssertEqual(self.service.database, self.database);
}

- (void)testRegisterPushMissingDID {
    NSError *error = nil;
    BOOL success = [self.service registerPushForActor:@"" deviceToken:@"token" platformToken:nil serviceEndpoint:@"https://example.com" error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
}

- (void)testRegisterPushMissingDeviceToken {
    NSError *error = nil;
    BOOL success = [self.service registerPushForActor:@"did:plc:user" deviceToken:@"" platformToken:nil serviceEndpoint:@"https://example.com" error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
}

- (void)testRegisterPushSuccess {
    NSError *error = nil;
    BOOL success = [self.service registerPushForActor:@"did:plc:user1"
                                          deviceToken:@"device-token-123"
                                        platformToken:@"apns"
                                        serviceEndpoint:@"https://push.example.com"
                                                  error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
}

- (void)testRegisterPushUpdateExistingIsSuccessful {
    NSError *error = nil;
    [self.service registerPushForActor:@"did:plc:user2"
                          deviceToken:@"token-456"
                        platformToken:@"fcm"
                        serviceEndpoint:@"https://old.example.com"
                                  error:&error];
    
    error = nil;
    BOOL success = [self.service registerPushForActor:@"did:plc:user2"
                                          deviceToken:@"token-456"
                                        platformToken:@"apns"
                                        serviceEndpoint:@"https://new.example.com"
                                                  error:&error];
    XCTAssertTrue(success);
}

- (void)testUnregisterPushMissingDID {
    NSError *error = nil;
    BOOL success = [self.service unregisterPushForActor:@"" error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
}

- (void)testUnregisterPushSuccess {
    NSError *error = nil;
    [self.service registerPushForActor:@"did:plc:user3" deviceToken:@"tok1" platformToken:nil serviceEndpoint:@"https://example.com" error:&error];
    
    error = nil;
    BOOL success = [self.service unregisterPushForActor:@"did:plc:user3" error:&error];
    XCTAssertTrue(success);
}

- (void)testUnregisterNonExistentIsSuccessful {
    NSError *error = nil;
    BOOL success = [self.service unregisterPushForActor:@"did:plc:nonexistent" error:&error];
    XCTAssertTrue(success);
}

- (void)testGetNotificationsMissingDID {
    NSError *error = nil;
    NSArray *notifications = [self.service getNotificationsForActor:@"" limit:10 cursor:nil error:&error];
    XCTAssertNil(notifications);
    XCTAssertNotNil(error);
}

- (void)testGetNotificationsEmptyReturnsEmptyArray {
    NSError *error = nil;
    NSArray *notifications = [self.service getNotificationsForActor:@"did:plc:user4" limit:10 cursor:nil error:&error];
    
    XCTAssertNotNil(notifications);
    XCTAssertEqual(notifications.count, 0);
}

- (void)testGetNotificationsWithDataReturnsNotifications {
    [self insertNotification:@"did:plc:user5" reason:@"reply" subjectURI:@"at://did:plc:author/app.bsky.feed.post/123"];
    [self insertNotification:@"did:plc:user5" reason:@"like" subjectURI:@"at://did:plc:author/app.bsky.feed.post/456"];
    
    NSError *error = nil;
    NSArray *notifications = [self.service getNotificationsForActor:@"did:plc:user5" limit:10 cursor:nil error:&error];
    
    XCTAssertNotNil(notifications);
    XCTAssertEqual(notifications.count, 2);
}

- (void)testGetNotificationsLimitReturnsLimitedNotifications {
    for (int i = 0; i < 10; i++) {
        [self insertNotification:@"did:plc:user6" reason:@"mention" subjectURI:[NSString stringWithFormat:@"at://did:plc:author/app.bsky.feed.post/%d", i]];
    }
    
    NSError *error = nil;
    NSArray *notifications = [self.service getNotificationsForActor:@"did:plc:user6" limit:3 cursor:nil error:&error];
    
    XCTAssertNotNil(notifications);
    XCTAssertEqual(notifications.count, 3);
}

- (void)testGetNotificationsWithCursorMatchesAllCount {
    [self insertNotification:@"did:plc:user7" reason:@"repost" subjectURI:@"at://did:plc:a/post1"];
    [self insertNotification:@"did:plc:user7" reason:@"repost" subjectURI:@"at://did:plc:a/post2"];
    [self insertNotification:@"did:plc:user7" reason:@"repost" subjectURI:@"at://did:plc:a/post3"];
    
    NSError *error = nil;
    NSArray *all = [self.service getNotificationsForActor:@"did:plc:user7" limit:10 cursor:nil error:&error];
    XCTAssertEqual(all.count, 3);
}

- (void)testGetNotificationsDifferentActorsMatchesNotifs2Count {
    [self insertNotification:@"did:plc:actor1" reason:@"like" subjectURI:@"at://did:plc:a/post1"];
    [self insertNotification:@"did:plc:actor2" reason:@"like" subjectURI:@"at://did:plc:a/post2"];
    
    NSError *error = nil;
    NSArray *notifs1 = [self.service getNotificationsForActor:@"did:plc:actor1" limit:10 cursor:nil error:&error];
    NSArray *notifs2 = [self.service getNotificationsForActor:@"did:plc:actor2" limit:10 cursor:nil error:&error];
    
    XCTAssertEqual(notifs1.count, 1);
    XCTAssertEqual(notifs2.count, 1);
}

- (void)testMarkNotificationsAsReadMissingDID {
    NSError *error = nil;
    BOOL success = [self.service markNotificationsAsReadForActor:@"" limit:10 error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
}

- (void)testMarkNotificationsAsReadSuccess {
    [self insertNotification:@"did:plc:user8" reason:@"mention" subjectURI:@"at://did:plc:a/post1" isRead:NO];
    
    NSError *error = nil;
    BOOL success = [self.service markNotificationsAsReadForActor:@"did:plc:user8" limit:10 error:&error];
    XCTAssertTrue(success);
}

- (void)testMarkNotificationsAsReadWithLimitIsSuccessful {
    for (int i = 0; i < 5; i++) {
        [self insertNotification:@"did:plc:user9" reason:@"reply" subjectURI:[NSString stringWithFormat:@"at://did:plc:a/post%d", i] isRead:NO];
    }
    
    NSError *error = nil;
    BOOL success = [self.service markNotificationsAsReadForActor:@"did:plc:user9" limit:2 error:&error];
    XCTAssertTrue(success);
}

- (void)testMarkNotificationsAsReadNonexistentActorIsSuccessful {
    NSError *error = nil;
    BOOL success = [self.service markNotificationsAsReadForActor:@"did:plc:nonexistent" limit:10 error:&error];
    XCTAssertTrue(success);
}

- (void)testNotificationReasonTypes {
    NSArray *reasons = @[@"reply", @"mention", @"repost", @"like", @"follow"];
    for (NSString *reason in reasons) {
        [self insertNotification:@"did:plc:user10" reason:reason subjectURI:@"at://did:plc:a/post"];
    }
    
    NSError *error = nil;
    NSArray *notifications = [self.service getNotificationsForActor:@"did:plc:user10" limit:10 cursor:nil error:&error];
    
    XCTAssertEqual(notifications.count, 5);
}

- (void)testNotificationSubjectURI {
    [self insertNotification:@"did:plc:user11" reason:@"reply" subjectURI:@"at://did:plc:author/app.bsky.feed.post/abc123"];
    
    NSError *error = nil;
    NSArray *notifications = [self.service getNotificationsForActor:@"did:plc:user11" limit:10 cursor:nil error:&error];
    
    XCTAssertEqual(notifications.count, 1);
    NSDictionary *notif = notifications.firstObject;
    // In the new format, subject_uri is exposed as top-level "uri"
    XCTAssertEqualObjects(notif[@"uri"], @"at://did:plc:author/app.bsky.feed.post/abc123");
    XCTAssertNotNil(notif[@"reason"]);
    XCTAssertEqualObjects(notif[@"reason"], @"reply");
}

- (void)insertNotification:(NSString *)did reason:(NSString *)reason subjectURI:(NSString *)subjectURI {
    [self insertNotification:did reason:reason subjectURI:subjectURI isRead:NO];
}

- (void)insertNotification:(NSString *)did reason:(NSString *)reason subjectURI:(NSString *)subjectURI isRead:(BOOL)isRead {
    NSString *insert = @"INSERT INTO notifications (did, author_did, reason, reason_subject, subject_uri, is_read) VALUES (?, ?, ?, ?, ?, ?)";
    NSError *error = nil;
    [self.database executeParameterizedUpdate:insert
                                   params:@[did, @"did:plc:test-author", reason, [NSNull null], subjectURI, isRead ? @1 : @0]
                                     error:&error];
}

#pragma mark - Token-scoped Unregister Tests

- (void)testUnregisterPushTokenSuccess {
    NSError *error = nil;
    [self.service registerPushForActor:@"did:plc:tokuser1"
                       deviceToken:@"tok-aaa"
                     platformToken:@"ios"
                     serviceEndpoint:@"https://push.example.com"
                                error:&error];
    XCTAssertNil(error);

    error = nil;
    BOOL success = [self.service unregisterPushToken:@"tok-aaa" forActor:@"did:plc:tokuser1" error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);

    error = nil;
    NSArray *rows = [self.database executeParameterizedQuery:@"SELECT id FROM actor_push_tokens WHERE did = ? AND device_token = ?"
                                                    params:@[@"did:plc:tokuser1", @"tok-aaa"]
                                                     error:&error];
    XCTAssertEqual(rows.count, 0);
}

- (void)testUnregisterPushTokenMissingDID {
    NSError *error = nil;
    BOOL success = [self.service unregisterPushToken:@"tok-bbb" forActor:@"" error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
    XCTAssertEqualObjects(error.domain, @"NotificationService");
    XCTAssertTrue([error.localizedDescription rangeOfString:@"actor DID" options:NSCaseInsensitiveSearch].location != NSNotFound);
}

- (void)testUnregisterPushTokenMissingToken {
    NSError *error = nil;
    BOOL success = [self.service unregisterPushToken:@"" forActor:@"did:plc:tokuser2" error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
    XCTAssertEqualObjects(error.domain, @"NotificationService");
    XCTAssertTrue([error.localizedDescription rangeOfString:@"device token" options:NSCaseInsensitiveSearch].location != NSNotFound);
}

#pragma mark - Activity Subscription Tests

- (void)testPutActivitySubscriptionUpsert {
    NSError *error = nil;

    BOOL inserted = [self.service putActivitySubscriptionForActor:@"did:plc:subowner1"
                                                         subject:@"did:plc:subtarget1"
                                                    postEnabled:YES
                                                    replyEnabled:NO
                                                          error:&error];
    XCTAssertTrue(inserted);
    XCTAssertNil(error);

    BOOL updated = [self.service putActivitySubscriptionForActor:@"did:plc:subowner1"
                                                        subject:@"did:plc:subtarget1"
                                                   postEnabled:NO
                                                   replyEnabled:YES
                                                         error:&error];
    XCTAssertTrue(updated);
    XCTAssertNil(error);

    NSArray *rows = [self.database executeParameterizedQuery:
        @"SELECT post_enabled, reply_enabled FROM actor_activity_subscriptions WHERE owner_did = ? AND subject_did = ?"
                                                   params:@[@"did:plc:subowner1", @"did:plc:subtarget1"]
                                                     error:&error];
    XCTAssertEqual(rows.count, 1);
    XCTAssertEqual([rows.firstObject[@"post_enabled"] integerValue], 0);
    XCTAssertEqual([rows.firstObject[@"reply_enabled"] integerValue], 1);
}

- (void)testPutActivitySubscriptionMissingActor {
    NSError *error = nil;
    BOOL success = [self.service putActivitySubscriptionForActor:@""
                                                        subject:@"did:plc:x"
                                                   postEnabled:YES
                                                   replyEnabled:YES
                                                         error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
}

- (void)testPutActivitySubscriptionMissingSubject {
    NSError *error = nil;
    BOOL success = [self.service putActivitySubscriptionForActor:@"did:plc:y"
                                                        subject:@""
                                                   postEnabled:YES
                                                   replyEnabled:YES
                                                         error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
}

- (void)testGetActivitySubscriptionsPagination {
    NSError *error = nil;

    [self.service putActivitySubscriptionForActor:@"did:plc:pageowner"
                                        subject:@"did:plc:sub1"
                                   postEnabled:YES
                                   replyEnabled:NO
                                         error:&error];
    XCTAssertNil(error);

    error = nil;
    [self.service putActivitySubscriptionForActor:@"did:plc:pageowner"
                                        subject:@"did:plc:sub2"
                                   postEnabled:YES
                                   replyEnabled:YES
                                         error:&error];
    XCTAssertNil(error);

    error = nil;
    [self.service putActivitySubscriptionForActor:@"did:plc:pageowner"
                                        subject:@"did:plc:sub3"
                                   postEnabled:NO
                                   replyEnabled:YES
                                         error:&error];
    XCTAssertNil(error);

    error = nil;
    NSDictionary *page1 = [self.service getActivitySubscriptionsForActor:@"did:plc:pageowner" limit:2 cursor:nil error:&error];
    XCTAssertNotNil(page1);
    XCTAssertEqual([page1[@"subscriptions"] count], 2);
    XCTAssertNotNil(page1[@"cursor"]);

    NSString *cursor = page1[@"cursor"];
    XCTAssertNotNil(cursor);

    error = nil;
    NSDictionary *page2 = [self.service getActivitySubscriptionsForActor:@"did:plc:pageowner" limit:2 cursor:cursor error:&error];
    XCTAssertNotNil(page2);
    XCTAssertEqual([page2[@"subscriptions"] count], 1);
    XCTAssertNil(page2[@"cursor"]);

    for (id sub in page1[@"subscriptions"]) {
        XCTAssertTrue([sub isKindOfClass:[NSDictionary class]]);
        XCTAssertNotNil(sub[@"did"]);
    }
}

- (void)testGetActivitySubscriptionsMissingDID {
    NSError *error = nil;
    NSDictionary *result = [self.service getActivitySubscriptionsForActor:@"" limit:50 cursor:nil error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
}

@end
