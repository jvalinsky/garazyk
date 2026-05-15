// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Constellation/ConstellationConfiguration.h"
#import "Constellation/ConstellationDatabase.h"
#import "Constellation/ConstellationLinkExtractor.h"
#import "Constellation/ConstellationRuntime.h"
#import "Constellation/ConstellationSourceSpec.h"
#import "Constellation/ConstellationXrpcRoutePack.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

static NSString *ConstellationTestDBPath(NSString *name) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"garazyk-constellation-%@-%@", name, NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return [dir stringByAppendingPathComponent:@"test.db"];
}

static ConstellationDatabase *ConstellationOpenTestDB(XCTestCase *testCase) {
    NSError *error = nil;
    ConstellationDatabase *db = [[ConstellationDatabase alloc] initWithPath:ConstellationTestDBPath(testCase.name)
                                                                      error:&error];
    XCTAssertNotNil(db, @"open db: %@", error);
    XCTAssertTrue([db runMigrations:&error], @"migrate db: %@", error);
    return db;
}

static HttpRequest *ConstellationRequest(NSDictionary *queryParams) {
    return [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                 methodString:@"GET"
                                         path:@"/xrpc/test"
                                  queryString:@""
                                  queryParams:queryParams
                                      version:@"HTTP/1.1"
                                      headers:@{}
                                         body:[NSData data]
                                remoteAddress:@"127.0.0.1"];
}

@interface ConstellationSourceSpecTests : XCTestCase
@end

@interface ConstellationRuntimeTests : XCTestCase
@property (nonatomic, strong) ConstellationRuntime *runtime;
@property (nonatomic, copy) NSString *tempDir;
@end

@implementation ConstellationRuntimeTests

- (void)setUp {
    [super setUp];
    self.runtime = [[ConstellationRuntime alloc] init];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"garazyk-constellation-runtime-%@", NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

- (void)tearDown {
    [self.runtime stop];
    self.runtime = nil;
    if (self.tempDir.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    }
    [super tearDown];
}

- (void)testRuntimeHealthEndpoint {
    NSDictionary *config = @{
        @"data_directory": self.tempDir,
        @"port": @0,
        @"ingest_enabled": @NO,
        @"relay_urls": @[]
    };
    NSData *configData = [NSJSONSerialization dataWithJSONObject:config options:0 error:nil];
    NSString *configPath = [self.tempDir stringByAppendingPathComponent:@"constellation.json"];
    XCTAssertTrue([configData writeToFile:configPath atomically:YES]);

    NSError *error = nil;
    XCTAssertTrue([self.runtime loadConfiguration:configPath error:&error], @"%@", error);
    BOOL started = [self.runtime startWithError:&error];
    XCTAssertTrue(started, @"%@", error);
    if (!started) return;
    XCTAssertGreaterThan(self.runtime.configuration.httpPort, 0u);

    NSURL *url = [NSURL URLWithString:
        [NSString stringWithFormat:@"http://127.0.0.1:%lu/_health",
                                   (unsigned long)self.runtime.configuration.httpPort]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"constellation health"];
    [[[NSURLSession sharedSession] dataTaskWithURL:url
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *requestError) {
        XCTAssertNil(requestError);
        NSHTTPURLResponse *httpResponse = [response isKindOfClass:[NSHTTPURLResponse class]]
            ? (NSHTTPURLResponse *)response
            : nil;
        XCTAssertEqual(httpResponse.statusCode, 200);
        NSDictionary *json = data.length > 0
            ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]
            : nil;
        XCTAssertEqualObjects(json[@"status"], @"ok");
        XCTAssertEqualObjects(json[@"ingest"], @"stopped");
        [expectation fulfill];
    }] resume];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

@end

@implementation ConstellationSourceSpecTests

- (void)testSourceParserAcceptsCollectionAndPath {
    NSError *error = nil;
    ConstellationSourceSpec *source =
        [ConstellationSourceSpec sourceSpecWithString:@"app.bsky.feed.like:subject.uri"
                                                error:&error];
    XCTAssertNotNil(source, @"%@", error);
    XCTAssertEqualObjects(source.collection, @"app.bsky.feed.like");
    XCTAssertEqualObjects(source.path, @"subject.uri");

    ConstellationSourceSpec *arraySource =
        [ConstellationSourceSpec sourceSpecWithString:@"sh.tangled.label.op:add[].key"
                                                error:&error];
    XCTAssertNotNil(arraySource, @"%@", error);
    XCTAssertEqualObjects(arraySource.path, @"add[].key");

    ConstellationSourceSpec *legacyLeadingDot =
        [ConstellationSourceSpec sourceSpecWithString:@"app.bsky.feed.like:.subject.uri"
                                                error:&error];
    XCTAssertNotNil(legacyLeadingDot, @"%@", error);
    XCTAssertEqualObjects(legacyLeadingDot.path, @"subject.uri");
}

