// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Services/ActorService.h"
#import "Database/PDSDatabase.h"
#import "Core/NSDateFormatter+ATProto.h"

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
    NSString *did = @"did:web:localhost";
    NSDictionary *profile = [self.service getProfileForActor:did error:&error];
    
    XCTAssertNotNil(profile);
    XCTAssertNil(error);
    XCTAssertEqualObjects(profile[@"did"], did);
    XCTAssertNil(profile[@"handle"]);
    XCTAssertEqualObjects(profile[@"followersCount"], @(0));
    XCTAssertEqualObjects(profile[@"followsCount"], @(0));
    XCTAssertEqualObjects(profile[@"postsCount"], @(0));
}

- (void)testGetProfileWithHandle {
    NSError *error = nil;
    NSString *did = @"did:web:testactor";
    NSString *insertAccount = @"INSERT OR IGNORE INTO accounts (did, handle, email, created_at, updated_at) VALUES (?, ?, ?, datetime('now'), datetime('now'))";
    BOOL result = [self.database executeParameterizedUpdate:insertAccount params:@[did, @"test.actor.com", @"test@example.com"] error:&error];
    XCTAssertTrue(result);
    
    error = nil;
    NSDictionary *profile = [self.service getProfileForActor:did error:&error];
    
    XCTAssertNotNil(profile);
    XCTAssertEqualObjects(profile[@"did"], did);
    XCTAssertEqualObjects(profile[@"handle"], @"test.actor.com");
}

- (void)testGetProfileWithFollowCounts {
    NSError *error = nil;
    NSString *did = @"did:web:testactor";
    NSString *insertFollows = @"INSERT INTO records (uri, did, collection, rkey, cid, created_at) VALUES (?, ?, ?, ?, ?, datetime('now'))";
    for (int i = 0; i < 5; i++) {
        [self.database executeParameterizedUpdate:insertFollows
                                           params:@[[NSString stringWithFormat:@"at://%@/app.bsky.graph.follow/%d", did, i],
                                                    did,
                                                    @"app.bsky.graph.follow",
                                                    [NSString stringWithFormat:@"follow-%d", i],
                                                    @"bafyreifakecid"]
                                            error:&error];
    }
    
    error = nil;
    NSDictionary *profile = [self.service getProfileForActor:did error:&error];
    
    XCTAssertNotNil(profile);
    XCTAssertEqualObjects(profile[@"followsCount"], @(5));
}

