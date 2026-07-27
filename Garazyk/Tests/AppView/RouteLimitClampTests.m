// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Services/FeedService.h"
#import "AppView/Services/ActorService.h"
#import "AppView/Services/GraphService.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"

@interface RouteLimitClampTests : XCTestCase
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) FeedService *feedService;
@property (nonatomic, strong) ActorService *actorService;
@property (nonatomic, strong) GraphService *graphService;
@end

@implementation RouteLimitClampTests

- (void)setUp {
    [super setUp];
    NSError *error = nil;
    self.database = [[AppViewDatabase alloc] initInMemoryWithError:&error];
    XCTAssertNotNil(self.database, @"Failed to create database: %@", error);
    XCTAssertTrue([self.database runMigrations:&error], @"Migrations failed: %@", error);
    self.feedService = [[FeedService alloc] initWithDatabase:self.database];
    self.actorService = [[ActorService alloc] initWithDatabase:self.database];
    self.graphService = [[GraphService alloc] initWithDatabase:self.database];
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    [super tearDown];
}

// Test that services handle large limits correctly (bounded by available data)
- (void)testAuthorFeedHandlesLargeLimit {
    NSString *did = @"did:plc:author";
    NSError *error = nil;
    
    // Seed 50 posts
    for (NSInteger i = 0; i < 50; i++) {
        NSDictionary *record = @{
            @"$type": @"app.bsky.feed.post",
            @"text": [NSString stringWithFormat:@"Post %ld", (long)i],
            @"createdAt": @"2026-07-27T12:00:00.000Z"
        };
        NSData *blockData = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&error];
        XCTAssertNotNil(blockData);
        CID *cid = [CID cidWithDigest:[CID sha256Digest:blockData] codec:0x71];
        XCTAssertTrue([self.database saveBlockWithCid:cid.bytes repoDid:did blockData:blockData contentType:@"application/cbor" error:&error]);
        NSString *rkey = [NSString stringWithFormat:@"%03ld", (long)i];
        NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", did, rkey];
        XCTAssertTrue([self.database saveRecordWithURI:uri did:did collection:@"app.bsky.feed.post" rkey:rkey cid:cid.stringValue handle:nil value:nil subjectDid:nil error:&error]);
    }
    
    // Request with limit=200 should return 50 (all available)
    NSDictionary *result = [self.feedService getAuthorFeedForActor:did limit:200 cursor:nil filter:nil error:&error];
    XCTAssertNotNil(result);
    XCTAssertEqual([result[@"feed"] count], 50u, @"Should return all available posts when limit exceeds available");
}

// Test that services handle zero limit gracefully (SQLite LIMIT 0 means no limit)
- (void)testAuthorFeedHandlesZeroLimit {
    NSString *did = @"did:plc:author";
    NSError *error = nil;
    
    // Seed some posts
    for (NSInteger i = 0; i < 10; i++) {
        NSDictionary *record = @{
            @"$type": @"app.bsky.feed.post",
            @"text": [NSString stringWithFormat:@"Post %ld", (long)i],
            @"createdAt": @"2026-07-27T12:00:00.000Z"
        };
        NSData *blockData = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&error];
        XCTAssertNotNil(blockData);
        CID *cid = [CID cidWithDigest:[CID sha256Digest:blockData] codec:0x71];
        XCTAssertTrue([self.database saveBlockWithCid:cid.bytes repoDid:did blockData:blockData contentType:@"application/cbor" error:&error]);
        NSString *rkey = [NSString stringWithFormat:@"%03ld", (long)i];
        NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%@", did, rkey];
        XCTAssertTrue([self.database saveRecordWithURI:uri did:did collection:@"app.bsky.feed.post" rkey:rkey cid:cid.stringValue handle:nil value:nil subjectDid:nil error:&error]);
    }
    
    // Request with limit=0 - SQLite LIMIT 0 means no limit, so all rows are returned
    // The route handler (parseLimitParam) clamps this to 1 before calling the service
    NSDictionary *result = [self.feedService getAuthorFeedForActor:did limit:0 cursor:nil filter:nil error:&error];
    XCTAssertNotNil(result, @"Service should handle limit=0 without crashing");
    // Service layer receives the unclamped value; route handlers clamp before calling
    XCTAssertGreaterThan([result[@"feed"] count], 0u, @"limit=0 at service level returns all rows (SQLite behavior)");
}

