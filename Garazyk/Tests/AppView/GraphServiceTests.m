// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Services/GraphService.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"

@interface GraphServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) GraphService *service;
@end

@implementation GraphServiceTests

- (void)setUp {
    [super setUp];
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"graph_test.db"];
    [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];

    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Database setup failed: %@", error);
    [self setupSchema];
    self.service = [[GraphService alloc] initWithDatabase:self.database];
}

- (void)setupSchema {
    NSError *error = nil;
    // Drop tables first in case PDSDatabase migrations created them with different schemas
    [self.database executeParameterizedUpdate:@"DROP TABLE IF EXISTS starter_packs" params:@[] error:nil];
    [self.database executeParameterizedUpdate:@"DROP TABLE IF EXISTS bsky_graph_lists" params:@[] error:nil];
    [self.database executeParameterizedUpdate:@"DROP TABLE IF EXISTS bsky_graph_listitems" params:@[] error:nil];
    [self.database executeParameterizedUpdate:@"DROP TABLE IF EXISTS actor_mutes" params:@[] error:nil];
    [self.database executeParameterizedUpdate:@"DROP TABLE IF EXISTS records" params:@[] error:nil];
    [self.database executeParameterizedUpdate:@"DROP TABLE IF EXISTS blocks" params:@[] error:nil];

    // Starter packs table — matches the INSERT in indexStarterPack:
    // "INSERT OR REPLACE INTO starter_packs (uri, did, rkey, cid, name, created_at)"
    NSString *spSql = @"CREATE TABLE starter_packs ("
        @"uri TEXT PRIMARY KEY, did TEXT, rkey TEXT, cid TEXT, "
        @"name TEXT, created_at TEXT)";
    XCTAssertTrue([self.database executeParameterizedUpdate:spSql params:@[] error:&error], @"Starter packs: %@", error);

    // Lists table
    NSString *listsSql = @"CREATE TABLE bsky_graph_lists ("
        @"uri TEXT PRIMARY KEY, did TEXT, name TEXT, purpose TEXT, "
        @"description TEXT, avatar_cid TEXT, created_at REAL)";
    [self.database executeParameterizedUpdate:listsSql params:@[] error:nil];

    // List items table
    NSString *itemsSql = @"CREATE TABLE bsky_graph_listitems ("
        @"uri TEXT PRIMARY KEY, list_uri TEXT, subject_did TEXT, created_at REAL)";
    [self.database executeParameterizedUpdate:itemsSql params:@[] error:nil];

    // Actor mutes table
    NSString *mutesSql = @"CREATE TABLE actor_mutes ("
        @"id INTEGER PRIMARY KEY AUTOINCREMENT, "
        @"did TEXT, muted_did TEXT, created_at TEXT, "
        @"UNIQUE(did, muted_did))";
    [self.database executeParameterizedUpdate:mutesSql params:@[] error:nil];

    // Records table (needed for getFollowsForActor:)
    NSString *recordsSql = @"CREATE TABLE records ("
        @"uri TEXT PRIMARY KEY, did TEXT, collection TEXT, rkey TEXT, cid TEXT)";
    [self.database executeParameterizedUpdate:recordsSql params:@[] error:nil];

    // Blocks table (needed for getRecordBodiesForPairs:)
    NSString *blocksSql = @"CREATE TABLE blocks ("
        @"cid BLOB PRIMARY KEY, repo_did TEXT, block_data BLOB, created_at TEXT)";
    [self.database executeParameterizedUpdate:blocksSql params:@[] error:nil];
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

#pragma mark - Init

- (void)testService_Init {
    XCTAssertNotNil(self.service);
}

#pragma mark - indexStarterPack

- (void)testIndexStarterPack_Valid_ReturnsSuccess {
    NSError *error = nil;
    BOOL result = [self.service indexStarterPack:@{@"name": @"Test Pack", @"createdAt": @"2026-01-01T00:00:00Z"}
                                            did:@"did:plc:creator"
                                           rkey:@"self-start"
                                            cid:@"bafyabc"
                                          error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testIndexStarterPack_NilDid_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service indexStarterPack:@{}
                                            did:(NSString *)nil
                                           rkey:@"rkey"
                                            cid:@"cid"
                                          error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testIndexStarterPack_EmptyDid_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service indexStarterPack:@{}
                                            did:@""
                                           rkey:@"rkey"
                                            cid:@"cid"
                                          error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testIndexStarterPack_NilRkey_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service indexStarterPack:@{}
                                            did:@"did:plc:test"
                                           rkey:(NSString *)nil
                                            cid:@"cid"
                                          error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

#pragma mark - unindexStarterPackWithRKey

- (void)testUnindexStarterPackWithRKey_NilDid_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service unindexStarterPackWithRKey:@"rkey" did:(NSString *)nil error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testUnindexStarterPackWithRKey_NilRkey_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service unindexStarterPackWithRKey:(NSString *)nil did:@"did:plc:test" error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

#pragma mark - indexList

- (void)testIndexList_Valid_ReturnsSuccess {
    NSError *error = nil;
    BOOL result = [self.service indexList:@{@"name": @"My List", @"purpose": @"app.bsky.graph.defs#modlist"}
                                     did:@"did:plc:list-creator"
                                     uri:@"at://did:plc:list-creator/app.bsky.graph.list/rkey1"
                                     cid:@"bafyabc"
                                   error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testIndexList_NilDid_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service indexList:@{}
                                     did:(NSString *)nil
                                     uri:@"at://uri"
                                     cid:@"cid"
                                   error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testIndexList_EmptyUri_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service indexList:@{}
                                     did:@"did:plc:test"
                                     uri:@""
                                     cid:@"cid"
                                   error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

#pragma mark - unindexListWithURI

- (void)testUnindexListWithURI_NilURI_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service unindexListWithURI:(NSString *)nil error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testUnindexListWithURI_EmptyURI_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service unindexListWithURI:@"" error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

#pragma mark - indexListitem

- (void)testIndexListitem_Valid_ReturnsSuccess {
    NSError *error = nil;
    BOOL result = [self.service indexListitem:@{@"list": @"at://list-uri", @"subject": @"did:plc:member"}
                                         did:@"did:plc:adder"
                                         uri:@"at://did:plc:adder/app.bsky.graph.listitem/rkey1"
                                         cid:@"bafyabc"
                                       error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testIndexListitem_NilDid_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service indexListitem:@{}
                                         did:(NSString *)nil
                                         uri:@"at://uri"
                                         cid:@"cid"
                                       error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testIndexListitem_EmptyUri_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service indexListitem:@{}
                                         did:@"did:plc:test"
                                         uri:@""
                                         cid:@"cid"
                                       error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

#pragma mark - unindexListitemWithURI

- (void)testUnindexListitemWithURI_NilURI_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service unindexListitemWithURI:(NSString *)nil error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testUnindexListitemWithURI_EmptyURI_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service unindexListitemWithURI:@"" error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

#pragma mark - Mute/Unmute

- (void)testMuteActor_Valid_ReturnsSuccess {
    NSError *error = nil;
    BOOL result = [self.service muteActor:@"did:plc:target" forActor:@"did:plc:muter" error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testUnmuteActor_Valid_ReturnsSuccess {
    // First mute, then unmute
    [self.service muteActor:@"did:plc:target" forActor:@"did:plc:muter" error:nil];

    NSError *error = nil;
    BOOL result = [self.service unmuteActor:@"did:plc:target" forActor:@"did:plc:muter" error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testMuteActor_Duplicate_ReturnsSuccess {
    [self.service muteActor:@"did:plc:target" forActor:@"did:plc:muter" error:nil];
    NSError *error = nil;
    BOOL result = [self.service muteActor:@"did:plc:target" forActor:@"did:plc:muter" error:&error];
    // INSERT OR IGNORE should succeed even for duplicates
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

#pragma mark - getFollowsForActor

- (void)testGetFollowsForActor_ObjectValuedSubject_FiltersOut {
    // F1 fix: record[@"subject"] as an object (not string) is safely rejected.
    // This test inserts a follow record whose block data has
    // subject = {uri: "..."} rather than subject = "did:plc:target".

    NSDictionary *recordContent = @{@"subject": @{@"uri": @"at://did:plc:ignored/app.bsky.feed.post/abc"}};
    NSError *cborError = nil;
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:recordContent error:&cborError];
    XCTAssertNotNil(cborData, @"CBOR encode failed: %@", cborError);

    NSString *cidString = @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu";
    CID *testCid = [CID cidFromString:cidString];
    XCTAssertNotNil(testCid, @"CID parse failed");

    // Insert block with object-valued subject
    [self.database executeParameterizedUpdate:
        @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, created_at) VALUES (?, ?, ?, ?)"
        params:@[testCid.bytes, @"did:plc:test-user", cborData, @"2026-01-01T00:00:00Z"] error:nil];

    // Insert follow record pointing to that CID
    [self.database executeParameterizedUpdate:
        @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid) VALUES (?, ?, ?, ?, ?)"
        params:@[@"at://did:plc:test-user/app.bsky.graph.follow/abc",
                  @"did:plc:test-user", @"app.bsky.graph.follow", @"abc", cidString] error:nil];

    NSError *error = nil;
    NSDictionary *result = [self.service getFollowsForActor:@"did:plc:test-user" limit:10 cursor:nil error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);

    NSArray *follows = result[@"follows"];
    XCTAssertNotNil(follows);
    XCTAssertEqual(follows.count, 0,
                   @"Object-valued subject should be filtered out (isKindOfClass guard), got %lu items",
                   (unsigned long)follows.count);
}

@end
