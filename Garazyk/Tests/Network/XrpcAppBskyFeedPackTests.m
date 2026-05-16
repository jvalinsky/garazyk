// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminAuthXrpcTestBase.h"
#import "AppView/Services/GraphService.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabaseBlock.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Network/XrpcAppBskyFeedPack.h"

#ifndef XCTAssertIsInstance
#define XCTAssertIsInstance(obj, cls) XCTAssertTrue([(obj) isKindOfClass:(cls)])
#endif

@interface XrpcAppBskyFeedPackTests : AdminAuthXrpcTestBase
@end

@implementation XrpcAppBskyFeedPackTests

- (NSDictionary *)createdRecordForDid:(NSString *)did
                            collection:(NSString *)collection
                                record:(NSDictionary *)record {
    NSError *error = nil;
    NSDictionary *created = [self.application.legacyController createRecordForDid:did
                                                                       collection:collection
                                                                           record:record
                                                                   validationMode:PDSValidationModeOff
                                                                            error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(created);
    return created;
}

- (NSDictionary *)createPostForDid:(NSString *)did text:(NSString *)text {
    NSDictionary *record = @{
        @"$type" : @"app.bsky.feed.post",
        @"text" : text,
        @"createdAt" : [self iso8601String]
    };
    NSDictionary *created = [self createdRecordForDid:did
                                           collection:@"app.bsky.feed.post"
                                               record:record];
    [self seedRecordInServiceDB:created record:record forDid:did collection:@"app.bsky.feed.post"];
    return created;
}

- (NSDictionary *)createReplyForDid:(NSString *)did parentURI:(NSString *)parentURI text:(NSString *)text {
    NSDictionary *record = @{
        @"$type" : @"app.bsky.feed.post",
        @"text" : text,
        @"reply" : @{
            @"parent" : @{@"uri" : parentURI},
            @"root" : @{@"uri" : parentURI}
        },
        @"createdAt" : [self iso8601String]
    };
    NSDictionary *created = [self createdRecordForDid:did
                                           collection:@"app.bsky.feed.post"
                                               record:record];
    [self seedRecordInServiceDB:created record:record forDid:did collection:@"app.bsky.feed.post"];
    return created;
}

- (NSDictionary *)createLikeForDid:(NSString *)did subjectURI:(NSString *)subjectURI {
    NSDictionary *record = @{
        @"$type" : @"app.bsky.feed.like",
        @"subject" : @{@"uri" : subjectURI},
        @"createdAt" : [self iso8601String]
    };
    NSDictionary *created = [self createdRecordForDid:did
                                           collection:@"app.bsky.feed.like"
                                               record:record];
    [self seedRecordInServiceDB:created record:record forDid:did collection:@"app.bsky.feed.like"];
    return created;
}

- (NSDictionary *)createRepostForDid:(NSString *)did subjectURI:(NSString *)subjectURI {
    NSDictionary *record = @{
        @"$type" : @"app.bsky.feed.repost",
        @"subject" : @{@"uri" : subjectURI},
        @"createdAt" : [self iso8601String]
    };
    NSDictionary *created = [self createdRecordForDid:did
                                           collection:@"app.bsky.feed.repost"
                                               record:record];
    [self seedRecordInServiceDB:created record:record forDid:did collection:@"app.bsky.feed.repost"];
    return created;
}

- (NSDictionary *)createQuoteForDid:(NSString *)did subjectURI:(NSString *)subjectURI text:(NSString *)text {
    NSDictionary *record = @{
        @"$type" : @"app.bsky.feed.post",
        @"text" : text,
        @"embed" : @{
            @"$type" : @"app.bsky.embed.record",
            @"record" : @{@"uri" : subjectURI}
        },
        @"createdAt" : [self iso8601String]
    };
    NSDictionary *created = [self createdRecordForDid:did
                                           collection:@"app.bsky.feed.post"
                                               record:record];
    [self seedRecordInServiceDB:created record:record forDid:did collection:@"app.bsky.feed.post"];
    return created;
}

- (NSDictionary *)createFeedGeneratorForDid:(NSString *)did
                                  displayName:(NSString *)displayName
                                   items:(NSArray *)items {
    NSDictionary *record = @{
        @"$type" : @"app.bsky.feed.generator",
        @"displayName" : displayName,
        @"description" : [NSString stringWithFormat:@"%@ description", displayName],
        @"items" : items,
        @"createdAt" : [self iso8601String]
    };
    NSDictionary *created = [self createdRecordForDid:did
                                           collection:@"app.bsky.feed.generator"
                                               record:record];
    [self seedRecordInServiceDB:created record:record forDid:did collection:@"app.bsky.feed.generator"];
    return created;
}

- (void)seedListItemForListURI:(NSString *)listURI subjectDid:(NSString *)subjectDid {
    NSError *dbError = nil;
    PDSDatabase *database = [self.application.serviceDatabases serviceDatabaseWithError:&dbError];
    XCTAssertNil(dbError);
    XCTAssertNotNil(database);

    // Ensure the bsky_graph_listitems and bsky_graph_lists tables exist
    // (these are AppView tables not created by the default PDSDatabase schema)
    [database executeParameterizedUpdate:@"CREATE TABLE IF NOT EXISTS bsky_graph_lists (uri TEXT PRIMARY KEY, creator_did TEXT, name TEXT, description TEXT, purpose TEXT, cursor INTEGER DEFAULT 0, indexed_at REAL)" params:@[] error:nil];
    [database executeParameterizedUpdate:@"CREATE TABLE IF NOT EXISTS bsky_graph_listitems (uri TEXT PRIMARY KEY, list_uri TEXT NOT NULL, subject_did TEXT NOT NULL, created_at INTEGER)" params:@[] error:nil];

    // Insert the list itself so the FK constraint is satisfied
    [database executeParameterizedUpdate:@"INSERT OR REPLACE INTO bsky_graph_lists (uri, creator_did, name, purpose) VALUES (?, ?, ?, ?)"
                                  params:@[listURI, subjectDid, @"test-list", @"app.bsky.graph.defs#curatelist"]
                                   error:nil];

    GraphService *graphService = [[GraphService alloc] initWithDatabase:database];
    NSError *error = nil;
    NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.graph.listitem/%@", subjectDid, [NSUUID UUID].UUIDString];
    BOOL success = [graphService indexListitem:@{@"list" : listURI, @"subject" : subjectDid}
                                          did:subjectDid
                                          uri:uri
                                          cid:@"bafkreigh2akiscaildc"
                                        error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
}

- (void)seedRecordInServiceDB:(NSDictionary *)createdRecord
                        record:(NSDictionary *)record
                     forDid:(NSString *)did
                   collection:(NSString *)collection {
    NSError *dbError = nil;
    PDSDatabase *database = [self.application.serviceDatabases serviceDatabaseWithError:&dbError];
    XCTAssertNil(dbError);
    XCTAssertNotNil(database);

    NSString *uri = createdRecord[@"uri"];
    NSString *cidStr = createdRecord[@"cid"];
    XCTAssertNotNil(uri);
    XCTAssertNotNil(cidStr);

    // Parse URI to extract rkey: at://did/collection/rkey
    NSArray *components = [uri componentsSeparatedByString:@"/"];
    NSString *rkey = components.count >= 5 ? components[4] : @"";

    // CBOR-encode the record for the blocks table
    NSError *cborError = nil;
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&cborError];
    XCTAssertNil(cborError);
    XCTAssertNotNil(cborData);

    // Compute CID from CBOR data (same as PDSController does)
    NSData *digest = [CID sha256Digest:cborData];
    CID *cid = [CID cidWithDigest:digest codec:0x71]; // dag-cbor codec

    // Insert into records table
    NSString *valueJSON = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:record options:0 error:nil] encoding:NSUTF8StringEncoding];
    NSString *insertSQL = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, value) VALUES (?, ?, ?, ?, ?, ?)";
    BOOL insertOK = [database executeParameterizedUpdate:insertSQL
                                                  params:@[uri, did, collection, rkey, cid.stringValue ?: cidStr, valueJSON ?: @""]
                                                   error:&dbError];
    XCTAssertTrue(insertOK);
    XCTAssertNil(dbError);

    // Insert into blocks table for getRecordBodyFromCID: lookups
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = cid.bytes;
    block.repoDid = did;
    block.blockData = cborData;
    block.contentType = @"application/cbor";
    block.size = (NSInteger)cborData.length;
    block.createdAt = [NSDate date];

    BOOL blockOK = [database saveBlock:block error:&dbError];
    XCTAssertTrue(blockOK);
    XCTAssertNil(dbError);
}