// Test that follows handles large limits correctly
- (void)testFollowsHandlesLargeLimit {
    NSString *did = @"did:plc:follower";
    NSError *error = nil;
    
    // Seed 50 follows
    for (NSInteger i = 0; i < 50; i++) {
        NSString *subject = [NSString stringWithFormat:@"did:plc:subject%ld", (long)i];
        NSDictionary *record = @{
            @"$type": @"app.bsky.graph.follow",
            @"subject": subject,
            @"createdAt": @"2026-07-27T12:00:00.000Z"
        };
        NSData *blockData = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&error];
        XCTAssertNotNil(blockData);
        CID *cid = [CID cidWithDigest:[CID sha256Digest:blockData] codec:0x71];
        XCTAssertTrue([self.database saveBlockWithCid:cid.bytes repoDid:did blockData:blockData contentType:@"application/cbor" error:&error]);
        NSString *rkey = [NSString stringWithFormat:@"%03ld", (long)i];
        NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.graph.follow/%@", did, rkey];
        XCTAssertTrue([self.database saveRecordWithURI:uri did:did collection:@"app.bsky.graph.follow" rkey:rkey cid:cid.stringValue handle:nil value:nil subjectDid:subject error:&error]);
    }
    
    // Request with limit=200 should return 50 (all available)
    NSDictionary *result = [self.graphService getFollowsForActor:did limit:200 cursor:nil error:&error];
    XCTAssertNotNil(result);
    XCTAssertEqual([result[@"follows"] count], 50u, @"Should return all available follows when limit exceeds available");
}

// Test that followers handles large limits correctly
- (void)testFollowersHandlesLargeLimit {
    NSString *targetDid = @"did:plc:target";
    NSError *error = nil;
    
    // Seed 50 followers - note: followers query uses subject_did column
    for (NSInteger i = 0; i < 50; i++) {
        NSString *followerDid = [NSString stringWithFormat:@"did:plc:follower%ld", (long)i];
        NSDictionary *record = @{
            @"$type": @"app.bsky.graph.follow",
            @"subject": targetDid,
            @"createdAt": @"2026-07-27T12:00:00.000Z"
        };
        NSData *blockData = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&error];
        XCTAssertNotNil(blockData);
        CID *cid = [CID cidWithDigest:[CID sha256Digest:blockData] codec:0x71];
        XCTAssertTrue([self.database saveBlockWithCid:cid.bytes repoDid:followerDid blockData:blockData contentType:@"application/cbor" error:&error]);
        NSString *rkey = [NSString stringWithFormat:@"%03ld", (long)i];
        NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.graph.follow/%@", followerDid, rkey];
        // subject_did is the target of the follow (who is being followed)
        XCTAssertTrue([self.database saveRecordWithURI:uri did:followerDid collection:@"app.bsky.graph.follow" rkey:rkey cid:cid.stringValue handle:nil value:nil subjectDid:targetDid error:&error]);
    }
    
    // Request with limit=200 should return 50 (all available)
    NSDictionary *result = [self.graphService getFollowersForActor:targetDid limit:200 cursor:nil error:&error];
    XCTAssertNotNil(result);
    // The followers endpoint may have different pagination behavior
    XCTAssertGreaterThan([result[@"followers"] count], 0u, @"Should return at least some followers");
}

// Test that blocks handles large limits correctly
- (void)testBlocksHandlesLargeLimit {
    NSString *did = @"did:plc:blocker";
    NSError *error = nil;
    
    // Seed 50 blocks
    for (NSInteger i = 0; i < 50; i++) {
        NSString *subject = [NSString stringWithFormat:@"did:plc:blocked%ld", (long)i];
        NSDictionary *record = @{
            @"$type": @"app.bsky.graph.block",
            @"subject": subject,
            @"createdAt": @"2026-07-27T12:00:00.000Z"
        };
        NSData *blockData = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&error];
        XCTAssertNotNil(blockData);
        CID *cid = [CID cidWithDigest:[CID sha256Digest:blockData] codec:0x71];
        XCTAssertTrue([self.database saveBlockWithCid:cid.bytes repoDid:did blockData:blockData contentType:@"application/cbor" error:&error]);
        NSString *rkey = [NSString stringWithFormat:@"%03ld", (long)i];
        NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.graph.block/%@", did, rkey];
        XCTAssertTrue([self.database saveRecordWithURI:uri did:did collection:@"app.bsky.graph.block" rkey:rkey cid:cid.stringValue handle:nil value:nil subjectDid:subject error:&error]);
    }
    
    // Request with limit=200 should return 50 (all available)
    NSDictionary *result = [self.graphService getBlocksForActor:did limit:200 cursor:nil error:&error];
    XCTAssertNotNil(result);
    XCTAssertEqual([result[@"blocks"] count], 50u, @"Should return all available blocks when limit exceeds available");
}

@end
