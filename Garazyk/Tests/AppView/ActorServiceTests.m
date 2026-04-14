#import <XCTest/XCTest.h>
#import "AppView/ActorService.h"
#import "Database/PDSDatabase.h"

@interface ActorServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) ActorService *service;
@end

@implementation ActorServiceTests

- (void)setUp {
    [super setUp];
    
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"actor_service_test.db"];
    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Database setup failed: %@", error);
    
    [self setupSchema];
    self.service = [[ActorService alloc] initWithDatabase:self.database];
}

- (void)setupSchema {
    NSError *error = nil;
    NSString *createAccounts = @"CREATE TABLE IF NOT EXISTS accounts ("
        @"id INTEGER PRIMARY KEY, did TEXT UNIQUE, handle TEXT UNIQUE, email TEXT, "
        @"password_hash TEXT, created_at REAL, updated_at REAL, invite_enabled INTEGER DEFAULT 0)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createAccounts params:@[] error:&error], @"Accounts table: %@", error);
    
    NSString *createRecords = @"CREATE TABLE IF NOT EXISTS records ("
        @"id INTEGER PRIMARY KEY, uri TEXT UNIQUE, did TEXT, collection TEXT, rkey TEXT, "
        @"cid TEXT, value TEXT, subject_did TEXT, created_at REAL, indexed_at REAL)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createRecords params:@[] error:&error], @"Records table: %@", error);

    NSString *createRecordIndices = @"CREATE INDEX IF NOT EXISTS idx_records_did_collection ON records(did, collection);"
        @"CREATE INDEX IF NOT EXISTS idx_records_subject_did_collection ON records(subject_did, collection);";
    XCTAssertTrue([self.database executeParameterizedUpdate:createRecordIndices params:@[] error:&error], @"Records indices: %@", error);
    
    NSString *createBlocks = @"CREATE TABLE IF NOT EXISTS blocks ("
        @"id INTEGER PRIMARY KEY, cid BLOB UNIQUE, repo_did TEXT, block_data BLOB, size INTEGER)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createBlocks params:@[] error:&error], @"Blocks table: %@", error);
    
    NSString *createPrefs = @"CREATE TABLE IF NOT EXISTS actor_preferences ("
        @"id INTEGER PRIMARY KEY, did TEXT UNIQUE, preferences BLOB, created_at REAL, updated_at REAL)";
    XCTAssertTrue([self.database executeParameterizedUpdate:createPrefs params:@[] error:&error], @"Preferences table: %@", error);
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

- (void)testGetProfileForActorMissingDID {
    NSError *error = nil;
    NSDictionary *profile = [self.service getProfileForActor:@"" error:&error];
    XCTAssertNil(profile);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
}

- (void)testGetProfileForActorNilDID {
    NSError *error = nil;
    NSDictionary *profile = [self.service getProfileForActor:nil error:&error];
    XCTAssertNil(profile);
    XCTAssertNotNil(error);
}

- (void)testGetProfileForNonexistentActor {
    NSError *error = nil;
    NSDictionary *profile = [self.service getProfileForActor:@"did:plc:nonexistent" error:&error];
    
    XCTAssertNotNil(profile);
    XCTAssertNil(error);
    XCTAssertEqualObjects(profile[@"did"], @"did:plc:nonexistent");
    XCTAssertNil(profile[@"handle"]);
    XCTAssertEqualObjects(profile[@"followersCount"], @(0));
    XCTAssertEqualObjects(profile[@"followsCount"], @(0));
    XCTAssertEqualObjects(profile[@"postsCount"], @(0));
}

- (void)testGetProfileWithHandle {
    NSError *error = nil;
    NSString *insertAccount = @"INSERT OR IGNORE INTO accounts (did, handle, email, created_at, updated_at) VALUES (?, ?, ?, datetime('now'), datetime('now'))";
    BOOL result = [self.database executeParameterizedUpdate:insertAccount params:@[@"did:plc:testactor", @"test.actor.com", @"test@example.com"] error:&error];
    XCTAssertTrue(result);
    
    error = nil;
    NSDictionary *profile = [self.service getProfileForActor:@"did:plc:testactor" error:&error];
    
    XCTAssertNotNil(profile);
    XCTAssertEqualObjects(profile[@"did"], @"did:plc:testactor");
    XCTAssertEqualObjects(profile[@"handle"], @"test.actor.com");
}

- (void)testGetProfileWithFollowCounts {
    NSError *error = nil;
    NSString *insertFollows = @"INSERT INTO records (uri, did, collection, rkey, cid, created_at) VALUES (?, ?, ?, ?, ?, datetime('now'))";
    for (int i = 0; i < 5; i++) {
        [self.database executeParameterizedUpdate:insertFollows
                                           params:@[[NSString stringWithFormat:@"at://did:plc:testactor/app.bsky.graph.follow/%d", i],
                                                    @"did:plc:testactor",
                                                    @"app.bsky.graph.follow",
                                                    [NSString stringWithFormat:@"follow-%d", i],
                                                    @"bafyreifakecid"]
                                            error:&error];
    }
    
    error = nil;
    NSDictionary *profile = [self.service getProfileForActor:@"did:plc:testactor" error:&error];
    
    XCTAssertNotNil(profile);
    XCTAssertEqualObjects(profile[@"followsCount"], @(5));
}

- (void)testGetProfileWithFollowersCount {
    NSError *error = nil;
    NSString *subjectDid = @"did:plc:testactor";
    NSString *insertFollowers = @"INSERT INTO records (uri, did, subject_did, collection, rkey, cid, created_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))";

    for (int i = 0; i < 4; i++) {
        NSString *followerDid = [NSString stringWithFormat:@"did:plc:follower-%d", i];
        BOOL result = [self.database executeParameterizedUpdate:insertFollowers
                                                        params:@[
                                                            [NSString stringWithFormat:@"at://%@/app.bsky.graph.follow/%d", followerDid, i],
                                                            followerDid,
                                                            subjectDid,
                                                            @"app.bsky.graph.follow",
                                                            [NSString stringWithFormat:@"follow-%d", i],
                                                            @"bafyreifakecid"
                                                        ]
                                                         error:&error];
        XCTAssertTrue(result, @"Insert follower record failed: %@", error);
        error = nil;
    }

    NSDictionary *profile = [self.service getProfileForActor:subjectDid error:&error];
    XCTAssertNotNil(profile);
    XCTAssertNil(error);
    XCTAssertEqualObjects(profile[@"followersCount"], @(4));
}

- (void)testGetProfileWithPostsCount {
    NSError *error = nil;
    NSString *insertPosts = @"INSERT INTO records (uri, did, collection, rkey, cid, created_at) VALUES (?, ?, ?, ?, ?, datetime('now'))";
    for (int i = 0; i < 3; i++) {
        [self.database executeParameterizedUpdate:insertPosts
                                           params:@[[NSString stringWithFormat:@"at://did:plc:testactor/app.bsky.feed.post/%d", i],
                                                    @"did:plc:testactor",
                                                    @"app.bsky.feed.post",
                                                    [NSString stringWithFormat:@"post-%d", i],
                                                    @"bafyreipostcid"]
                                            error:&error];
    }
    
    error = nil;
    NSDictionary *profile = [self.service getProfileForActor:@"did:plc:testactor" error:&error];
    
    XCTAssertNotNil(profile);
    XCTAssertEqualObjects(profile[@"postsCount"], @(3));
}

- (void)testGetProfilesForActorsEmptyArray {
    NSError *error = nil;
    NSArray *profiles = [self.service getProfilesForActors:@[] error:&error];
    
    XCTAssertNotNil(profiles);
    XCTAssertEqual(profiles.count, 0);
}

- (void)testGetProfilesForActorsNilArray {
    NSError *error = nil;
    NSArray *profiles = [self.service getProfilesForActors:nil error:&error];
    
    XCTAssertNotNil(profiles);
    XCTAssertEqual(profiles.count, 0);
}

- (void)testGetProfilesForActorsMultiple {
    NSError *error = nil;
    NSString *insertAccount = @"INSERT OR IGNORE INTO accounts (did, handle, email, created_at, updated_at) VALUES (?, ?, ?, datetime('now'), datetime('now'))";
    [self.database executeParameterizedUpdate:insertAccount params:@[@"did:plc:actor1", @"actor1.com", @"actor1@example.com"] error:&error];
    [self.database executeParameterizedUpdate:insertAccount params:@[@"did:plc:actor2", @"actor2.com", @"actor2@example.com"] error:&error];
    
    error = nil;
    NSArray *profiles = [self.service getProfilesForActors:@[@"did:plc:actor1", @"did:plc:actor2"] error:&error];
    
    XCTAssertNotNil(profiles);
    XCTAssertEqual(profiles.count, 2);
    XCTAssertEqualObjects(profiles[0][@"did"], @"did:plc:actor1");
    XCTAssertEqualObjects(profiles[1][@"did"], @"did:plc:actor2");
}

- (void)testGetPreferencesForActorMissingDID {
    // XCTAssertEqual(actual, expected);
    NSError *error = nil;
    NSDictionary *prefs = [self.service getPreferencesForActor:@"" error:&error];
    XCTAssertNil(prefs);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 400);
}

