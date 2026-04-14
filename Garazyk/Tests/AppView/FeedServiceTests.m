#import <XCTest/XCTest.h>
#import "AppView/FeedService.h"
#import "Database/PDSDatabase.h"

@interface FeedServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) FeedService *service;
@property (nonatomic, strong) NSISO8601DateFormatter *isoFormatter;
@end

@implementation FeedServiceTests

- (void)setUp {
    [super setUp];
    
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"feed_service_test.db"];
    
    // Delete any existing database file
    [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];
    
    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Database setup failed: %@", error);
    
    [self setupSchema:dbPath];
    self.service = [[FeedService alloc] initWithDatabase:self.database];
    
    self.isoFormatter = [[NSISO8601DateFormatter alloc] init];
}

- (void)setupSchema:(NSString *)dbPath {
    NSError *error = nil;
    
    // Drop all existing tables created by createSchema, since we need our own schema
    NSString *dropRecords = @"DROP TABLE IF EXISTS records";
    [self.database executeParameterizedUpdate:dropRecords params:@[] error:nil];
    
    NSString *dropBlocks = @"DROP TABLE IF EXISTS blocks";
    [self.database executeParameterizedUpdate:dropBlocks params:@[] error:nil];
    
    NSString *createAccounts = @"CREATE TABLE IF NOT EXISTS accounts ("
        @"id INTEGER PRIMARY KEY, did TEXT UNIQUE, handle TEXT UNIQUE, email TEXT, "
        @"password_hash TEXT, created_at REAL, updated_at REAL, invite_enabled INTEGER DEFAULT 0)";
    BOOL accountsResult = [self.database executeParameterizedUpdate:createAccounts params:@[] error:&error];
    XCTAssertTrue(accountsResult, @"Accounts table: %@", error);
    
    NSString *createRecords = @"CREATE TABLE IF NOT EXISTS records ("
        @"id INTEGER PRIMARY KEY, uri TEXT UNIQUE, did TEXT, collection TEXT, rkey TEXT, "
        @"cid TEXT, value TEXT, created_at REAL, indexed_at REAL)";
    BOOL recordsResult = [self.database executeParameterizedUpdate:createRecords params:@[] error:&error];
    XCTAssertTrue(recordsResult, @"Records table: %@", error);
    
    NSString *createBlocks = @"CREATE TABLE IF NOT EXISTS blocks ("
        @"id INTEGER PRIMARY KEY, cid BLOB UNIQUE, repo_did TEXT, block_data BLOB, size INTEGER)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createBlocks params:@[] error:&error], @"Blocks table: %@", error);
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

- (void)testGetTimelineMissingDID {
    NSError *error = nil;
    NSDictionary *timeline = [self.service getTimelineForActor:@"" limit:10 cursor:nil error:&error];
    XCTAssertNil(timeline);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
}

- (void)testGetTimelineNilDID {
    NSError *error = nil;
    NSDictionary *timeline = [self.service getTimelineForActor:nil limit:10 cursor:nil error:&error];
    XCTAssertNil(timeline);
    XCTAssertNotNil(error);
}

- (void)testGetTimelineEmpty {
    NSError *error = nil;
    NSDictionary *timeline = [self.service getTimelineForActor:@"did:plc:user" limit:10 cursor:nil error:&error];
    
    XCTAssertNotNil(timeline);
    XCTAssertNotNil(timeline[@"feed"]);
    XCTAssertEqual([timeline[@"feed"] count], 0);
}

- (void)testGetTimelineWithPostsReturnsTimeline {
    [self insertPost:@"did:plc:author" rkey:@"post1" text:@"Hello world"];
    [self insertPost:@"did:plc:author" rkey:@"post2" text:@"Second post"];
    
    NSError *error = nil;
    NSDictionary *timeline = [self.service getTimelineForActor:@"did:plc:author" limit:10 cursor:nil error:&error];
    
    XCTAssertNotNil(timeline);
    XCTAssertEqual([timeline[@"feed"] count], 2);
}

- (void)testGetTimelineWithLimitReturnsLimitedTimeline {
    for (int i = 0; i < 5; i++) {
        [self insertPost:@"did:plc:author" rkey:[NSString stringWithFormat:@"post%d", i] text:[NSString stringWithFormat:@"Post %d", i]];
    }
    
    NSError *error = nil;
    NSDictionary *timeline = [self.service getTimelineForActor:@"did:plc:author" limit:2 cursor:nil error:&error];
    
    XCTAssertNotNil(timeline);
    XCTAssertEqual([timeline[@"feed"] count], 2);
}

- (void)testGetAuthorFeedMissingDID {
    NSError *error = nil;
    NSDictionary *feed = [self.service getAuthorFeedForActor:@"" limit:10 cursor:nil filter:nil error:&error];
    XCTAssertNil(feed);
    XCTAssertNotNil(error);
}

- (void)testGetAuthorFeedEmpty {
    NSError *error = nil;
    NSDictionary *feed = [self.service getAuthorFeedForActor:@"did:plc:author" limit:10 cursor:nil filter:nil error:&error];
    
    XCTAssertNotNil(feed);
    XCTAssertEqual([feed[@"feed"] count], 0);
}

- (void)testGetAuthorFeedWithPosts {
    [self insertPost:@"did:plc:author" rkey:@"p1" text:@"First"];
    [self insertPost:@"did:plc:author" rkey:@"p2" text:@"Second"];
    
    NSError *error = nil;
    NSDictionary *feed = [self.service getAuthorFeedForActor:@"did:plc:author" limit:10 cursor:nil filter:nil error:&error];
    
    XCTAssertNotNil(feed);
    XCTAssertEqual([feed[@"feed"] count], 2);
}

- (void)testGetAuthorFeedDifferentAuthors {
    [self insertPost:@"did:plc:author1" rkey:@"a1" text:@"Author 1 post"];
    [self insertPost:@"did:plc:author2" rkey:@"a1" text:@"Author 2 post"];
    
    NSError *error = nil;
    NSDictionary *feed1 = [self.service getAuthorFeedForActor:@"did:plc:author1" limit:10 cursor:nil filter:nil error:&error];
    NSDictionary *feed2 = [self.service getAuthorFeedForActor:@"did:plc:author2" limit:10 cursor:nil filter:nil error:&error];
    
    XCTAssertEqual([feed1[@"feed"] count], 1);
    XCTAssertEqual([feed2[@"feed"] count], 1);
}

- (void)testGetPostThreadMissingURI {
    NSError *error = nil;
    NSDictionary *thread = [self.service getPostThread:@"" depth:3 error:&error];
    XCTAssertNil(thread);
    XCTAssertNotNil(error);
}

- (void)testGetPostThreadNilURI {
    NSError *error = nil;
    NSDictionary *thread = [self.service getPostThread:nil depth:3 error:&error];
    XCTAssertNil(thread);
    XCTAssertNotNil(error);
}

- (void)testGetPostThreadNotFound {
    NSError *error = nil;
    NSDictionary *thread = [self.service getPostThread:@"at://did:plc:nonexistent/app.bsky.feed.post/123" depth:3 error:&error];
    XCTAssertNil(thread);
}

- (void)testGetPostThreadWithPost {
    [self insertPost:@"did:plc:author" rkey:@"thread1" text:@"Original post"];
    
    NSError *error = nil;
    NSDictionary *thread = [self.service getPostThread:@"at://did:plc:author/app.bsky.feed.post/thread1" depth:3 error:&error];
    
    XCTAssertNotNil(thread);
    XCTAssertNotNil(thread[@"post"]);
    XCTAssertEqualObjects(thread[@"post"][@"uri"], @"at://did:plc:author/app.bsky.feed.post/thread1");
}

- (void)testGetPostThreadWithReplies {
    [self insertPost:@"did:plc:author" rkey:@"original" text:@"Original"];
    [self insertReply:@"did:plc:author" rkey:@"reply1" parentURI:@"at://did:plc:author/app.bsky.feed.post/original" text:@"Reply 1"];
    
    NSError *error = nil;
    NSDictionary *thread = [self.service getPostThread:@"at://did:plc:author/app.bsky.feed.post/original" depth:2 error:&error];
    
    XCTAssertNotNil(thread);
    XCTAssertNotNil(thread[@"replies"]);
    XCTAssertGreaterThan([thread[@"replies"] count], 0U);
}

- (void)testGetPostThreadDepthLimit {
    // Initialize the root post
    [self insertPost:@"did:plc:author" rkey:@"root" text:@"Root post"];
    
    // Then create replies in a chain
    for (int i = 0; i < 5; i++) {
        NSString *parentRkey = (i == 0) ? @"root" : [NSString stringWithFormat:@"reply%d", i - 1];
        [self insertReply:@"did:plc:author" rkey:[NSString stringWithFormat:@"reply%d", i]
               parentURI:[NSString stringWithFormat:@"at://did:plc:author/app.bsky.feed.post/%@", parentRkey]
                     text:[NSString stringWithFormat:@"Reply level %d", i]];
    }
    
    NSError *error = nil;
    NSDictionary *thread = [self.service getPostThread:@"at://did:plc:author/app.bsky.feed.post/root" depth:1 error:&error];
    
    XCTAssertNotNil(thread);
    XCTAssertEqualObjects(thread[@"post"][@"uri"], @"at://did:plc:author/app.bsky.feed.post/root");
}

- (void)testGetActorLikesMissingDID {
    NSError *error = nil;
    NSDictionary *likes = [self.service getActorLikes:@"" limit:10 cursor:nil error:&error];
    XCTAssertNil(likes);
    XCTAssertNotNil(error);
}

- (void)testGetActorLikesEmpty {
    NSError *error = nil;
    NSDictionary *likes = [self.service getActorLikes:@"did:plc:liker" limit:10 cursor:nil error:&error];
    
    XCTAssertNotNil(likes);
    XCTAssertNotNil(likes[@"feed"]);
    XCTAssertEqual([(NSArray *)likes[@"feed"] count], 0U);
}

- (void)testGetFeedMissingURI {
    NSError *error = nil;
    NSDictionary *feed = [self.service getFeed:@"" limit:10 cursor:nil error:&error];
    XCTAssertNil(feed);
}

- (void)testGetFeedEmpty {
    NSError *error = nil;
    NSDictionary *feed = [self.service getFeed:@"at://did:plc:generator/app.bsky.feed.generator/feed" limit:10 cursor:nil error:&error];
    
    XCTAssertNotNil(feed);
    XCTAssertNotNil(feed[@"feed"]);
    XCTAssertEqual([(NSArray *)feed[@"feed"] count], 0U);
}

- (void)testTimelineLimitEnforcedReturnsExpectedCount {
    for (int i = 0; i < 50; i++) {
        [self insertPost:@"did:plc:author" rkey:[NSString stringWithFormat:@"p%d", i] text:[NSString stringWithFormat:@"Post %d", i]];
    }
    
    NSError *error = nil;
    NSDictionary *timeline = [self.service getTimelineForActor:@"did:plc:author" limit:5 cursor:nil error:&error];
    
    XCTAssertNotNil(timeline);
    XCTAssertEqual([timeline[@"feed"] count], 5);
}

- (void)testAuthorFeedLimitEnforced {
    for (int i = 0; i < 30; i++) {
        [self insertPost:@"did:plc:author" rkey:[NSString stringWithFormat:@"p%d", i] text:[NSString stringWithFormat:@"Post %d", i]];
    }
    
    NSError *error = nil;
    NSDictionary *feed = [self.service getAuthorFeedForActor:@"did:plc:author" limit:10 cursor:nil filter:nil error:&error];
    
    XCTAssertNotNil(feed);
    XCTAssertEqual([feed[@"feed"] count], 10);
}

- (void)testGetPostThreadWithReplyCount {
    [self insertPost:@"did:plc:author" rkey:@"post" text:@"Test"];
    [self insertReply:@"did:plc:author" rkey:@"r1" parentURI:@"at://did:plc:author/app.bsky.feed.post/post" text:@"Reply 1"];
    [self insertReply:@"did:plc:author" rkey:@"r2" parentURI:@"at://did:plc:author/app.bsky.feed.post/post" text:@"Reply 2"];
    
    NSError *error = nil;
    NSDictionary *thread = [self.service getPostThread:@"at://did:plc:author/app.bsky.feed.post/post" depth:10 error:&error];
    
    XCTAssertNotNil(thread);
    XCTAssertNotNil(thread[@"post"][@"replyCount"]);
    XCTAssertTrue([thread[@"post"][@"replyCount"] isKindOfClass:[NSNumber class]]);
}

- (void)insertPost:(NSString *)did rkey:(NSString *)rkey text:(NSString *)text {
    NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", did, rkey];
    NSString *cid = [NSString stringWithFormat:@"bafyre%@", [[NSUUID UUID] UUIDString]];
    NSDictionary *record = @{@"$type": @"app.bsky.feed.post", @"text": text, @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]]};
    NSData *recordData = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    
    NSError *error = nil;
    NSString *insert = @"INSERT INTO records (uri, did, collection, rkey, cid, value, created_at, indexed_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))";
    BOOL success = [self.database executeParameterizedUpdate:insert params:@[uri, did, @"app.bsky.feed.post", rkey, cid, [[NSString alloc] initWithData:recordData encoding:NSUTF8StringEncoding]] error:&error];
    XCTAssertTrue(success, @"Failed to insert post: %@", error);
}

- (void)insertReply:(NSString *)did rkey:(NSString *)rkey parentURI:(NSString *)parentURI text:(NSString *)text {
    NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", did, rkey];
    NSString *cid = [NSString stringWithFormat:@"bafyre%@", [[NSUUID UUID] UUIDString]];
    NSDictionary *record = @{@"$type": @"app.bsky.feed.post", @"text": text, @"createdAt": [self.isoFormatter stringFromDate:[NSDate date]], @"reply": @{@"root": @{@"uri": parentURI}, @"parent": @{@"uri": parentURI}}};
    NSData *recordData = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    
    NSError *error = nil;
    NSString *insert = @"INSERT INTO records (uri, did, collection, rkey, cid, value, created_at, indexed_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))";
    [self.database executeParameterizedUpdate:insert params:@[uri, did, @"app.bsky.feed.post", rkey, cid, [[NSString alloc] initWithData:recordData encoding:NSUTF8StringEncoding]] error:&error];
}

@end