- (void)testSourceParserRejectsMalformedSource {
    NSError *error = nil;
    ConstellationSourceSpec *source =
        [ConstellationSourceSpec sourceSpecWithString:@"app.bsky.feed.like.subject.uri"
                                                error:&error];
    XCTAssertNil(source);
    XCTAssertNotNil(error);
}

- (void)testExtractorFindsNestedAndArraySubjects {
    NSDictionary *record = @{
        @"subject": @{@"uri": @"at://did:plc:post/app.bsky.feed.post/1"},
        @"facets": @[
            @{@"features": @[@{@"uri": @"https://example.com/a"}]},
            @{@"features": @[@{@"did": @"did:plc:mentioned"}]}
        ]
    };

    NSArray *subjectURIs = [ConstellationLinkExtractor subjectsInRecord:record path:@"subject.uri"];
    XCTAssertEqualObjects(subjectURIs, (@[@"at://did:plc:post/app.bsky.feed.post/1"]));

    NSArray *featureURIs = [ConstellationLinkExtractor subjectsInRecord:record path:@"facets[].features[].uri"];
    XCTAssertEqualObjects(featureURIs, (@[@"https://example.com/a"]));

    NSArray *entries = [ConstellationLinkExtractor linkEntriesInRecord:record];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"path == %@ AND subject == %@",
                              @"facets[].features[].did", @"did:plc:mentioned"];
    XCTAssertEqual([entries filteredArrayUsingPredicate:predicate].count, 1u);
}

@end

@interface ConstellationDatabaseTests : XCTestCase
@property (nonatomic, strong) ConstellationDatabase *db;
@end

@implementation ConstellationDatabaseTests

- (void)setUp {
    [super setUp];
    self.db = ConstellationOpenTestDB(self);
}

- (void)tearDown {
    [self.db close];
    self.db = nil;
    [super tearDown];
}

- (void)testBacklinksUpdateAndDidFilter {
    NSError *error = nil;
    NSDictionary *like = @{@"$type": @"app.bsky.feed.like",
                           @"subject": @{@"uri": @"at://did:plc:target/app.bsky.feed.post/one"}};
    XCTAssertTrue([self.db indexRecord:like
                                   did:@"did:plc:alice"
                            collection:@"app.bsky.feed.like"
                                  rkey:@"like1"
                                   cid:@"cid1"
                                   seq:10
                                 error:&error], @"%@", error);

    ConstellationSourceSpec *source =
        [ConstellationSourceSpec sourceSpecWithString:@"app.bsky.feed.like:subject.uri" error:&error];
    NSInteger total = 0;
    NSArray *records = [self.db backlinkRecordsForSubject:@"at://did:plc:target/app.bsky.feed.post/one"
                                                    source:source
                                                didFilters:@[@"did:plc:alice"]
                                                     limit:16
                                                    cursor:nil
                                                nextCursor:nil
                                                     total:&total
                                                     error:&error];
    XCTAssertEqual(total, 1);
    XCTAssertEqual(records.count, 1u);
    XCTAssertEqualObjects(records.firstObject[@"did"], @"did:plc:alice");

    NSDictionary *updated = @{@"$type": @"app.bsky.feed.like",
                              @"subject": @{@"uri": @"at://did:plc:target/app.bsky.feed.post/two"}};
    XCTAssertTrue([self.db indexRecord:updated
                                   did:@"did:plc:alice"
                            collection:@"app.bsky.feed.like"
                                  rkey:@"like1"
                                   cid:@"cid2"
                                   seq:11
                                 error:&error], @"%@", error);

    NSInteger oldCount = [self.db backlinksCountForSubject:@"at://did:plc:target/app.bsky.feed.post/one"
                                                    source:source
                                                     error:&error];
    NSInteger newCount = [self.db backlinksCountForSubject:@"at://did:plc:target/app.bsky.feed.post/two"
                                                    source:source
                                                     error:&error];
    XCTAssertEqual(oldCount, 0);
    XCTAssertEqual(newCount, 1);
}

