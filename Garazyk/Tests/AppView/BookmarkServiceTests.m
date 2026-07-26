// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Services/BookmarkService.h"
#import "Database/PDSDatabase.h"

@interface BookmarkServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) BookmarkService *service;
@end

@implementation BookmarkServiceTests

- (void)setUp {
    [super setUp];
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"bookmark_test.db"];
    [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];

    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Database setup failed: %@", error);
    [self setupSchema];
    self.service = [[BookmarkService alloc] initWithDatabase:self.database];
}

- (void)setupSchema {
    NSError *error = nil;
    NSString *sql = @"CREATE TABLE IF NOT EXISTS bookmarks ("
        @"id INTEGER PRIMARY KEY AUTOINCREMENT, "
        @"did TEXT NOT NULL, uri TEXT, "
        @"subject_uri TEXT, subject_cid TEXT, "
        @"created_at TEXT)";
    XCTAssertTrue([self.database executeParameterizedUpdate:sql params:@[] error:&error], @"Table create: %@", error);

    // Also create the repo/record table that indexBookmark looks at
    NSString *recordsSql = @"CREATE TABLE IF NOT EXISTS records ("
        @"did TEXT, collection TEXT, rkey TEXT, "
        @"uri TEXT PRIMARY KEY, cid TEXT, "
        @"value TEXT, indexed_at TEXT)";
    [self.database executeParameterizedUpdate:recordsSql params:@[] error:nil];
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

#pragma mark - indexBookmark

- (void)testIndexBookmark_Valid_ReturnsSuccess {
    NSDictionary *record = @{
        @"subject": @{@"uri": @"at://did:plc:author/app.bsky.feed.post/rkey123", @"cid": @"bafyabc"},
        @"createdAt": @"2026-01-15T00:00:00Z"
    };

    NSError *error = nil;
    BOOL result = [self.service indexBookmark:record
                                          did:@"did:plc:user"
                                          uri:@"at://did:plc:user/app.bsky.bookmark/rkey"
                                          cid:@"bafydef"
                                        error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testIndexBookmark_NilDid_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service indexBookmark:@{@"subject": @{@"uri": @"test"}}
                                          did:(NSString *)nil
                                          uri:@"at://uri"
                                          cid:nil
                                        error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testIndexBookmark_EmptyDid_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service indexBookmark:@{}
                                          did:@""
                                          uri:@"at://uri"
                                          cid:nil
                                        error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testIndexBookmark_NilUri_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service indexBookmark:@{}
                                          did:@"did:plc:user"
                                          uri:(NSString *)nil
                                          cid:nil
                                        error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

#pragma mark - indexBookmarkWithDid

- (void)testIndexBookmarkWithDid_Valid_ReturnsSuccess {
    NSError *error = nil;
    BOOL result = [self.service indexBookmarkWithDid:@"did:plc:user"
                                         subjectURI:@"at://did:plc:author/app.bsky.feed.post/rkey"
                                         subjectCID:@"bafyabc"
                                          createdAt:@"2026-01-15T00:00:00Z"
                                              error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testIndexBookmarkWithDid_NilDid_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service indexBookmarkWithDid:(NSString *)nil
                                         subjectURI:@"at://test"
                                         subjectCID:nil
                                          createdAt:@""
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testIndexBookmarkWithDid_EmptySubjectURI_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service indexBookmarkWithDid:@"did:plc:user"
                                         subjectURI:@""
                                         subjectCID:nil
                                          createdAt:@""
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

#pragma mark - getBookmarksForActor

- (void)testGetBookmarksForActor_NoBookmarks_ReturnsEmpty {
    NSError *error = nil;
    NSDictionary *result = [self.service getBookmarksForActor:@"did:plc:reader"
                                                        limit:10
                                                       cursor:nil
                                                        error:&error];
    XCTAssertNotNil(result);
    XCTAssertNotNil(result[@"bookmarks"]);
    XCTAssertEqual([result[@"bookmarks"] count], 0U);
    XCTAssertNil(error);
}

- (void)testGetBookmarksForActor_NilDid_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *result = [self.service getBookmarksForActor:(NSString *)nil
                                                        limit:10
                                                       cursor:nil
                                                        error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testGetBookmarksForActor_EmptyDid_ReturnsNilError {
    NSError *error = nil;
    NSDictionary *result = [self.service getBookmarksForActor:@""
                                                        limit:10
                                                       cursor:nil
                                                        error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

#pragma mark - unindexBookmarkWithURI

- (void)testUnindexBookmarkWithURI_NilDid_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service unindexBookmarkWithURI:@"at://uri" did:(NSString *)nil error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testUnindexBookmarkWithURI_NilURI_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service unindexBookmarkWithURI:(NSString *)nil did:@"did:plc:user" error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

#pragma mark - unindexBookmarkWithSubjectURI

- (void)testUnindexBookmarkWithSubjectURI_NilSubjectURI_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service unindexBookmarkWithSubjectURI:(NSString *)nil did:@"did:plc:user" error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testUnindexBookmarkWithSubjectURI_NilDid_ReturnsNOError {
    NSError *error = nil;
    BOOL result = [self.service unindexBookmarkWithSubjectURI:@"at://subject" did:(NSString *)nil error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

@end
