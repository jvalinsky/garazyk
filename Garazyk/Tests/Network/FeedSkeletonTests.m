#import "RepoAuthXrpcTestBase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"

@interface FeedSkeletonTests : RepoAuthXrpcTestBase
@end

@implementation FeedSkeletonTests

- (void)insertTestPostRecord:(NSString *)did
                          rkey:(NSString *)rkey
                            cid:(NSString *)cidStr {
    NSError *dbError = nil;
    PDSDatabase *db = [[self serviceDatabases] serviceDatabaseWithError:&dbError];
    XCTAssertNotNil(db, @"Failed to open service database: %@", dbError);

    NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", did, rkey];
    NSString *insertSQL = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, value, indexed_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))";
    BOOL ok = [db executeParameterizedUpdate:insertSQL
                                     params:@[uri, did, @"app.bsky.feed.post", rkey, cidStr, @"{}"]
                                       error:&dbError];
    XCTAssertTrue(ok, @"Insert post record failed: %@", dbError);
    [db close];
}

#pragma mark - getFeedSkeleton

- (void)testGetFeedSkeletonMissingFeedParam {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getFeedSkeleton"
                                               headers:@{}];
    XCTAssertEqual(response.statusCode, 400,
        @"Missing feed param should return 400, got %ld: %@",
        (long)response.statusCode, response.jsonBody);
    XCTAssertTrue(
        [response.jsonBody[@"message"] rangeOfString:@"feed" options:NSCaseInsensitiveSearch].location != NSNotFound,
        @"Expected message about feed parameter, got '%@'", response.jsonBody[@"message"]);
}

- (void)testGetFeedSkeletonInvalidCollection {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getFeedSkeleton"
                                         queryParams:@{
                                             @"feed": @"at://did:plc:example/app.bsky.feed.post/somepost"
                                         }
                                              headers:@{}];
    XCTAssertEqual(response.statusCode, 400,
        @"Non-generator collection should return 400, got %ld: %@",
        (long)response.statusCode, response.jsonBody);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"UnknownFeed",
        @"Expected UnknownFeed error");
}

- (void)testGetFeedSkeletonEmptySkeleton {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getFeedSkeleton"
                                         queryParams:@{
                                             @"feed": @"at://did:plc:nonexistent/app.bsky.feed.generator/unknownrkey",
                                             @"limit": @"10"
                                         }
                                              headers:@{}];
    XCTAssertEqual(response.statusCode, 200,
        @"Unknown generator should return 200 with empty feed, got %ld: %@",
        (long)response.statusCode, response.jsonBody);
    XCTAssertTrue([response.jsonBody[@"feed"] isKindOfClass:[NSArray class]],
        @"feed should be an array");
    XCTAssertEqual([response.jsonBody[@"feed"] count], 0,
        @"feed should be empty for unknown generator");
}

- (void)testGetFeedSkeletonReturnsSkeletonItems {
    XCTAssertNotNil(self.did1, @"did1 should be set from account creation");

    [self insertTestPostRecord:self.did1 rkey:@"post001" cid:@"bafyreifake1"];
    [self insertTestPostRecord:self.did1 rkey:@"post002" cid:@"bafyreifake2"];

    NSString *feedURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.generator/myfeed", self.did1];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getFeedSkeleton"
                                         queryParams:@{
                                             @"feed": feedURI,
                                             @"limit": @"10"
                                         }
                                              headers:@{}];
    XCTAssertEqual(response.statusCode, 200,
        @"Expected 200, got %ld: %@", (long)response.statusCode, response.jsonBody);
    XCTAssertTrue([response.jsonBody[@"feed"] isKindOfClass:[NSArray class]],
        @"feed should be an array");

    NSArray *feed = response.jsonBody[@"feed"];
    XCTAssertGreaterThanOrEqual(feed.count, 1,
        @"Feed should have at least 1 item, got %@", feed);

    for (id item in feed) {
        XCTAssertTrue([item isKindOfClass:[NSDictionary class]],
            @"Each feed item should be a dict");
        XCTAssertTrue([item[@"post"] isKindOfClass:[NSString class]],
            @"Each feed item should have a post URI string");
    }
}

@end
