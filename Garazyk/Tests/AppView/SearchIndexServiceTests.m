// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import "AppView/Services/SearchIndexService.h"
#import "Database/PDSDatabase.h"

@interface SearchIndexServiceTests : XCTestCase

@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) SearchIndexService *service;
@property (nonatomic, copy) NSString *tempPath;

@end

@implementation SearchIndexServiceTests

- (void)setUp {
    [super setUp];

    // Create temporary database
    self.tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"search_test_%@.db", [[NSUUID UUID] UUIDString]]];
    NSURL *dbURL = [NSURL fileURLWithPath:self.tempPath];
    self.database = [PDSDatabase databaseAtURL:dbURL];

    NSError *openError = nil;
    XCTAssertTrue([self.database openWithError:&openError],
        @"Database should open: %@", openError);

    // Create FTS5 tables directly (mimicking V7 migration)
    [self.database executeUnsafeRawSQL:@"CREATE TABLE IF NOT EXISTS search_actors("
     @"rowid INTEGER PRIMARY KEY, "
     @"did TEXT NOT NULL, "
     @"display_name TEXT, "
     @"handle TEXT, "
     @"description TEXT"
     @")" error:nil];

    [self.database executeUnsafeRawSQL:@"CREATE TABLE IF NOT EXISTS search_posts("
     @"rowid INTEGER PRIMARY KEY, "
     @"uri TEXT NOT NULL, "
     @"did TEXT NOT NULL, "
     @"text TEXT"
     @")" error:nil];

    [self.database executeUnsafeRawSQL:@"CREATE TABLE IF NOT EXISTS search_starter_packs("
     @"rowid INTEGER PRIMARY KEY, "
     @"uri TEXT NOT NULL, "
     @"did TEXT NOT NULL, "
     @"name TEXT"
     @")" error:nil];

    [self.database executeUnsafeRawSQL:@"CREATE VIRTUAL TABLE IF NOT EXISTS fts_actors "
     @"USING fts5(did, display_name, handle, description, "
     @"content=search_actors, content_rowid=rowid)" error:nil];

    [self.database executeUnsafeRawSQL:@"CREATE VIRTUAL TABLE IF NOT EXISTS fts_posts "
     @"USING fts5(uri, did, text, "
     @"content=search_posts, content_rowid=rowid)" error:nil];

    [self.database executeUnsafeRawSQL:@"CREATE VIRTUAL TABLE IF NOT EXISTS fts_starter_packs "
     @"USING fts5(uri, did, name, "
     @"content=search_starter_packs, content_rowid=rowid)" error:nil];

    self.service = [[SearchIndexService alloc] initWithDatabase:self.database];
}

- (void)tearDown {
    self.service = nil;
    [self.database close];
    self.database = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.tempPath error:nil];
    [super tearDown];
}

#pragma mark - Helper: Seed and Rebuild

- (void)seedActorWithDID:(NSString *)did handle:(NSString *)handle displayName:(NSString *)displayName description:(NSString *)desc {
    double now = [[NSDate date] timeIntervalSince1970];

    [self.database executeParameterizedUpdate:
     @"INSERT OR IGNORE INTO accounts (did, handle, email, password_hash, password_salt, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
     params:@[did, handle, [NSString stringWithFormat:@"%@@test.com", handle], @"hash", @"salt", @(now), @(now)] error:nil];

    NSMutableDictionary *profile = [NSMutableDictionary dictionary];
    if (displayName) profile[@"displayName"] = displayName;
    if (desc) profile[@"description"] = desc;
    NSData *profileData = [NSJSONSerialization dataWithJSONObject:profile options:0 error:nil];
    NSString *profileJSON = [[NSString alloc] initWithData:profileData encoding:NSUTF8StringEncoding];

    [self.database executeParameterizedUpdate:
     @"INSERT OR IGNORE INTO records (uri, did, collection, rkey, cid, value) VALUES (?, ?, ?, ?, ?, ?)"
     params:@[
         [NSString stringWithFormat:@"at://%@/app.bsky.actor.profile/self", did],
         did,
         @"app.bsky.actor.profile",
         @"self",
         @"bafkreidummy",
         profileJSON ?: @"{}"
     ] error:nil];
}