- (void)testGetAuthorFeedRequiresActor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getAuthorFeed"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetAuthorFeedReturnsAuthorPosts {
    NSDictionary *created = [self createPostForDid:self.userDid text:@"author feed post"];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getAuthorFeed"
                                             queryString:[NSString stringWithFormat:@"actor=%@&limit=10", self.userDid]
                                              queryParams:@{@"actor" : self.userDid, @"limit" : @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *feed = response.jsonBody[@"feed"];
    XCTAssertIsInstance(feed, [NSArray class]);
    XCTAssertEqual(feed.count, 1U);

    NSDictionary *postView = feed.firstObject;
    XCTAssertEqualObjects(postView[@"uri"], created[@"uri"]);
    XCTAssertEqualObjects(postView[@"record"][@"text"], @"author feed post");
    XCTAssertIsInstance(postView[@"author"], [NSDictionary class]);
}

- (void)testGetTimelineRequiresAuth {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getTimeline"
                                             queryString:@"limit=10"
                                              queryParams:@{@"limit" : @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 401);
}

- (void)testGetTimelineReturnsFeedItems {
    NSDictionary *created = [self createPostForDid:self.userDid text:@"timeline post"];
    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getTimeline"
                                             queryString:@"limit=10"
                                              queryParams:@{@"limit" : @"10"}
                                                  headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *feed = response.jsonBody[@"feed"];
    XCTAssertIsInstance(feed, [NSArray class]);
    XCTAssertTrue(feed.count >= 1U);
    XCTAssertEqualObjects(feed.firstObject[@"uri"], created[@"uri"]);
}

