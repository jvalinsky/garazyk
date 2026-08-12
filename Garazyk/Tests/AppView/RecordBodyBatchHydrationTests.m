// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Services/FeedService.h"
#import "AppView/Services/GraphService.h"
#import "AppView/Server/AppViewDatabase.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"

@interface RecordBodyQueryCountingDatabase : AppViewDatabase
@property (nonatomic, assign) NSUInteger queryCount;
@end

@implementation RecordBodyQueryCountingDatabase

- (nullable NSArray<NSDictionary *> *)executeParameterizedQuery:(NSString *)sql
                                                          params:(NSArray *)params
                                                           error:(NSError **)error {
    self.queryCount++;
    return [super executeParameterizedQuery:sql params:params error:error];
}

@end

@interface RecordBodyBatchHydrationTests : XCTestCase
@property (nonatomic, strong) RecordBodyQueryCountingDatabase *database;
@property (nonatomic, strong) PDSFeedService *feedService;
@property (nonatomic, strong) PDSGraphService *graphService;
@end

@implementation RecordBodyBatchHydrationTests

- (void)setUp {
    [super setUp];
    NSError *error = nil;
    self.database = [[RecordBodyQueryCountingDatabase alloc] initInMemoryWithError:&error];
    XCTAssertNotNil(self.database, @"Failed to create in-memory AppViewDatabase: %@", error);
    XCTAssertTrue([self.database runMigrations:&error], @"Failed to run migrations: %@", error);
    self.feedService = [[PDSFeedService alloc] initWithDatabase:self.database];
    self.graphService = [[PDSGraphService alloc] initWithDatabase:self.database];
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.feedService = nil;
    self.graphService = nil;
    [super tearDown];
}

- (void)seedPosts:(NSInteger)count forActor:(NSString *)did {
    NSError *error = nil;
    for (NSInteger index = 0; index < count; index++) {
        NSDictionary *record = @{
            @"$type": @"app.bsky.feed.post",
            @"text": [NSString stringWithFormat:@"Post %ld", (long)index],
            @"createdAt": @"2026-07-27T12:00:00.000Z"
        };
        NSData *blockData = [[[ATProtoCBORSerialization alloc] initWithContentAddressed:YES] encodeDataWithJSONObject:record error:&error];
        XCTAssertNotNil(blockData, @"CBOR encode failed: %@", error);
        ATProtoCID *cid = [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:blockData] codec:0x71];
        XCTAssertTrue([self.database saveBlockWithCid:cid.bytes repoDid:did blockData:blockData contentType:@"application/cbor" error:&error], @"saveBlock failed: %@", error);
        NSString *rkey = [NSString stringWithFormat:@"%03ld", (long)index];
        NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", did, rkey];
        XCTAssertTrue([self.database saveRecordWithURI:uri did:did collection:@"app.bsky.feed.post" rkey:rkey cid:cid.stringValue handle:nil value:nil subjectDid:nil error:&error], @"saveRecord failed: %@", error);
        XCTAssertTrue(([self.database executeParameterizedUpdate:@"UPDATE records SET created_at = ? WHERE uri = ?" params:@[@"2026-07-27T12:00:00.000Z", uri] error:&error]), @"set created_at failed: %@", error);
    }
}