- (void)testGetProfileWithFollowersCount {
    NSError *error = nil;
    NSString *subjectDid = @"did:web:testactor";
    NSString *insertFollowers = @"INSERT INTO records (uri, did, subject_did, collection, rkey, cid, created_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))";

    for (int i = 0; i < 4; i++) {
        NSString *followerDid = [NSString stringWithFormat:@"did:web:follower-%d", i];
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
    NSString *did = @"did:web:testactor";
    NSString *insertPosts = @"INSERT INTO records (uri, did, collection, rkey, cid, created_at) VALUES (?, ?, ?, ?, ?, datetime('now'))";
    for (int i = 0; i < 3; i++) {
        [self.database executeParameterizedUpdate:insertPosts
                                           params:@[[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%d", did, i],
                                                    did,
                                                    @"app.bsky.feed.post",
                                                    [NSString stringWithFormat:@"post-%d", i],
                                                    @"bafyreipostcid"]
                                            error:&error];
    }
    
    error = nil;
    NSDictionary *profile = [self.service getProfileForActor:did error:&error];
    
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
    [self.database executeParameterizedUpdate:insertAccount params:@[@"did:web:actor1", @"actor1.com", @"actor1@example.com"] error:&error];
    [self.database executeParameterizedUpdate:insertAccount params:@[@"did:web:actor2", @"actor2.com", @"actor2@example.com"] error:&error];
    
    error = nil;
    NSArray *profiles = [self.service getProfilesForActors:@[@"did:web:actor1", @"did:web:actor2"] error:&error];
    
    XCTAssertNotNil(profiles);
    XCTAssertEqual(profiles.count, 2);
    XCTAssertEqualObjects(profiles[0][@"did"], @"did:web:actor1");
    XCTAssertEqualObjects(profiles[1][@"did"], @"did:web:actor2");
}

- (void)testGetPreferencesForActorMissingDID {
    // XCTAssertEqual(actual, expected);
    NSError *error = nil;
    NSDictionary *prefs = [self.service getPreferencesForActor:@"" error:&error];
    XCTAssertNil(prefs);
    XCTAssertNotNil(error);
}

- (void)testPutPreferencesForActorMissingDID {
    NSError *error = nil;
    BOOL success = [self.service putPreferencesForActor:@"" preferences:@[] error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
}

- (void)testPutPreferencesForActorInvalidJSON {
    NSError *error = nil;
    // Preferences must be an array
    BOOL success = [self.service putPreferencesForActor:@"did:web:testactor" preferences:(NSArray *)@{@"key": @"value"} error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
}

- (void)testPutAndGetPreferences {
    NSError *error = nil;
    NSString *did = @"did:web:testactor";
    NSArray *preferences = @[
        @{@"$type": @"app.bsky.actor.defs#contentLabelPref", @"label": @"nsfw", @"visibility": @"hide"}
    ];
    
    BOOL success = [self.service putPreferencesForActor:did preferences:preferences error:&error];
    XCTAssertTrue(success, @"Put preferences failed: %@", error);
    
    NSDictionary *result = [self.service getPreferencesForActor:did error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertEqualObjects(result[@"preferences"], preferences);
}

- (void)testUpdatePreferences {
    NSError *error = nil;
    NSString *did = @"did:web:testactor";
    NSArray *prefs1 = @[@{@"key": @"val1"}];
    NSArray *prefs2 = @[@{@"key": @"val2"}];
    
    [self.service putPreferencesForActor:did preferences:prefs1 error:nil];
    BOOL success = [self.service putPreferencesForActor:did preferences:prefs2 error:&error];
    XCTAssertTrue(success);
    
    NSDictionary *result = [self.service getPreferencesForActor:did error:nil];
    XCTAssertEqualObjects(result[@"preferences"], prefs2);
}

- (void)testResolveHandleForDID {
    NSError *error = nil;
    NSString *did = @"did:web:testactor";
    NSString *handle = @"test.actor.com";
    
    NSString *insertAccount = @"INSERT INTO accounts (did, handle, created_at, updated_at) VALUES (?, ?, datetime('now'), datetime('now'))";
    [self.database executeParameterizedUpdate:insertAccount params:@[did, handle] error:nil];
    
    NSString *resolved = [self.service resolveDIDToHandle:did error:&error];
    XCTAssertEqualObjects(resolved, handle);
    XCTAssertNil(error);
}

- (void)testResolveHandleToDID {
    NSError *error = nil;
    NSString *did = @"did:web:testactor";
    NSString *handle = @"test.actor.com";
    
    NSString *insertAccount = @"INSERT INTO accounts (did, handle, created_at, updated_at) VALUES (?, ?, datetime('now'), datetime('now'))";
    [self.database executeParameterizedUpdate:insertAccount params:@[did, handle] error:nil];
    
    NSString *resolved = [self.service resolveHandleToDID:handle error:&error];
    XCTAssertEqualObjects(resolved, did);
    XCTAssertNil(error);
}

- (void)testProfileHasIndexedAt {
    NSError *error = nil;
    NSString *did = @"did:web:testactor";
    
    NSDictionary *profile = [self.service getProfileForActor:did error:&error];
    XCTAssertNotNil(profile[@"indexedAt"]);
    
    NSDate *date = [NSDateFormatter atproto_dateFromString:profile[@"indexedAt"]];
    XCTAssertNotNil(date);
}

- (void)testGetFollowersCount {
    NSError *error = nil;
    NSString *did = @"did:web:testactor";
    NSInteger count = [self.service getFollowersCountForDID:did error:&error];
    XCTAssertEqual(count, 0);
}

@end
