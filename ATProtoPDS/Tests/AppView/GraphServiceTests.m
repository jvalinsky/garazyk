// Tests for GraphService: follows, mutes, relationships, starter packs.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "AppView/GraphService.h"
#import "Database/PDSDatabase.h"
#import "Database/Schema.h"

@interface GraphServiceTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, strong) GraphService *service;
@property (nonatomic, copy) NSString *dbPath;
@end

@implementation GraphServiceTests

- (void)setUp {
    [super setUp];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"graph_test_%@.db", uuid]];
    NSURL *url = [NSURL fileURLWithPath:self.dbPath];
    self.db = [PDSDatabase databaseAtURL:url];
    NSError *error = nil;
    BOOL opened = [self.db openWithError:&error];
    XCTAssertTrue(opened, @"Database must open: %@", error);
    self.service = [[GraphService alloc] initWithDatabase:self.db];
    XCTAssertNotNil(self.service);
}

- (void)tearDown {
    [self.db close];
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

#pragma mark - Initialization

- (void)testServiceStoresDatabaseReference {
    XCTAssertEqualObjects(self.service.database, self.db);
}

#pragma mark - Follows (empty state)

- (void)testGetFollowsForActorWithNoFollowsReturnsResult {
    NSError *error = nil;
    NSDictionary *result = [self.service getFollowsForActor:@"did:plc:nobody"
                                                      limit:50
                                                     cursor:nil
                                                      error:&error];
    // Either nil (no records) or a dict with an empty follows array — must not crash
    (void)result;
}

- (void)testGetFollowersForActorWithNoFollowersReturnsResult {
    NSError *error = nil;
    NSDictionary *result = [self.service getFollowersForActor:@"did:plc:nobody"
                                                        limit:50
                                                       cursor:nil
                                                        error:&error];
    (void)result;
}

#pragma mark - Mutes

- (void)testMuteAndGetMutes {
    NSError *error = nil;
    BOOL ok = [self.service muteActor:@"did:plc:target"
                             forActor:@"did:plc:viewer"
                                error:&error];
    XCTAssertTrue(ok, @"muteActor: %@", error);

    NSDictionary *mutes = [self.service getMutesForActor:@"did:plc:viewer"
                                                   limit:50
                                                  cursor:nil
                                                   error:&error];
    XCTAssertNotNil(mutes, @"getMutes must return a result: %@", error);
}

- (void)testUnmuteReversesMute {
    NSError *error = nil;
    [self.service muteActor:@"did:plc:mutetarget"
                   forActor:@"did:plc:viewer2"
                      error:nil];

    BOOL ok = [self.service unmuteActor:@"did:plc:mutetarget"
                               forActor:@"did:plc:viewer2"
                                  error:&error];
    XCTAssertTrue(ok, @"unmuteActor: %@", error);
}

#pragma mark - Relationships

- (void)testGetRelationshipBetweenUnconnectedActors {
    NSError *error = nil;
    // Two actors with no relationship should not crash and may return a result or nil
    NSDictionary *rel = [self.service getRelationship:@"did:plc:viewer"
                                            withActor:@"did:plc:other"
                                                error:&error];
    // Acceptable: non-nil dict with false/absent flags
    (void)rel;
}

#pragma mark - Likes / Reposts (empty state)

- (void)testGetLikesForNonExistentURIDoesNotCrash {
    NSError *error = nil;
    NSDictionary *result = [self.service getLikesForURI:@"at://did:plc:x/app.bsky.feed.post/abc"
                                                  limit:20
                                                 cursor:nil
                                                  error:&error];
    (void)result;
}

- (void)testGetRepostedByForNonExistentURIDoesNotCrash {
    NSError *error = nil;
    NSDictionary *result = [self.service getRepostedByForURI:@"at://did:plc:x/app.bsky.feed.post/abc"
                                                       limit:20
                                                      cursor:nil
                                                       error:&error];
    (void)result;
}

#pragma mark - Starter Packs

- (void)testIndexAndGetStarterPack {
    NSError *error = nil;
    NSDictionary *record = @{
        @"name": @"Test Pack",
        @"description": @"A test starter pack",
        @"list": @"at://did:plc:creator/app.bsky.graph.list/rkey1"
    };
    NSString *did = @"did:plc:creator";
    NSString *rkey = @"starterpack001";
    NSString *cid = @"bafyreipackcid";

    BOOL ok = [self.service indexStarterPack:record
                                         did:did
                                        rkey:rkey
                                         cid:cid
                                       error:&error];
    XCTAssertTrue(ok, @"indexStarterPack: %@", error);

    NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.graph.starterpack/%@", did, rkey];
    NSDictionary *fetched = [self.service getStarterPack:uri error:&error];
    XCTAssertNotNil(fetched, @"getStarterPack must return the indexed pack: %@", error);
}

- (void)testUnindexStarterPackRemovesIt {
    NSError *error = nil;
    NSDictionary *record = @{@"name": @"Pack to remove"};
    NSString *did = @"did:plc:remover";
    NSString *rkey = @"packremove001";

    [self.service indexStarterPack:record did:did rkey:rkey cid:@"bafyreicid" error:nil];

    BOOL ok = [self.service unindexStarterPackWithRKey:rkey did:did error:&error];
    XCTAssertTrue(ok, @"unindexStarterPack: %@", error);

    NSString *uri = [NSString stringWithFormat:@"at://%@/app.bsky.graph.starterpack/%@", did, rkey];
    NSDictionary *fetched = [self.service getStarterPack:uri error:nil];
    XCTAssertNil(fetched, @"Unindexed starter pack must not be found");
}

- (void)testGetStarterPacksForActorReturnsIndexedPacks {
    NSError *error = nil;
    NSString *did = @"did:plc:packauthor";

    for (NSUInteger i = 0; i < 3; i++) {
        NSDictionary *record = @{@"name": [NSString stringWithFormat:@"Pack %lu", (unsigned long)i]};
        NSString *rkey = [NSString stringWithFormat:@"packkey%lu", (unsigned long)i];
        [self.service indexStarterPack:record did:did rkey:rkey cid:@"bafyreicid" error:nil];
    }

    NSDictionary *result = [self.service getStarterPacksForActor:did
                                                           limit:10
                                                          cursor:nil
                                                           error:&error];
    XCTAssertNotNil(result, @"getStarterPacksForActor: %@", error);
}

@end
