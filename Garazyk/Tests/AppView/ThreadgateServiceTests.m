// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Unit tests for FeedService -indexThreadgate:did:uri:cid:error: and
// -unindexThreadgateWithURI:error: (FeedService.m:657–684).
// Schema under test: bsky_feed_threadgates table in AppViewDatabase.m kSchemaV1.
#import <XCTest/XCTest.h>
#import "AppView/Services/FeedService.h"
#import "Database/PDSDatabase.h"

@interface ThreadgateServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) FeedService *service;
@end

@implementation ThreadgateServiceTests

- (void)setUp {
    [super setUp];
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory
                                withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"threadgate_test.db"];
    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Database setup failed: %@", error);

    [self createSchema];
    self.service = [[FeedService alloc] initWithDatabase:self.database];
}

- (void)createSchema {
    [self.database executeParameterizedUpdate:
        @"CREATE TABLE IF NOT EXISTS accounts ("
        @"id INTEGER PRIMARY KEY, did TEXT UNIQUE, handle TEXT UNIQUE, email TEXT, "
        @"password_hash TEXT, created_at REAL, updated_at REAL, invite_enabled INTEGER DEFAULT 0)"
        params:@[] error:nil];
    [self.database executeParameterizedUpdate:
        @"CREATE TABLE IF NOT EXISTS records ("
        @"id INTEGER PRIMARY KEY, uri TEXT UNIQUE, did TEXT, collection TEXT, rkey TEXT, "
        @"cid TEXT, value TEXT, created_at REAL, indexed_at REAL)"
        params:@[] error:nil];
    [self.database executeParameterizedUpdate:
        @"CREATE TABLE IF NOT EXISTS blocks ("
        @"id INTEGER PRIMARY KEY, cid BLOB UNIQUE, repo_did TEXT, block_data BLOB, size INTEGER)"
        params:@[] error:nil];
    [self.database executeParameterizedUpdate:
        @"CREATE TABLE IF NOT EXISTS bsky_feed_threadgates ("
        @"uri TEXT UNIQUE, post_uri TEXT PRIMARY KEY, allow_json TEXT, "
        @"created_at INTEGER, updated_at INTEGER)"
        params:@[] error:nil];
    [self.database executeParameterizedUpdate:
        @"CREATE UNIQUE INDEX IF NOT EXISTS idx_bsky_feed_threadgates_uri "
        @"ON bsky_feed_threadgates(uri)"
        params:@[] error:nil];
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

// MARK: - Helpers

- (NSString *)threadgateURIForDID:(NSString *)did rkey:(NSString *)rkey {
    return [NSString stringWithFormat:@"at://%@/app.bsky.feed.threadgate/%@", did, rkey];
}

- (NSString *)postURIForDID:(NSString *)did rkey:(NSString *)rkey {
    return [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", did, rkey];
}

// MARK: - Basic error cases

- (void)testIndexThreadgateMissingPostURI {
    NSError *error = nil;
    NSDictionary *record = @{};  // missing "post" key
    BOOL ok = [self.service indexThreadgate:record
                                        did:@"did:plc:author"
                                        uri:[self threadgateURIForDID:@"did:plc:author" rkey:@"gate1"]
                                        cid:@"bafycid1"
                                      error:&error];
    XCTAssertFalse(ok, @"indexThreadgate must fail when 'post' key is absent");
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"FeedService");
    XCTAssertEqual(error.code, 400);
}

// MARK: - Successful indexing

- (void)testIndexThreadgatePersistsRecord {
    NSError *error = nil;
    NSString *postUri = [self postURIForDID:@"did:plc:author" rkey:@"post1"];
    NSString *gateUri = [self threadgateURIForDID:@"did:plc:author" rkey:@"gate1"];
    NSDictionary *record = @{@"post": postUri};

    BOOL ok = [self.service indexThreadgate:record
                                        did:@"did:plc:author"
                                        uri:gateUri
                                        cid:@"bafycid1"
                                      error:&error];
    XCTAssertTrue(ok, @"indexThreadgate should succeed: %@", error);
    XCTAssertNil(error);

    NSArray *rows = [self.database executeParameterizedQuery:
        @"SELECT uri, post_uri, allow_json FROM bsky_feed_threadgates WHERE uri = ?"
        params:@[gateUri] error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(rows.count, 1U);
    XCTAssertEqualObjects(rows[0][@"uri"],      gateUri);
    XCTAssertEqualObjects(rows[0][@"post_uri"], postUri);
}

- (void)testIndexThreadgateEmptyAllowListDefaultsToEmptyJSON {
    NSString *postUri = [self postURIForDID:@"did:plc:author" rkey:@"post2"];
    NSString *gateUri = [self threadgateURIForDID:@"did:plc:author" rkey:@"gate2"];
    NSDictionary *record = @{@"post": postUri};  // no "allow" key

    BOOL ok = [self.service indexThreadgate:record
                                        did:@"did:plc:author"
                                        uri:gateUri
                                        cid:@"bafycid2"
                                      error:nil];
    XCTAssertTrue(ok);

    NSArray *rows = [self.database executeParameterizedQuery:
        @"SELECT allow_json FROM bsky_feed_threadgates WHERE uri = ?"
        params:@[gateUri] error:nil];
    XCTAssertEqualObjects(rows.firstObject[@"allow_json"], @"[]",
        @"allow_json must default to '[]' when 'allow' key is absent from record");
}

- (void)testIndexThreadgateWithAllowListSerializesJSON {
    NSArray *allow = @[@{@"$type": @"app.bsky.feed.threadgate#mentionRule"}];
    NSString *postUri = [self postURIForDID:@"did:plc:author" rkey:@"post3"];
    NSString *gateUri = [self threadgateURIForDID:@"did:plc:author" rkey:@"gate3"];
    NSDictionary *record = @{@"post": postUri, @"allow": allow};

    BOOL ok = [self.service indexThreadgate:record
                                        did:@"did:plc:author"
                                        uri:gateUri
                                        cid:@"bafycid3"
                                      error:nil];
    XCTAssertTrue(ok);

    NSArray *rows = [self.database executeParameterizedQuery:
        @"SELECT allow_json FROM bsky_feed_threadgates WHERE uri = ?"
        params:@[gateUri] error:nil];
    NSString *storedJson = rows.firstObject[@"allow_json"];
    XCTAssertNotNil(storedJson);
    NSArray *parsed = [NSJSONSerialization JSONObjectWithData:
        [storedJson dataUsingEncoding:NSUTF8StringEncoding]
        options:0 error:nil];
    XCTAssertNotNil(parsed);
    XCTAssertEqual(parsed.count, 1U);
    XCTAssertEqualObjects(parsed[0][@"$type"], @"app.bsky.feed.threadgate#mentionRule");
}

// MARK: - Upsert

- (void)testIndexThreadgateUpsertUpdatesExistingRecord {
    NSString *postUri = [self postURIForDID:@"did:plc:author" rkey:@"post4"];
    NSString *gateUri = [self threadgateURIForDID:@"did:plc:author" rkey:@"gate4"];

    // First write — no allow list
    BOOL ok1 = [self.service indexThreadgate:@{@"post": postUri}
                                         did:@"did:plc:author"
                                         uri:gateUri
                                         cid:@"cid1"
                                       error:nil];
    XCTAssertTrue(ok1);

    // Second write — with allow list (INSERT OR REPLACE semantics)
    NSArray *allow = @[@{@"$type": @"app.bsky.feed.threadgate#followingRule"}];
    BOOL ok2 = [self.service indexThreadgate:@{@"post": postUri, @"allow": allow}
                                         did:@"did:plc:author"
                                         uri:gateUri
                                         cid:@"cid2"
                                       error:nil];
    XCTAssertTrue(ok2);

    // Exactly one row must exist after two writes on the same uri.
    NSArray *rows = [self.database executeParameterizedQuery:
        @"SELECT COUNT(*) AS c, allow_json FROM bsky_feed_threadgates WHERE uri = ?"
        params:@[gateUri] error:nil];
    XCTAssertEqual([rows.firstObject[@"c"] integerValue], 1,
        @"INSERT OR REPLACE must leave exactly one row");

    // allow_json must reflect the second write.
    NSArray *parsed = [NSJSONSerialization JSONObjectWithData:
        [rows.firstObject[@"allow_json"] dataUsingEncoding:NSUTF8StringEncoding]
        options:0 error:nil];
    XCTAssertEqualObjects(parsed[0][@"$type"], @"app.bsky.feed.threadgate#followingRule");
}

// MARK: - Unindex

- (void)testUnindexThreadgateRemovesRow {
    NSString *postUri = [self postURIForDID:@"did:plc:author" rkey:@"post5"];
    NSString *gateUri = [self threadgateURIForDID:@"did:plc:author" rkey:@"gate5"];
    [self.service indexThreadgate:@{@"post": postUri}
                              did:@"did:plc:author"
                              uri:gateUri
                              cid:@"cid5"
                            error:nil];

    NSError *error = nil;
    BOOL ok = [self.service unindexThreadgateWithURI:gateUri error:&error];
    XCTAssertTrue(ok, @"unindexThreadgateWithURI failed: %@", error);
    XCTAssertNil(error);

    NSArray *rows = [self.database executeParameterizedQuery:
        @"SELECT COUNT(*) AS c FROM bsky_feed_threadgates WHERE uri = ?"
        params:@[gateUri] error:nil];
    XCTAssertEqual([rows.firstObject[@"c"] integerValue], 0,
        @"Row must be absent after unindexThreadgateWithURI:");
}

- (void)testUnindexThreadgateNonExistentURISucceeds {
    // DELETE on a non-existent row must not produce an error — the operation is idempotent.
    NSError *error = nil;
    BOOL ok = [self.service unindexThreadgateWithURI:
        @"at://did:plc:ghost/app.bsky.feed.threadgate/notexist"
                                               error:&error];
    XCTAssertTrue(ok, @"Unindexing non-existent gate should succeed: %@", error);
    XCTAssertNil(error);
}

// MARK: - Gate by non-author (documented gap)

- (void)testIndexThreadgateByNonAuthorIsRejected {
    // KNOWN GAP: FeedService.m:657 does not validate that `did` matches the post_uri author.
    // A gate created by "did:plc:other" for a post authored by "did:plc:author" is currently
    // accepted. This test fails intentionally to keep the gap visible in CI until the author
    // check is added to FeedService.m.
    NSError *error = nil;
    NSString *postUri = [self postURIForDID:@"did:plc:author" rkey:@"post6"];
    NSString *gateUri = [self threadgateURIForDID:@"did:plc:other"  rkey:@"gate6"];
    NSDictionary *record = @{@"post": postUri};

    BOOL ok = [self.service indexThreadgate:record
                                        did:@"did:plc:other"  // different from post author
                                        uri:gateUri
                                        cid:@"cid6"
                                      error:&error];
    
    XCTAssertFalse(ok, @"Author check must be enforced");
    XCTAssertNotNil(error, @"Error must be populated on author mismatch");
    XCTAssertEqual(error.code, 400, @"Must return 400 Bad Request");
}

// MARK: - Allow list rule types

- (void)testIndexThreadgateWithListAllowRule {
    NSArray *allow = @[@{
        @"$type": @"app.bsky.feed.threadgate#listRule",
        @"list": @"at://did:plc:author/app.bsky.graph.list/list1",
    }];
    NSString *postUri = [self postURIForDID:@"did:plc:author" rkey:@"post7"];
    NSString *gateUri = [self threadgateURIForDID:@"did:plc:author" rkey:@"gate7"];
    NSDictionary *record = @{@"post": postUri, @"allow": allow};

    BOOL ok = [self.service indexThreadgate:record
                                        did:@"did:plc:author"
                                        uri:gateUri
                                        cid:@"cid7"
                                      error:nil];
    XCTAssertTrue(ok);

    NSArray *rows = [self.database executeParameterizedQuery:
        @"SELECT allow_json FROM bsky_feed_threadgates WHERE uri = ?"
        params:@[gateUri] error:nil];
    NSArray *parsed = [NSJSONSerialization JSONObjectWithData:
        [rows.firstObject[@"allow_json"] dataUsingEncoding:NSUTF8StringEncoding]
        options:0 error:nil];
    XCTAssertEqualObjects(parsed[0][@"$type"], @"app.bsky.feed.threadgate#listRule");
    XCTAssertEqualObjects(parsed[0][@"list"],
        @"at://did:plc:author/app.bsky.graph.list/list1");
}

- (void)testIndexThreadgateWithFollowerAllowRule {
    NSArray *allow = @[@{@"$type": @"app.bsky.feed.threadgate#followingRule"}];
    NSString *postUri = [self postURIForDID:@"did:plc:author" rkey:@"post8"];
    NSString *gateUri = [self threadgateURIForDID:@"did:plc:author" rkey:@"gate8"];
    NSDictionary *record = @{@"post": postUri, @"allow": allow};

    BOOL ok = [self.service indexThreadgate:record
                                        did:@"did:plc:author"
                                        uri:gateUri
                                        cid:@"cid8"
                                      error:nil];
    XCTAssertTrue(ok);

    NSArray *rows = [self.database executeParameterizedQuery:
        @"SELECT allow_json FROM bsky_feed_threadgates WHERE uri = ?"
        params:@[gateUri] error:nil];
    NSArray *parsed = [NSJSONSerialization JSONObjectWithData:
        [rows.firstObject[@"allow_json"] dataUsingEncoding:NSUTF8StringEncoding]
        options:0 error:nil];
    XCTAssertEqualObjects(parsed[0][@"$type"], @"app.bsky.feed.threadgate#followingRule");
}

// MARK: - Full lifecycle

- (void)testDeleteThreadgateViaUnindex {
    NSError *error = nil;
    NSString *postUri = [self postURIForDID:@"did:plc:author" rkey:@"post9"];
    NSString *gateUri = [self threadgateURIForDID:@"did:plc:author" rkey:@"gate9"];

    XCTAssertTrue([self.service indexThreadgate:@{@"post": postUri}
                                            did:@"did:plc:author"
                                            uri:gateUri
                                            cid:@"cid9"
                                          error:&error],
        @"index failed: %@", error);

    XCTAssertTrue([self.service unindexThreadgateWithURI:gateUri error:&error],
        @"unindex failed: %@", error);
    XCTAssertNil(error);

    NSArray *rows = [self.database executeParameterizedQuery:
        @"SELECT COUNT(*) AS c FROM bsky_feed_threadgates WHERE uri = ?"
        params:@[gateUri] error:nil];
    XCTAssertEqual([rows.firstObject[@"c"] integerValue], 0,
        @"Row must be absent after full index→unindex lifecycle");
}

@end