- (void)testBacklinkDidsAndCursor {
    NSError *error = nil;
    ConstellationSourceSpec *source =
        [ConstellationSourceSpec sourceSpecWithString:@"app.bsky.graph.follow:subject" error:&error];
    for (NSInteger i = 0; i < 2; i++) {
        NSString *did = [NSString stringWithFormat:@"did:plc:user%ld", (long)i];
        NSString *rkey = [NSString stringWithFormat:@"follow%ld", (long)i];
        NSDictionary *follow = @{@"$type": @"app.bsky.graph.follow", @"subject": @"did:plc:target"};
        XCTAssertTrue([self.db indexRecord:follow
                                       did:did
                                collection:@"app.bsky.graph.follow"
                                      rkey:rkey
                                       cid:nil
                                       seq:20 + i
                                     error:&error], @"%@", error);
    }

    NSString *cursor = nil;
    NSInteger total = 0;
    NSArray *page1 = [self.db backlinkDIDsForSubject:@"did:plc:target"
                                              source:source
                                               limit:1
                                              cursor:nil
                                          nextCursor:&cursor
                                               total:&total
                                               error:&error];
    XCTAssertEqual(total, 2);
    XCTAssertEqual(page1.count, 1u);
    XCTAssertNotNil(cursor);

    NSArray *page2 = [self.db backlinkDIDsForSubject:@"did:plc:target"
                                              source:source
                                               limit:1
                                              cursor:cursor
                                          nextCursor:nil
                                               total:&total
                                               error:&error];
    XCTAssertEqual(page2.count, 1u);
    XCTAssertNotEqualObjects(page1.firstObject, page2.firstObject);
}

- (void)testManyToManyItemsAndCounts {
    NSError *error = nil;
    NSDictionary *item1 = @{@"$type": @"app.bsky.graph.listitem",
                            @"subject": @"did:plc:bob",
                            @"list": @"at://did:plc:alice/app.bsky.graph.list/main"};
    NSDictionary *item2 = @{@"$type": @"app.bsky.graph.listitem",
                            @"subject": @"did:plc:bob",
                            @"list": @"at://did:plc:alice/app.bsky.graph.list/main"};
    XCTAssertTrue([self.db indexRecord:item1 did:@"did:plc:alice" collection:@"app.bsky.graph.listitem" rkey:@"one" cid:nil seq:30 error:&error], @"%@", error);
    XCTAssertTrue([self.db indexRecord:item2 did:@"did:plc:carol" collection:@"app.bsky.graph.listitem" rkey:@"two" cid:nil seq:31 error:&error], @"%@", error);

    ConstellationSourceSpec *source =
        [ConstellationSourceSpec sourceSpecWithString:@"app.bsky.graph.listitem:subject" error:&error];
    NSArray *items = [self.db manyToManyItemsForSubject:@"did:plc:bob"
                                                 source:source
                                            pathToOther:@"list"
                                               linkDIDs:@[]
                                          otherSubjects:@[]
                                                  limit:16
                                                 cursor:nil
                                             nextCursor:nil
                                                  error:&error];
    XCTAssertEqual(items.count, 2u);

    NSArray *counts = [self.db manyToManyCountsForSubject:@"did:plc:bob"
                                                   source:source
                                              pathToOther:@"list"
                                                     dids:@[]
                                            otherSubjects:@[]
                                                    limit:16
                                                   cursor:nil
                                               nextCursor:nil
                                                    error:&error];
    XCTAssertEqual(counts.count, 1u);
    XCTAssertEqualObjects(counts.firstObject[@"subject"], @"at://did:plc:alice/app.bsky.graph.list/main");
    XCTAssertEqual([counts.firstObject[@"total"] integerValue], 2);
    XCTAssertEqual([counts.firstObject[@"distinct"] integerValue], 2);
}

- (void)testIndexesSpecialRkeyPath {
    NSError *error = nil;
    NSDictionary *record = @{@"$type": @"sh.tangled.graph.vouch", @"createdAt": @"2026-05-15T00:00:00.000Z"};
    XCTAssertTrue([self.db indexRecord:record
                                   did:@"did:plc:alice"
                            collection:@"sh.tangled.graph.vouch"
                                  rkey:@"did:plc:bob"
                                   cid:nil
                                   seq:40
                                 error:&error], @"%@", error);

    ConstellationSourceSpec *source =
        [ConstellationSourceSpec sourceSpecWithString:@"sh.tangled.graph.vouch:." error:&error];
    NSInteger total = [self.db backlinksCountForSubject:@"did:plc:bob"
                                                 source:source
                                                  error:&error];
    XCTAssertEqual(total, 1);
}