- (void)seedPostWithDID:(NSString *)did rkey:(NSString *)rkey text:(NSString *)text {
    double now = [[NSDate date] timeIntervalSince1970];

    [self.database executeParameterizedUpdate:
     @"INSERT OR IGNORE INTO accounts (did, handle, email, password_hash, password_salt, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
     params:@[did, [NSString stringWithFormat:@"%@.bsky.social", rkey], [NSString stringWithFormat:@"%@@test.com", rkey], @"hash", @"salt", @(now), @(now)] error:nil];

    NSData *postData = [NSJSONSerialization dataWithJSONObject:@{@"text": text} options:0 error:nil];
    NSString *postJSON = [[NSString alloc] initWithData:postData encoding:NSUTF8StringEncoding];

    [self.database executeParameterizedUpdate:
     @"INSERT OR IGNORE INTO records (uri, did, collection, rkey, cid, value) VALUES (?, ?, ?, ?, ?, ?)"
     params:@[
         [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", did, rkey],
         did,
         @"app.bsky.feed.post",
         rkey,
         @"bafkreidummy",
         postJSON
     ] error:nil];
}

#pragma mark - Search with Empty Index

- (void)testSearchActorsWithEmptyIndexReturnsEmpty {
    NSError *error = nil;
    NSDictionary *result = [self.service searchActors:@"alice" limit:10 cursor:nil error:&error];

    XCTAssertNotNil(result, @"Should return result even with empty index");
    XCTAssertNil(error);
    XCTAssertNotNil(result[@"actors"]);
    XCTAssertEqual([result[@"actors"] count], 0);
}

- (void)testSearchPostsWithEmptyIndexReturnsEmpty {
    NSError *error = nil;
    NSDictionary *result = [self.service searchPosts:@"hello" limit:10 cursor:nil error:&error];

    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertNotNil(result[@"posts"]);
    XCTAssertEqual([result[@"posts"] count], 0);
}

- (void)testSearchStarterPacksWithEmptyIndexReturnsEmpty {
    NSError *error = nil;
    NSDictionary *result = [self.service searchStarterPacks:@"starter" limit:10 cursor:nil error:&error];

    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertNotNil(result[@"starterPacks"]);
    XCTAssertEqual([result[@"starterPacks"] count], 0);
}

#pragma mark - Rebuild Index

- (void)testRebuildIndexPopulatesContentTables {
    [self seedActorWithDID:@"did:plc:alice123" handle:@"alice.bsky.social"
              displayName:@"Alice Smith" description:@"Software developer and cat lover"];

    [self seedPostWithDID:@"did:plc:alice123" rkey:@"test123" text:@"Hello world! This is my first post"];

    NSError *error = nil;
    BOOL ok = [self.service rebuildIndexWithError:&error];
    XCTAssertTrue(ok, @"Rebuild should succeed: %@", error);
    XCTAssertNil(error);

    // Verify search actors works
    NSDictionary *actorsResult = [self.service searchActors:@"Alice" limit:10 cursor:nil error:nil];
    XCTAssertNotNil(actorsResult);
    XCTAssertTrue([actorsResult[@"actors"] count] > 0, @"Should find Alice");

    // Verify search posts works
    NSDictionary *postsResult = [self.service searchPosts:@"Hello" limit:10 cursor:nil error:nil];
    XCTAssertNotNil(postsResult);
    XCTAssertTrue([postsResult[@"posts"] count] > 0, @"Should find the post");
}

#pragma mark - Search Results Shape

- (void)testSearchActorsReturnsSkeletonFormat {
    [self seedActorWithDID:@"did:plc:bob456" handle:@"bob.bsky.social"
              displayName:@"Bob Jones" description:nil];

    [self.service rebuildIndexWithError:nil];

    NSDictionary *result = [self.service searchActors:@"Bob" limit:10 cursor:nil error:nil];
    XCTAssertNotNil(result);
    XCTAssertTrue([result[@"actors"] count] > 0);

    // Verify skeleton format: { did: "..." }
    NSDictionary *actor = result[@"actors"][0];
    XCTAssertNotNil(actor[@"did"], @"Skeleton actor should have 'did' key");
    XCTAssertEqualObjects(actor[@"did"], @"did:plc:bob456");
}

- (void)testSearchPostsReturnsSkeletonFormat {
    [self seedPostWithDID:@"did:plc:carol789" rkey:@"rkey1" text:@"Testing search functionality"];

    [self.service rebuildIndexWithError:nil];

    NSDictionary *result = [self.service searchPosts:@"search" limit:10 cursor:nil error:nil];
    XCTAssertNotNil(result);
    XCTAssertTrue([result[@"posts"] count] > 0);

    NSDictionary *post = result[@"posts"][0];
    XCTAssertNotNil(post[@"uri"], @"Skeleton post should have 'uri' key");
    XCTAssertTrue([post[@"uri"] containsString:@"app.bsky.feed.post"], @"URI should contain collection");
}

#pragma mark - Pagination

- (void)testSearchActorsPaginationWithCursor {
    // Seed multiple actors
    for (int i = 0; i < 5; i++) {
        NSString *did = [NSString stringWithFormat:@"did:plc:paguser%d", i];
        NSString *handle = [NSString stringWithFormat:@"paguser%d.bsky.social", i];
        [self seedActorWithDID:did handle:handle
                  displayName:[NSString stringWithFormat:@"PagUser %d", i] description:nil];
    }

    [self.service rebuildIndexWithError:nil];

    // First page
    NSDictionary *page1 = [self.service searchActors:@"PagUser" limit:2 cursor:nil error:nil];
    XCTAssertNotNil(page1);
    XCTAssertEqual([page1[@"actors"] count], 2);
    XCTAssertNotNil(page1[@"cursor"], @"Should have cursor for next page");

    // Second page
    id cursor = page1[@"cursor"];
    if (![cursor isEqual:[NSNull null]] && cursor != nil) {
        NSDictionary *page2 = [self.service searchActors:@"PagUser" limit:2 cursor:cursor error:nil];
        XCTAssertNotNil(page2);
        XCTAssertTrue([page2[@"actors"] count] > 0, @"Second page should have results");
    }
}

#pragma mark - Query Sanitization

- (void)testSearchWithSpecialCharactersDoesNotCrash {
    [self seedActorWithDID:@"did:plc:special1" handle:@"special.bsky.social"
              displayName:@"Special User" description:nil];

    [self.service rebuildIndexWithError:nil];

    // Search with special characters should not crash
    NSDictionary *result = [self.service searchActors:@"test (special) {chars}" limit:10 cursor:nil error:nil];
    XCTAssertNotNil(result, @"Should handle special characters gracefully");
}

#pragma mark - Populate If Empty

- (void)testPopulateIndexIfEmptyCallsRebuild {
    [self seedActorWithDID:@"did:plc:pop1" handle:@"pop.bsky.social"
              displayName:@"Pop User" description:nil];

    NSError *error = nil;
    BOOL ok = [self.service populateIndexIfEmptyWithError:&error];
    XCTAssertTrue(ok, @"populateIndexIfEmpty should succeed: %@", error);

    // Should now find results
    NSDictionary *result = [self.service searchActors:@"Pop" limit:10 cursor:nil error:nil];
    XCTAssertNotNil(result);
    XCTAssertTrue([result[@"actors"] count] > 0, @"Should find Pop User after populate");
}

- (void)testPopulateIndexSkipsIfAlreadyPopulated {
    [self seedActorWithDID:@"did:plc:skip1" handle:@"skip.bsky.social"
              displayName:@"Skip User" description:nil];

    [self.service populateIndexIfEmptyWithError:nil];

    // Second populate should skip
    NSError *error = nil;
    BOOL ok = [self.service populateIndexIfEmptyWithError:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
}

@end
