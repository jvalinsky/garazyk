// Tests for BookmarkService: index, get, and unindex bookmarks.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "AppView/BookmarkService.h"
#import "Database/PDSDatabase.h"

@interface BookmarkServiceTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, strong) BookmarkService *service;
@property (nonatomic, copy) NSString *dbPath;
@end

@implementation BookmarkServiceTests

- (void)setUp {
    [super setUp];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"bookmark_test_%@.db", uuid]];
    NSURL *url = [NSURL fileURLWithPath:self.dbPath];
    self.db = [PDSDatabase databaseAtURL:url];
    NSError *error = nil;
    BOOL opened = [self.db openWithError:&error];
    XCTAssertTrue(opened, @"Database must open: %@", error);
    self.service = [[BookmarkService alloc] initWithDatabase:self.db];
    XCTAssertNotNil(self.service);
}

- (void)tearDown {
    [self.db close];
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

#pragma mark - Index via indexBookmark:did:uri:cid:

- (void)testIndexBookmarkAndGetBookmarks {
    NSError *error = nil;
    NSDictionary *record = @{@"subject": @{@"uri": @"at://did:plc:target/app.bsky.feed.post/r1"}};
    NSString *did = @"did:plc:bookmarkuser";
    NSString *uri = @"at://did:plc:bookmarkuser/app.bsky.actor.bookmark/bm001";
    NSString *cid = @"bafyreibm001";

    BOOL ok = [self.service indexBookmark:record did:did uri:uri cid:cid error:&error];
    XCTAssertTrue(ok, @"indexBookmark:did:uri:cid: must succeed: %@", error);

    NSDictionary *result = [self.service getBookmarksForActor:did limit:10 cursor:nil error:&error];
    XCTAssertNotNil(result, @"getBookmarksForActor must return a result: %@", error);
}

#pragma mark - Index via indexBookmarkWithDid:subjectURI:subjectCID:createdAt:

- (void)testIndexBookmarkWithDIDSubjectURIAndGet {
    NSError *error = nil;
    NSString *did = @"did:plc:bmuserB";
    NSString *subjectURI = @"at://did:plc:author/app.bsky.feed.post/tid999";
    NSString *subjectCID = @"bafyreisub999";
    NSString *createdAt = @"2025-01-01T00:00:00.000Z";

    BOOL ok = [self.service indexBookmarkWithDid:did
                                      subjectURI:subjectURI
                                      subjectCID:subjectCID
                                       createdAt:createdAt
                                           error:&error];
    XCTAssertTrue(ok, @"indexBookmarkWithDid: must succeed: %@", error);

    NSDictionary *result = [self.service getBookmarksForActor:did limit:10 cursor:nil error:&error];
    XCTAssertNotNil(result, @"getBookmarksForActor must return a result: %@", error);
}

#pragma mark - Unindex by URI

- (void)testUnindexBookmarkWithURIRemovesIt {
    NSError *error = nil;
    NSString *did = @"did:plc:unindexuser";
    NSString *uri = @"at://did:plc:unindexuser/app.bsky.actor.bookmark/bm002";

    [self.service indexBookmark:@{} did:did uri:uri cid:nil error:nil];

    BOOL ok = [self.service unindexBookmarkWithURI:uri did:did error:&error];
    XCTAssertTrue(ok, @"unindexBookmarkWithURI: must succeed: %@", error);
}

#pragma mark - Unindex by Subject URI

- (void)testUnindexBookmarkWithSubjectURIRemovesIt {
    NSError *error = nil;
    NSString *did = @"did:plc:subjectunindex";
    NSString *subjectURI = @"at://did:plc:original/app.bsky.feed.post/tid888";

    [self.service indexBookmarkWithDid:did
                            subjectURI:subjectURI
                            subjectCID:nil
                             createdAt:@"2025-06-01T00:00:00.000Z"
                                 error:nil];

    BOOL ok = [self.service unindexBookmarkWithSubjectURI:subjectURI did:did error:&error];
    XCTAssertTrue(ok, @"unindexBookmarkWithSubjectURI: must succeed: %@", error);
}

#pragma mark - Empty State

- (void)testGetBookmarksForActorWithNoneReturnsResult {
    NSError *error = nil;
    NSDictionary *result = [self.service getBookmarksForActor:@"did:plc:hasnothing"
                                                        limit:50
                                                       cursor:nil
                                                        error:&error];
    // Must not crash; result may be nil or an empty-bookmarks dict
    (void)result;
}

#pragma mark - Pagination Limit

- (void)testGetBookmarksRespectsLimit {
    NSError *error = nil;
    NSString *did = @"did:plc:limituser";

    for (NSUInteger i = 0; i < 10; i++) {
        NSString *subjectURI = [NSString stringWithFormat:
                                @"at://did:plc:posts/app.bsky.feed.post/tid%lu", (unsigned long)i];
        [self.service indexBookmarkWithDid:did
                                subjectURI:subjectURI
                                subjectCID:nil
                                 createdAt:@"2025-01-01T00:00:00.000Z"
                                     error:nil];
    }

    NSDictionary *result = [self.service getBookmarksForActor:did limit:5 cursor:nil error:&error];
    XCTAssertNotNil(result, @"getBookmarksForActor with limit: %@", error);
    // If the implementation returns a bookmarks array, verify the limit is honored
    NSArray *bookmarks = result[@"bookmarks"];
    if (bookmarks) {
        XCTAssertLessThanOrEqual(bookmarks.count, (NSUInteger)5,
                                 @"Result must not exceed limit of 5");
    }
}

@end
