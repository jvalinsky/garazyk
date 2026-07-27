// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Services/ActorService.h"
#import "AppView/Server/AppViewDatabase.h"
#import "Core/CID.h"
#import "Core/ATProtoCBORSerialization.h"

// Wraps AppViewDatabase to count every SELECT issued through the shared
// query path, so tests can assert query counts rather than merely observe
// them once. All ActorService reads flow through this single override.
@interface AppViewQueryCountingDatabase : AppViewDatabase
@property (nonatomic, assign) NSUInteger queryCount;
@end

@implementation AppViewQueryCountingDatabase

- (nullable NSArray<NSDictionary *> *)executeParameterizedQuery:(NSString *)sql
                                                          params:(NSArray *)params
                                                           error:(NSError **)error {
    self.queryCount++;
    return [super executeParameterizedQuery:sql params:params error:error];
}

@end

@interface ActorServiceBatchHydrationTests : XCTestCase
@property (nonatomic, strong) AppViewQueryCountingDatabase *database;
@property (nonatomic, strong) ActorService *service;
@end

@implementation ActorServiceBatchHydrationTests

- (void)setUp {
    [super setUp];
    NSError *error = nil;
    self.database = [[AppViewQueryCountingDatabase alloc] initInMemoryWithError:&error];
    XCTAssertNotNil(self.database, @"Failed to create in-memory AppViewDatabase: %@", error);
    XCTAssertTrue([self.database runMigrations:&error], @"Failed to run migrations: %@", error);
    self.service = [[ActorService alloc] initWithDatabase:self.database];
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    self.service = nil;
    [super tearDown];
}

// Seeds a fully-hydrated actor: a handle, a profile record (with a real
// CBOR-encoded block), N posts, and N followers. Returns the actor's DID.
- (NSString *)seedActorAtIndex:(NSInteger)index
                      followers:(NSInteger)followerCount
                          posts:(NSInteger)postCount {
    NSError *error = nil;
    NSString *did = [NSString stringWithFormat:@"did:plc:actor%ld", (long)index];
    NSString *handle = [NSString stringWithFormat:@"actor%ld.test", (long)index];
    XCTAssertTrue([self.database saveHandle:handle did:did error:&error], @"saveHandle failed: %@", error);

    NSDictionary *profileValue = @{
        @"$type": @"app.bsky.actor.profile",
        @"displayName": [NSString stringWithFormat:@"Actor %ld", (long)index],
        @"description": @"test bio"
    };
    NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:profileValue error:&error];
    XCTAssertNotNil(cborData, @"CBOR encode failed: %@", error);
    CID *cid = [CID cidWithDigest:[CID sha256Digest:cborData] codec:0x71];
    XCTAssertNotNil(cid);

    XCTAssertTrue([self.database saveBlockWithCid:cid.bytes
                                           repoDid:did
                                         blockData:cborData
                                       contentType:@"application/cbor"
                                             error:&error],
                  @"saveBlock failed: %@", error);
    NSString *profileURI = [NSString stringWithFormat:@"at://%@/app.bsky.actor.profile/self", did];
    XCTAssertTrue([self.database saveRecordWithURI:profileURI
                                                 did:did
                                          collection:@"app.bsky.actor.profile"
                                                rkey:@"self"
                                                 cid:cid.stringValue
                                              handle:handle
                                               value:nil
                                          subjectDid:nil
                                               error:&error],
                  @"saveRecord (profile) failed: %@", error);

    for (NSInteger i = 0; i < postCount; i++) {
        NSString *postURI = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/%ld", did, (long)i];
        NSString *postRkey = [NSString stringWithFormat:@"%ld", (long)i];
        XCTAssertTrue([self.database saveRecordWithURI:postURI
                                                     did:did
                                              collection:@"app.bsky.feed.post"
                                                    rkey:postRkey
                                                     cid:cid.stringValue
                                                  handle:nil
                                                   value:nil
                                              subjectDid:nil
                                                   error:&error],
                      @"saveRecord (post) failed: %@", error);
    }

    for (NSInteger i = 0; i < followerCount; i++) {
        NSString *followerDid = [NSString stringWithFormat:@"did:plc:actor%ld-follower%ld", (long)index, (long)i];
        NSString *followURI = [NSString stringWithFormat:@"at://%@/app.bsky.graph.follow/%ld", followerDid, (long)i];
        NSString *followRkey = [NSString stringWithFormat:@"%ld", (long)i];
        XCTAssertTrue([self.database saveRecordWithURI:followURI
                                                     did:followerDid
                                              collection:@"app.bsky.graph.follow"
                                                    rkey:followRkey
                                                     cid:cid.stringValue
                                                  handle:nil
                                                   value:nil
                                              subjectDid:did
                                                   error:&error],
                      @"saveRecord (follow) failed: %@", error);
    }

    return did;
}

- (void)testGetProfilesForActorsHydratesCorrectlyAndBatchesQueries {
    NSMutableArray<NSString *> *dids = [NSMutableArray array];
    for (NSInteger i = 0; i < 50; i++) {
        [dids addObject:[self seedActorAtIndex:i followers:(i % 5) posts:(i % 3)]];
    }

    self.database.queryCount = 0;
    NSError *error = nil;
    NSArray<NSDictionary *> *profiles = [self.service getProfilesForActors:dids error:&error];
    NSUInteger queriesFor50 = self.database.queryCount;

    XCTAssertNotNil(profiles);
    XCTAssertNil(error);
    XCTAssertEqual(profiles.count, dids.count);

    for (NSInteger i = 0; i < (NSInteger)profiles.count; i++) {
        NSDictionary *profile = profiles[i];
        XCTAssertEqualObjects(profile[@"did"], dids[i]);
        XCTAssertEqualObjects(profile[@"handle"], ([NSString stringWithFormat:@"actor%ld.test", (long)i]));
        XCTAssertEqualObjects(profile[@"displayName"], ([NSString stringWithFormat:@"Actor %ld", (long)i]));
        XCTAssertEqualObjects(profile[@"followersCount"], @(i % 5));
        XCTAssertEqualObjects(profile[@"postsCount"], @(i % 3));
    }

    // The defect this phase fixes is query volume: hydrating 5 actors must
    // cost the same number of queries as hydrating 50 — bounded, not O(n).
    self.database.queryCount = 0;
    NSArray<NSDictionary *> *smallBatch = [self.service getProfilesForActors:[dids subarrayWithRange:NSMakeRange(0, 5)] error:&error];
    NSUInteger queriesFor5 = self.database.queryCount;

    XCTAssertEqual(smallBatch.count, (NSUInteger)5);
    XCTAssertEqual(queriesFor50, queriesFor5, @"query count must be independent of page size");
    XCTAssertLessThanOrEqual(queriesFor50, (NSUInteger)10,
                              @"profile hydration must issue a small, bounded number of queries, not O(n)");
}

@end