- (void)seedFollows:(NSInteger)count forActor:(NSString *)did {
    NSError *error = nil;
    for (NSInteger index = 0; index < count; index++) {
        NSString *subject = [NSString stringWithFormat:@"did:plc:subject%ld", (long)index];
        NSDictionary *record = @{
            @"$type": @"app.bsky.graph.follow",
            @"subject": subject,
            @"createdAt": @"2026-07-27T12:00:00.000Z"
        };
        NSData *blockData = [[[ATProtoCBORSerialization alloc] initWithContentAddressed:YES] encodeDataWithJSONObject:record error:&error];
        XCTAssertNotNil(blockData, @"CBOR encode failed: %@", error);
        ATProtoCID *cid = [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:blockData] codec:0x71];
        XCTAssertTrue([self.database saveBlockWithCid:cid.bytes repoDid:did blockData:blockData contentType:@"application/cbor" error:&error], @"saveBlock failed: %@", error);
        NSString *rkey = [NSString stringWithFormat:@"%03ld", (long)index];
        NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.graph.follow/%@", did, rkey];
        XCTAssertTrue([self.database saveRecordWithURI:uri did:did collection:@"app.bsky.graph.follow" rkey:rkey cid:cid.stringValue handle:nil value:nil subjectDid:subject error:&error], @"saveRecord failed: %@", error);
    }
}

- (void)captureResponse:(NSDictionary *)response named:(NSString *)name {
    NSString *directory = [[[NSProcessInfo processInfo] environment] objectForKey:@"PHASE21_CAPTURE_DIRECTORY"];
    if (directory.length == 0) return;

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:&error];
    XCTAssertNotNil(data, @"Response serialization failed: %@", error);
    XCTAssertTrue([data writeToFile:[directory stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:&error], @"Response capture failed: %@", error);
}

- (void)testAuthorFeedRecordBodiesArePayloadStableAndQueryBounded {
    NSString *did = @"did:plc:author";
    [self seedPosts:50 forActor:did];

    NSError *error = nil;
    self.database.queryCount = 0;
    NSDictionary *pageOf50 = [self.feedService getAuthorFeedForActor:did limit:50 cursor:nil filter:nil error:&error];
    NSUInteger queriesFor50 = self.database.queryCount;
    XCTAssertNotNil(pageOf50);
    XCTAssertNil(error);
    XCTAssertEqual([pageOf50[@"feed"] count], 50U);
    [self captureResponse:pageOf50 named:@"author-feed.json"];

    self.database.queryCount = 0;
    NSDictionary *pageOf5 = [self.feedService getAuthorFeedForActor:did limit:5 cursor:nil filter:nil error:&error];
    NSUInteger queriesFor5 = self.database.queryCount;
    XCTAssertNotNil(pageOf5);
    XCTAssertEqual([pageOf5[@"feed"] count], 5U);
    XCTAssertEqualObjects([pageOf5[@"feed"] firstObject][@"record"][@"text"], @"Post 49");
    XCTAssertEqual(queriesFor50, queriesFor5, @"record-body hydration must be independent of page size");
    XCTAssertLessThanOrEqual(queriesFor50, 30U, @"record-body hydration must issue a bounded number of queries");
}

- (void)testFollowsRecordBodiesArePayloadStableAndQueryBounded {
    NSString *did = @"did:plc:follower";
    [self seedFollows:50 forActor:did];

    NSError *error = nil;
    self.database.queryCount = 0;
    NSDictionary *pageOf50 = [self.graphService getFollowsForActor:did limit:50 cursor:nil error:&error];
    NSUInteger queriesFor50 = self.database.queryCount;
    XCTAssertNotNil(pageOf50);
    XCTAssertNil(error);
    XCTAssertEqual([pageOf50[@"follows"] count], 50U);
    [self captureResponse:pageOf50 named:@"follows.json"];

    self.database.queryCount = 0;
    NSDictionary *pageOf5 = [self.graphService getFollowsForActor:did limit:5 cursor:nil error:&error];
    NSUInteger queriesFor5 = self.database.queryCount;
    XCTAssertNotNil(pageOf5);
    XCTAssertEqual([pageOf5[@"follows"] count], 5U);
    XCTAssertEqualObjects([pageOf5[@"follows"] firstObject][@"did"], @"did:plc:subject49");
    XCTAssertEqual(queriesFor50, queriesFor5, @"record-body hydration must be independent of page size");
    XCTAssertLessThanOrEqual(queriesFor50, 12U, @"record-body hydration must issue a bounded number of queries");
}

@end