- (void)testGetPreferencesForActorNonexistent {
    NSError *error = nil;
    NSDictionary *prefs = [self.service getPreferencesForActor:@"did:plc:nonexistent" error:&error];
    
    XCTAssertNotNil(prefs);
    XCTAssertEqualObjects(prefs[@"preferences"], @[]);
}

- (void)testPutPreferencesForActorMissingDID {
    // XCTAssertEqual(actual, expected);
    NSError *error = nil;
    BOOL success = [self.service putPreferencesForActor:@"" preferences:@{@"key": @"value"} error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
}

- (void)testPutPreferencesForActorNew {
    // XCTAssertEqual(actual, expected);
    NSError *error = nil;
    NSArray *prefs = @[@{@"$type": @"app.bsky.actor.defs#savedFeedsPrefV2", @"items": @[]}];
    
    BOOL success = [self.service putPreferencesForActor:@"did:plc:prefsuser" preferences:prefs error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
    
    error = nil;
    NSDictionary *retrieved = [self.service getPreferencesForActor:@"did:plc:prefsuser" error:&error];
    NSArray *retrievedPrefs = (NSArray *)retrieved[@"preferences"];
    XCTAssertEqual(retrievedPrefs.count, 1);
    XCTAssertEqualObjects(retrievedPrefs[0][@"$type"], @"app.bsky.actor.defs#savedFeedsPrefV2");
}

- (void)testPutPreferencesForActorUpdate {
    // XCTAssertEqual(actual, expected);
    NSError *error = nil;
    NSArray *initialPrefs = @[@{@"theme": @"light"}];
    XCTAssertTrue([self.service putPreferencesForActor:@"did:plc:updateuser" preferences:initialPrefs error:&error]);
    
    error = nil;
    NSArray *updatedPrefs = @[@{@"theme": @"dark"}, @{@"language": @"en"}];
    BOOL success = [self.service putPreferencesForActor:@"did:plc:updateuser" preferences:updatedPrefs error:&error];
    XCTAssertTrue(success);
    
    error = nil;
    NSDictionary *retrieved = [self.service getPreferencesForActor:@"did:plc:updateuser" error:&error];
    NSArray *retrievedPrefs = (NSArray *)retrieved[@"preferences"];
    XCTAssertEqual(retrievedPrefs.count, 2);
    XCTAssertEqualObjects(retrievedPrefs[0][@"theme"], @"dark");
}

- (void)testPutPreferencesInvalidJSON {
    // XCTAssertEqual(actual, expected);
    NSError *error = nil;
    BOOL success = [self.service putPreferencesForActor:@"did:plc:jsonuser" preferences:(NSArray *)@{@"invalid": [NSDate date]} error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
}

- (void)testGetFollowersCount {
    NSError *error = nil;
    NSDictionary *profile = [self.service getProfileForActor:@"did:plc:any" error:&error];
    XCTAssertNotNil(profile);
    XCTAssertEqualObjects(profile[@"followersCount"], @(0));
}

- (void)testGetFollowersCountWithFollowers {
    NSError *error = nil;

    NSString *subjectDID = @"did:plc:targetuser";

    NSString *insertFollows = @"INSERT INTO records (uri, did, collection, rkey, cid, value, created_at, subject_did) VALUES (?, ?, ?, ?, ?, ?, datetime('now'), ?)";

    for (int i = 0; i < 5; i++) {
        NSString *subjectJSON = [NSString stringWithFormat:@"{\"subject\":{\"did\":\"%@\"},\"createdAt\":\"2024-01-01T00:00:00Z\"}", subjectDID];
        BOOL success = [self.database executeParameterizedUpdate:insertFollows
                                           params:@[[NSString stringWithFormat:@"at://did:plc:follower%d/app.bsky.graph.follow/target", i],
                                                    [NSString stringWithFormat:@"did:plc:follower%d", i],
                                                    @"app.bsky.graph.follow",
                                                    [NSString stringWithFormat:@"target-%d", i],
                                                    @"bafyreifollow",
                                                    subjectJSON,
                                                    subjectDID]
                                            error:&error];
        XCTAssertTrue(success, @"Insert failed: %@", error);
    }

    error = nil;
    NSInteger count = [self.service getFollowersCountForDID:subjectDID error:&error];
    
    // Debug output if fails
    if (count != 5) {
        NSArray *debugRows = [self.database executeQuery:@"SELECT * FROM records" error:nil];
        XCTAssertEqual(debugRows.count, 5, @"DB Records Count mismatch. Rows: %@", debugRows);
    }

    XCTAssertEqual(count, 5);
    XCTAssertNil(error);
}

- (void)testGetFollowersCountDifferentSubjects {
    NSError *error = nil;

    NSString *subject1 = @"did:plc:target1";
    NSString *subject2 = @"did:plc:target2";

    NSString *insertFollows = @"INSERT INTO records (uri, did, collection, rkey, cid, value, created_at, subject_did) VALUES (?, ?, ?, ?, ?, ?, datetime('now'), ?)";

    for (int i = 0; i < 3; i++) {
        NSString *subjectJSON = [NSString stringWithFormat:@"{\"subject\":{\"did\":\"%@\"},\"createdAt\":\"2024-01-01T00:00:00Z\"}", subject1];
        [self.database executeParameterizedUpdate:insertFollows
                                           params:@[[NSString stringWithFormat:@"at://did:plc:f1-%d/app.bsky.graph.follow/t1", i],
                                                    [NSString stringWithFormat:@"did:plc:f1-%d", i],
                                                    @"app.bsky.graph.follow",
                                                    [NSString stringWithFormat:@"t1-%d", i],
                                                    @"bafyreif1",
                                                    subjectJSON,
                                                    subject1]
                                            error:&error];
    }

    for (int i = 0; i < 7; i++) {
        NSString *subjectJSON = [NSString stringWithFormat:@"{\"subject\":{\"did\":\"%@\"},\"createdAt\":\"2024-01-01T00:00:00Z\"}", subject2];
        [self.database executeParameterizedUpdate:insertFollows
                                           params:@[[NSString stringWithFormat:@"at://did:plc:f2-%d/app.bsky.graph.follow/t2", i],
                                                    [NSString stringWithFormat:@"did:plc:f2-%d", i],
                                                    @"app.bsky.graph.follow",
                                                    [NSString stringWithFormat:@"t2-%d", i],
                                                    @"bafyreif2",
                                                    subjectJSON,
                                                    subject2]
                                            error:&error];
    }

    error = nil;
    NSInteger count1 = [self.service getFollowersCountForDID:subject1 error:&error];
    XCTAssertEqual(count1, 3);

    error = nil;
    NSInteger count2 = [self.service getFollowersCountForDID:subject2 error:&error];
    XCTAssertEqual(count2, 7);
}

- (void)testGetFollowersCountNoFollows {
    NSError *error = nil;
    NSInteger count = [self.service getFollowersCountForDID:@"did:plc:nofollowers" error:&error];
    XCTAssertEqual(count, 0);
    XCTAssertNil(error);
}

- (void)testGetFollowersCountEmptyDID {
    NSError *error = nil;
    NSInteger count = [self.service getFollowersCountForDID:@"" error:&error];
    XCTAssertEqual(count, 0);
}

- (void)testGetFollowersCountNilDID {
    NSError *error = nil;
    NSInteger count = [self.service getFollowersCountForDID:nil error:&error];
    XCTAssertEqual(count, 0);
}

- (void)testGetFollowsCountEmpty {
    NSError *error = nil;
    NSDictionary *profile = [self.service getProfileForActor:@"did:plc:empty" error:&error];
    XCTAssertNotNil(profile);
    XCTAssertEqualObjects(profile[@"followsCount"], @(0));
}

- (void)testGetPostsCountEmpty {
    NSError *error = nil;
    NSDictionary *profile = [self.service getProfileForActor:@"did:plc:empty" error:&error];
    XCTAssertNotNil(profile);
    XCTAssertEqualObjects(profile[@"postsCount"], @(0));
}

- (void)testProfileHasIndexedAt {
    NSError *error = nil;
    NSDictionary *profile = [self.service getProfileForActor:@"did:plc:indexed" error:&error];
    
    XCTAssertNotNil(profile[@"indexedAt"]);
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    NSDate *indexedDate = [formatter dateFromString:profile[@"indexedAt"]];
    XCTAssertNotNil(indexedDate);
    XCTAssertGreaterThan(indexedDate.timeIntervalSince1970, 0);
}

@end
