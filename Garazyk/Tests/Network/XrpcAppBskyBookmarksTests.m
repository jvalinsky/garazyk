#import "AdminAuthXrpcTestBase.h"

@interface XrpcAppBskyBookmarksTests : AdminAuthXrpcTestBase
@end

@implementation XrpcAppBskyBookmarksTests

#pragma mark - getBookmarks Tests

- (void)testGetBookmarksRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.bookmark.getBookmarks"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetBookmarksSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.bookmark.getBookmarks"
                                             queryString:@""
                                             queryParams:@{}
                                                 headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - createBookmark Tests

- (void)testCreateBookmarkRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.bookmark.createBookmark"
                                                      body:@{@"uri": @"at://did:plc:test/app.bsky.feed.post/abc123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testCreateBookmarkRequiresUri {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.bookmark.createBookmark"
                                                      body:@{}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testCreateBookmarkSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.bookmark.createBookmark"
                                                      body:@{@"uri": @"at://did:plc:test/app.bsky.feed.post/abc123"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

#pragma mark - deleteBookmark Tests

- (void)testDeleteBookmarkRequiresAuth {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.bookmark.deleteBookmark"
                                                      body:@{@"uri": @"at://did:plc:test/app.bsky.feed.post/abc123"}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testDeleteBookmarkRequiresUri {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.bookmark.deleteBookmark"
                                                      body:@{}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testDeleteBookmarkSuccess {
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.bookmark.deleteBookmark"
                                                      body:@{@"uri": @"at://did:plc:test/app.bsky.feed.post/abc123"}
                                                   headers:@{@"authorization": authHeader}];
    XCTAssertEqual(response.statusCode, 200);
}

@end