- (void)testRecordByUriHonorsCid {
    NSError *error = nil;
    NSDictionary *record = @{@"$type": @"app.bsky.feed.post", @"text": @"hello"};
    XCTAssertTrue([self.db indexRecord:record did:@"did:plc:alice" collection:@"app.bsky.feed.post" rkey:@"one" cid:@"cid-ok" seq:1 error:&error], @"%@", error);

    NSDictionary *found = [self.db recordByURI:@"at://did:plc:alice/app.bsky.feed.post/one"
                                           cid:@"cid-ok"
                                         error:&error];
    XCTAssertEqualObjects(found[@"cid"], @"cid-ok");
    XCTAssertEqualObjects(found[@"value"][@"text"], @"hello");

    NSDictionary *missing = [self.db recordByURI:@"at://did:plc:alice/app.bsky.feed.post/one"
                                             cid:@"cid-other"
                                           error:&error];
    XCTAssertNil(missing);
    XCTAssertEqual(error.code, 404);
}

@end

@interface ConstellationXrpcRoutePackTests : XCTestCase
@property (nonatomic, strong) ConstellationDatabase *db;
@property (nonatomic, strong) ConstellationXrpcRoutePack *routes;
@end

@implementation ConstellationXrpcRoutePackTests

- (void)setUp {
    [super setUp];
    self.db = ConstellationOpenTestDB(self);
    self.routes = [[ConstellationXrpcRoutePack alloc] initWithDatabase:self.db];

    NSError *error = nil;
    NSDictionary *like = @{@"$type": @"app.bsky.feed.like",
                           @"subject": @{@"uri": @"at://did:plc:target/app.bsky.feed.post/one"}};
    XCTAssertTrue([self.db indexRecord:like did:@"did:plc:alice" collection:@"app.bsky.feed.like" rkey:@"like1" cid:@"cid1" seq:10 error:&error], @"%@", error);
}

- (void)tearDown {
    [self.db close];
    self.routes = nil;
    self.db = nil;
    [super tearDown];
}

- (void)testGetBacklinksResponseShape {
    HttpRequest *request = ConstellationRequest(@{
        @"subject": @"at://did:plc:target/app.bsky.feed.post/one",
        @"source": @"app.bsky.feed.like:subject.uri"
    });
    HttpResponse *response = [HttpResponse response];

    [self.routes handleGetBacklinks:request response:response];

    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(response.jsonBody[@"total"], @1);
    NSArray *records = response.jsonBody[@"records"];
    XCTAssertEqual(records.count, 1u);
    XCTAssertEqualObjects(records.firstObject[@"collection"], @"app.bsky.feed.like");
}

- (void)testRejectsLimitAboveLexiconMaximum {
    HttpRequest *request = ConstellationRequest(@{
        @"subject": @"at://did:plc:target/app.bsky.feed.post/one",
        @"source": @"app.bsky.feed.like:subject.uri",
        @"limit": @"101"
    });
    HttpResponse *response = [HttpResponse response];

    [self.routes handleGetBacklinks:request response:response];

    XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
    XCTAssertEqualObjects(response.jsonBody[@"error"], @"InvalidRequest");
}

- (void)testGetRecordByUriLocalRecord {
    HttpRequest *request = ConstellationRequest(@{
        @"at_uri": @"at://did:plc:alice/app.bsky.feed.like/like1",
        @"cid": @"cid1"
    });
    HttpResponse *response = [HttpResponse response];

    [self.routes handleGetRecordByUri:request response:response];

    XCTAssertEqual(response.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(response.jsonBody[@"cid"], @"cid1");
    XCTAssertEqualObjects(response.jsonBody[@"value"][@"$type"], @"app.bsky.feed.like");
}

- (void)testGetManyToManyAcceptsDidAlias {
    NSError *error = nil;
    NSDictionary *item = @{@"$type": @"app.bsky.graph.listitem",
                           @"subject": @"did:plc:bob",
                           @"list": @"at://did:plc:alice/app.bsky.graph.list/main"};
    XCTAssertTrue([self.db indexRecord:item
                                   did:@"did:plc:alice"
                            collection:@"app.bsky.graph.listitem"
                                  rkey:@"item1"
                                   cid:nil
                                   seq:20
                                 error:&error], @"%@", error);

    HttpRequest *request = ConstellationRequest(@{
        @"subject": @"did:plc:bob",
        @"source": @"app.bsky.graph.listitem:subject",
        @"pathToOther": @"list",
        @"did": @"did:plc:alice"
    });
    HttpResponse *response = [HttpResponse response];

    [self.routes handleGetManyToMany:request response:response];

    XCTAssertEqual(response.statusCode, HttpStatusOK);
    NSArray *items = response.jsonBody[@"items"];
    XCTAssertEqual(items.count, 1u);
    XCTAssertEqualObjects(items.firstObject[@"linkRecord"][@"did"], @"did:plc:alice");
}

@end