- (void)testGetActorLikesRequiresActor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getActorLikes"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetActorLikesReturnsLikedPosts {
    NSDictionary *target = [self createPostForDid:self.userDid text:@"liked target"];
    NSDictionary *like = [self createLikeForDid:self.userDid subjectURI:target[@"uri"]];
    (void)like;

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getActorLikes"
                                             queryString:[NSString stringWithFormat:@"actor=%@&limit=10", self.userDid]
                                              queryParams:@{@"actor" : self.userDid, @"limit" : @"10"}
                                                  headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *feed = response.jsonBody[@"feed"];
    XCTAssertIsInstance(feed, [NSArray class]);
    XCTAssertEqual(feed.count, 1U);

    NSDictionary *likeView = feed.firstObject[@"like"];
    XCTAssertIsInstance(likeView, [NSDictionary class]);
    XCTAssertEqualObjects(likeView[@"actor"][@"did"], self.userDid);
    XCTAssertEqualObjects(feed.firstObject[@"post"][@"uri"], target[@"uri"]);
}

- (void)testGetPostThreadRequiresUri {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getPostThread"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetPostThreadReturnsReplies {
    NSDictionary *parent = [self createPostForDid:self.userDid text:@"thread parent"];
    NSDictionary *reply = [self createReplyForDid:self.userDid parentURI:parent[@"uri"] text:@"thread reply"];
    (void)reply;

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getPostThread"
                                             queryString:[NSString stringWithFormat:@"uri=%@&depth=3", parent[@"uri"]]
                                              queryParams:@{@"uri" : parent[@"uri"], @"depth" : @"3"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    NSDictionary *thread = response.jsonBody;
    XCTAssertIsInstance(thread[@"post"], [NSDictionary class]);
    XCTAssertEqualObjects(thread[@"post"][@"uri"], parent[@"uri"]);
    NSArray *replies = thread[@"replies"];
    XCTAssertIsInstance(replies, [NSArray class]);
    XCTAssertEqual(replies.count, 1U);
    NSDictionary *replyThread = replies.firstObject;
    XCTAssertEqualObjects(replyThread[@"post"][@"record"][@"text"], @"thread reply");
}

- (void)testGetFeedRequiresFeed {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getFeed"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetFeedReturnsGeneratorItems {
    NSDictionary *itemPost = [self createPostForDid:self.userDid text:@"generator post"];
    NSDictionary *generator = [self createFeedGeneratorForDid:self.userDid
                                                   displayName:@"Featured feed"
                                                        items:@[@{@"post" : itemPost[@"uri"]}]];
    NSString *feedURI = generator[@"uri"];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getFeed"
                                             queryString:[NSString stringWithFormat:@"feed=%@&limit=10", feedURI]
                                              queryParams:@{@"feed" : feedURI, @"limit" : @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *feed = response.jsonBody[@"feed"];
    XCTAssertIsInstance(feed, [NSArray class]);
    XCTAssertEqual(feed.count, 1U);
    XCTAssertEqualObjects(feed.firstObject[@"post"], itemPost[@"uri"]);
}

- (void)testGetPostsRequiresUris {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getPosts"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetPostsReturnsRequestedPosts {
    NSDictionary *post = [self createPostForDid:self.userDid text:@"multi post"];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getPosts"
                                             queryString:[NSString stringWithFormat:@"uris=%@", post[@"uri"]]
                                              queryParams:@{@"uris" : post[@"uri"]}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *posts = response.jsonBody[@"posts"];
    XCTAssertIsInstance(posts, [NSArray class]);
    XCTAssertEqual(posts.count, 1U);
    XCTAssertEqualObjects(posts.firstObject[@"uri"], post[@"uri"]);
}

- (void)testGetFeedGeneratorsReturnsViews {
    NSDictionary *generator = [self createFeedGeneratorForDid:self.userDid
                                                   displayName:@"Featured feed"
                                                        items:@[]];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getFeedGenerators"
                                             queryString:[NSString stringWithFormat:@"feeds=%@", generator[@"uri"]]
                                              queryParams:@{@"feeds" : generator[@"uri"]}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *feeds = response.jsonBody[@"feeds"];
    XCTAssertIsInstance(feeds, [NSArray class]);
    XCTAssertEqual(feeds.count, 1U);
    XCTAssertEqualObjects(feeds.firstObject[@"uri"], generator[@"uri"]);
}

- (void)testGetSuggestedFeedsReturnsArray {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getSuggestedFeeds"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *feeds = response.jsonBody[@"feeds"];
    XCTAssertIsInstance(feeds, [NSArray class]);
    XCTAssertEqual(feeds.count, 0U);
}

- (void)testGetLikesRequiresUri {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getLikes"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetLikesReturnsLikerActors {
    NSDictionary *target = [self createPostForDid:self.userDid text:@"liked by query"];
    [self createLikeForDid:self.userDid subjectURI:target[@"uri"]];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getLikes"
                                             queryString:[NSString stringWithFormat:@"uri=%@&limit=10", target[@"uri"]]
                                              queryParams:@{@"uri" : target[@"uri"], @"limit" : @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    NSDictionary *body = response.jsonBody;
    XCTAssertEqualObjects(body[@"uri"], target[@"uri"]);
    NSArray *likes = body[@"likes"];
    XCTAssertIsInstance(likes, [NSArray class]);
    XCTAssertEqual(likes.count, 1U);
    XCTAssertEqualObjects(likes.firstObject[@"actor"][@"did"], self.userDid);
}

- (void)testGetRepostedByRequiresUri {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getRepostedBy"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetRepostedByReturnsActors {
    NSDictionary *target = [self createPostForDid:self.userDid text:@"reposted by query"];
    [self createRepostForDid:self.userDid subjectURI:target[@"uri"]];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getRepostedBy"
                                             queryString:[NSString stringWithFormat:@"uri=%@&limit=10", target[@"uri"]]
                                              queryParams:@{@"uri" : target[@"uri"], @"limit" : @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    NSDictionary *body = response.jsonBody;
    XCTAssertEqualObjects(body[@"uri"], target[@"uri"]);
    NSArray *repostedBy = body[@"repostedBy"];
    XCTAssertIsInstance(repostedBy, [NSArray class]);
    XCTAssertEqual(repostedBy.count, 1U);
    XCTAssertEqualObjects(repostedBy.firstObject[@"did"], self.userDid);
}

- (void)testGetActorFeedsRequiresActor {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getActorFeeds"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetActorFeedsReturnsGeneratorViews {
    NSDictionary *generator = [self createFeedGeneratorForDid:self.userDid
                                                   displayName:@"Creator feed"
                                                        items:@[]];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getActorFeeds"
                                             queryString:[NSString stringWithFormat:@"actor=%@&limit=10", self.userDid]
                                              queryParams:@{@"actor" : self.userDid, @"limit" : @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *feeds = response.jsonBody[@"feeds"];
    XCTAssertIsInstance(feeds, [NSArray class]);
    XCTAssertEqual(feeds.count, 1U);
    XCTAssertEqualObjects(feeds.firstObject[@"uri"], generator[@"uri"]);
    XCTAssertEqualObjects(feeds.firstObject[@"displayName"], @"Creator feed");
}

- (void)testGetFeedGeneratorRequiresFeed {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getFeedGenerator"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetFeedGeneratorReturnsView {
    NSDictionary *generator = [self createFeedGeneratorForDid:self.userDid
                                                   displayName:@"Generator view"
                                                        items:@[]];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getFeedGenerator"
                                             queryString:[NSString stringWithFormat:@"feed=%@", generator[@"uri"]]
                                              queryParams:@{@"feed" : generator[@"uri"]}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    NSDictionary *view = response.jsonBody[@"view"];
    XCTAssertIsInstance(view, [NSDictionary class]);
    XCTAssertEqualObjects(view[@"uri"], generator[@"uri"]);
    XCTAssertEqualObjects(view[@"did"], self.userDid);
    XCTAssertEqualObjects(response.jsonBody[@"isOnline"], @YES);
    XCTAssertEqualObjects(response.jsonBody[@"isValid"], @YES);
}

- (void)testSearchPostsRequiresQuery {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.searchPosts"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testSearchPostsReturnsMatchingPosts {
    NSDictionary *post = [self createPostForDid:self.userDid text:@"needle in haystack"];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.searchPosts"
                                             queryString:@"q=needle&limit=10"
                                              queryParams:@{@"q" : @"needle", @"limit" : @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *posts = response.jsonBody[@"posts"];
    XCTAssertIsInstance(posts, [NSArray class]);
    XCTAssertEqual(posts.count, 1U);
    XCTAssertEqualObjects(posts.firstObject[@"uri"], post[@"uri"]);
    XCTAssertEqualObjects(response.jsonBody[@"hitsTotal"], @1);
}

- (void)testGetQuotesRequiresUri {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getQuotes"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetQuotesReturnsQuotedPosts {
    NSDictionary *target = [self createPostForDid:self.userDid text:@"quote target"];
    NSDictionary *quote = [self createQuoteForDid:self.userDid subjectURI:target[@"uri"] text:@"quoting target"];
    (void)quote;

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getQuotes"
                                             queryString:[NSString stringWithFormat:@"uri=%@&limit=10", target[@"uri"]]
                                              queryParams:@{@"uri" : target[@"uri"], @"limit" : @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *posts = response.jsonBody[@"posts"];
    XCTAssertIsInstance(posts, [NSArray class]);
    XCTAssertEqual(posts.count, 1U);
    XCTAssertEqualObjects(posts.firstObject[@"uri"], quote[@"uri"]);
}

- (void)testDescribeFeedGeneratorReturnsMetadata {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.describeFeedGenerator"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    XCTAssertIsInstance(response.jsonBody[@"feeds"], [NSArray class]);
    XCTAssertIsInstance(response.jsonBody[@"links"], [NSDictionary class]);
}

- (void)testGetFeedSkeletonRequiresFeed {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getFeedSkeleton"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetFeedSkeletonReturnsPostUris {
    NSDictionary *post = [self createPostForDid:self.userDid text:@"skeleton feed post"];
    NSString *feedURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.generator/%@", self.userDid, @"skeleton-feed"];

    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getFeedSkeleton"
                                             queryString:[NSString stringWithFormat:@"feed=%@&limit=10", feedURI]
                                              queryParams:@{@"feed" : feedURI, @"limit" : @"10"}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *feed = response.jsonBody[@"feed"];
    XCTAssertIsInstance(feed, [NSArray class]);
    XCTAssertEqual(feed.count, 1U);
    XCTAssertEqualObjects(feed.firstObject[@"post"], post[@"uri"]);
}

- (void)testSendInteractionsReturnsEmptyBody {
    HttpResponse *response = [self sendJsonRequestWithPath:@"/xrpc/app.bsky.feed.sendInteractions"
                                                      body:@{@"interactions" : @[]}
                                                   headers:@{}];
    XCTAssertEqual(response.statusCode, 200);
    XCTAssertEqual([(NSDictionary *)response.jsonBody count], 0U);
}

- (void)testGetListFeedRequiresList {
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getListFeed"
                                             queryString:@""
                                              queryParams:@{}
                                                  headers:@{}];
    XCTAssertEqual(response.statusCode, 400);
}

- (void)testGetListFeedReturnsMemberPosts {
    NSDictionary *post = [self createPostForDid:self.userDid text:@"list member post"];
    NSString *listURI = [NSString stringWithFormat:@"at://%@/app.bsky.graph.list/%@", self.userDid, @"feed-list"];
    [self seedListItemForListURI:listURI subjectDid:self.userDid];

    NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
    HttpResponse *response = [self sendGetRequestWithPath:@"/xrpc/app.bsky.feed.getListFeed"
                                             queryString:[NSString stringWithFormat:@"list=%@&limit=10", listURI]
                                              queryParams:@{@"list" : listURI, @"limit" : @"10"}
                                                  headers:@{@"authorization" : authHeader}];
    XCTAssertEqual(response.statusCode, 200);

    NSArray *feed = response.jsonBody[@"feed"];
    XCTAssertIsInstance(feed, [NSArray class]);
    XCTAssertEqual(feed.count, 1U);
    XCTAssertEqualObjects(feed.firstObject[@"uri"], post[@"uri"]);
}

@end
