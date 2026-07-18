// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/Indexers/AppViewActorIndexer.h"
#import "AppView/Server/Indexers/AppViewFeedIndexer.h"
#import "AppView/Server/Indexers/AppViewGraphIndexer.h"
#import "AppView/Server/Indexers/AppViewNotificationIndexer.h"
#import "AppView/Server/Indexers/AppViewGenericIndexer.h"
#import "AppView/Server/Indexers/AppViewBookmarkIndexer.h"
#import "AppView/Server/Indexers/AppViewGroupIndexer.h"
#import "AppView/Server/Indexers/AppViewIndexer.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconValidator.h"

@interface AppViewIndexerTests : XCTestCase
@property (nonatomic, strong) AppViewDatabase *database;
@end

@implementation AppViewIndexerTests

- (void)setUp {
    [super setUp];
    NSError *error = nil;
    self.database = [[AppViewDatabase alloc] initInMemoryWithError:&error];
    XCTAssertNotNil(self.database, @"Failed to create in-memory database: %@", error);
    BOOL migrated = [self.database runMigrations:&error];
    XCTAssertTrue(migrated, @"Failed to run migrations: %@", error);
}

- (void)tearDown {
    self.database = nil;
    [super tearDown];
}

#pragma mark - Helpers

- (NSDictionary *)sampleProfileRecord {
    return @{@"displayName": @"Test User", @"description": @"A test bio"};
}

- (NSDictionary *)samplePostRecord {
    return @{@"$type": @"app.bsky.feed.post", @"text": @"Hello world"};
}

- (NSDictionary *)sampleLikeRecord {
    return @{@"$type": @"app.bsky.feed.like", @"subject": @{@"uri": @"at://did:plc:other/app.bsky.feed.post/abc", @"cid": @"bafyreicid"}};
}

- (NSDictionary *)sampleRepostRecord {
    return @{@"$type": @"app.bsky.feed.repost", @"subject": @{@"uri": @"at://did:plc:other/app.bsky.feed.post/abc", @"cid": @"bafyreicid"}};
}

- (NSDictionary *)sampleFollowRecord {
    return @{@"$type": @"app.bsky.graph.follow", @"subject": @"did:plc:target"};
}

- (NSDictionary *)sampleBlockRecord {
    return @{@"$type": @"app.bsky.graph.block", @"subject": @"did:plc:target"};
}

- (NSDictionary *)sampleGroupRecord {
    return @{@"name": @"Test Group", @"description": @"A group"};
}

#pragma mark - AppViewActorIndexer

- (void)testActorIndexerInstantiation {
    AppViewActorIndexer *indexer = [[AppViewActorIndexer alloc] initWithDatabase:self.database];
    XCTAssertNotNil(indexer);
}

- (void)testActorIndexerCanIndexProfile {
    AppViewActorIndexer *indexer = [[AppViewActorIndexer alloc] initWithDatabase:self.database];
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.actor.profile"]);
}

- (void)testActorIndexerRejectsOtherCollections {
    AppViewActorIndexer *indexer = [[AppViewActorIndexer alloc] initWithDatabase:self.database];
    XCTAssertFalse([indexer canIndexCollection:@"app.bsky.feed.post"]);
    XCTAssertFalse([indexer canIndexCollection:@"app.bsky.graph.follow"]);
}

- (void)testActorIndexerIndexRecord {
    AppViewActorIndexer *indexer = [[AppViewActorIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer indexRecord:[self sampleProfileRecord]
                                   did:@"did:plc:actor1"
                            collection:@"app.bsky.actor.profile"
                                  rkey:@"self"
                                   cid:@"bafytestcid123"
                                 error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testActorIndexerDeleteRecord {
    AppViewActorIndexer *indexer = [[AppViewActorIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer deleteRecord:@"self"
                                   did:@"did:plc:actor1"
                            collection:@"app.bsky.actor.profile"
                                 error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testActorIndexerDeleteRecordDoesNotReturnError {
    AppViewActorIndexer *indexer = [[AppViewActorIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer deleteRecord:@"nonexistent"
                                   did:@"did:plc:nobody"
                            collection:@"app.bsky.actor.profile"
                                 error:&error];
    XCTAssertTrue(result);
}

#pragma mark - AppViewFeedIndexer

- (void)testFeedIndexerInstantiation {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    XCTAssertNotNil(indexer);
}

- (void)testFeedIndexerCanIndexFeedCollections {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.feed.post"]);
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.feed.repost"]);
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.feed.like"]);
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.feed.generator"]);
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.feed.threadgate"]);
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.feed.postgate"]);
}

- (void)testFeedIndexerRejectsNonFeedCollections {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    XCTAssertFalse([indexer canIndexCollection:@"app.bsky.actor.profile"]);
    XCTAssertFalse([indexer canIndexCollection:@"app.bsky.graph.follow"]);
}

- (void)testFeedIndexerIndexPost {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer indexRecord:[self samplePostRecord]
                                   did:@"did:plc:author1"
                            collection:@"app.bsky.feed.post"
                                  rkey:@"post1"
                                   cid:@"bafypostcid"
                                 error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testFeedIndexerIndexPostMissingTypeFails {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer indexRecord:@{@"text": @"no type"}
                                   did:@"did:plc:author1"
                            collection:@"app.bsky.feed.post"
                                  rkey:@"post1"
                                   cid:nil
                                 error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 1);
}

- (void)testFeedIndexerPostMissingTextAndEmbedFails {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer indexRecord:@{@"$type": @"app.bsky.feed.post"}
                                   did:@"did:plc:author1"
                            collection:@"app.bsky.feed.post"
                                  rkey:@"post1"
                                   cid:nil
                                 error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 2);
}

- (void)testFeedIndexerIndexLike {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer indexRecord:[self sampleLikeRecord]
                                   did:@"did:plc:liker1"
                            collection:@"app.bsky.feed.like"
                                  rkey:@"like1"
                                   cid:nil
                                 error:&error];
    XCTAssertTrue(result);
}

- (void)testFeedIndexerLikeMissingSubjectFails {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer indexRecord:@{@"$type": @"app.bsky.feed.like"}
                                   did:@"did:plc:liker1"
                            collection:@"app.bsky.feed.like"
                                  rkey:@"like1"
                                   cid:nil
                                 error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 3);
}

- (void)testFeedIndexerIndexRepost {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer indexRecord:[self sampleRepostRecord]
                                   did:@"did:plc:reposter1"
                            collection:@"app.bsky.feed.repost"
                                  rkey:@"repost1"
                                   cid:nil
                                 error:&error];
    XCTAssertTrue(result);
}

- (void)testFeedIndexerRepostMissingSubjectFails {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer indexRecord:@{@"$type": @"app.bsky.feed.repost"}
                                   did:@"did:plc:reposter1"
                            collection:@"app.bsky.feed.repost"
                                  rkey:@"repost1"
                                   cid:nil
                                 error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 3);
}

- (void)testFeedIndexerDeleteRecord {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer deleteRecord:@"post1"
                                   did:@"did:plc:author1"
                            collection:@"app.bsky.feed.post"
                                 error:&error];
    XCTAssertTrue(result);
}

#pragma mark - AppViewGraphIndexer

- (void)testGraphIndexerInstantiation {
    AppViewGraphIndexer *indexer = [[AppViewGraphIndexer alloc] initWithDatabase:self.database
                                                                   relevanceSet:nil
                                                                   graphService:nil];
    XCTAssertNotNil(indexer);
}

- (void)testGraphIndexerCanIndexGraphCollections {
    AppViewGraphIndexer *indexer = [[AppViewGraphIndexer alloc] initWithDatabase:self.database
                                                                   relevanceSet:nil
                                                                   graphService:nil];
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.graph.follow"]);
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.graph.block"]);
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.graph.list"]);
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.graph.listitem"]);
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.graph.listblock"]);
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.graph.starterpack"]);
}

- (void)testGraphIndexerRejectsNonGraphCollections {
    AppViewGraphIndexer *indexer = [[AppViewGraphIndexer alloc] initWithDatabase:self.database
                                                                   relevanceSet:nil
                                                                   graphService:nil];
    XCTAssertFalse([indexer canIndexCollection:@"app.bsky.feed.post"]);
    XCTAssertFalse([indexer canIndexCollection:@"app.bsky.actor.profile"]);
}

- (void)testGraphIndexerIndexFollow {
    AppViewGraphIndexer *indexer = [[AppViewGraphIndexer alloc] initWithDatabase:self.database
                                                                   relevanceSet:nil
                                                                   graphService:nil];
    NSError *error = nil;
    BOOL result = [indexer indexRecord:[self sampleFollowRecord]
                                   did:@"did:plc:follower1"
                            collection:@"app.bsky.graph.follow"
                                  rkey:@"follow1"
                                   cid:@"bafyfollowcid"
                                 error:&error];
    XCTAssertTrue(result);
}

- (void)testGraphIndexerIndexBlock {
    AppViewGraphIndexer *indexer = [[AppViewGraphIndexer alloc] initWithDatabase:self.database
                                                                   relevanceSet:nil
                                                                   graphService:nil];
    NSError *error = nil;
    BOOL result = [indexer indexRecord:[self sampleBlockRecord]
                                   did:@"did:plc:blocker1"
                            collection:@"app.bsky.graph.block"
                                  rkey:@"block1"
                                   cid:nil
                                 error:&error];
    XCTAssertTrue(result);
}

- (void)testGraphIndexerDeleteRecord {
    AppViewGraphIndexer *indexer = [[AppViewGraphIndexer alloc] initWithDatabase:self.database
                                                                   relevanceSet:nil
                                                                   graphService:nil];
    NSError *error = nil;
    BOOL result = [indexer deleteRecord:@"follow1"
                                   did:@"did:plc:follower1"
                            collection:@"app.bsky.graph.follow"
                                 error:&error];
    XCTAssertTrue(result);
}

#pragma mark - AppViewNotificationIndexer

- (void)testNotificationIndexerInstantiation {
    AppViewNotificationIndexer *indexer = [[AppViewNotificationIndexer alloc] initWithDatabase:self.database];
    XCTAssertNotNil(indexer);
}

- (void)testNotificationIndexerCanIndexEventSources {
    AppViewNotificationIndexer *indexer = [[AppViewNotificationIndexer alloc] initWithDatabase:self.database];
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.feed.like"]);
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.feed.repost"]);
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.feed.post"]);
    XCTAssertTrue([indexer canIndexCollection:@"app.bsky.graph.follow"]);
}

- (void)testNotificationIndexerRejectsOtherCollections {
    AppViewNotificationIndexer *indexer = [[AppViewNotificationIndexer alloc] initWithDatabase:self.database];
    XCTAssertFalse([indexer canIndexCollection:@"app.bsky.actor.profile"]);
    XCTAssertFalse([indexer canIndexCollection:@"app.bsky.feed.generator"]);
}

- (void)testNotificationIndexerIndexLikeGeneratesNotification {
    AppViewNotificationIndexer *indexer = [[AppViewNotificationIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer indexRecord:[self sampleLikeRecord]
                                   did:@"did:plc:liker1"
                            collection:@"app.bsky.feed.like"
                                  rkey:@"like1"
                                   cid:nil
                                 error:&error];
    XCTAssertTrue(result);
}

- (void)testNotificationIndexerDeleteRecord {
    AppViewNotificationIndexer *indexer = [[AppViewNotificationIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer deleteRecord:@"like1"
                                   did:@"did:plc:liker1"
                            collection:@"app.bsky.feed.like"
                                 error:&error];
    XCTAssertTrue(result);
}

#pragma mark - AppViewGroupIndexer

- (void)testGroupIndexerInstantiation {
    AppViewGroupIndexer *indexer = [[AppViewGroupIndexer alloc] initWithDatabase:self.database];
    XCTAssertNotNil(indexer);
}

- (void)testGroupIndexerCanIndexGroupDefinition {
    AppViewGroupIndexer *indexer = [[AppViewGroupIndexer alloc] initWithDatabase:self.database];
    XCTAssertTrue([indexer canIndexCollection:@"chat.bsky.group.definition"]);
}

- (void)testGroupIndexerRejectsOtherCollections {
    AppViewGroupIndexer *indexer = [[AppViewGroupIndexer alloc] initWithDatabase:self.database];
    XCTAssertFalse([indexer canIndexCollection:@"app.bsky.feed.post"]);
    XCTAssertFalse([indexer canIndexCollection:@"app.bsky.graph.follow"]);
}

- (void)testGroupIndexerIndexGroup {
    AppViewGroupIndexer *indexer = [[AppViewGroupIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer indexRecord:[self sampleGroupRecord]
                                   did:@"did:plc:groupowner"
                            collection:@"chat.bsky.group.definition"
                                  rkey:@"group1"
                                   cid:@"bafygroupcid"
                                 error:&error];
    XCTAssertTrue(result);
}

- (void)testGroupIndexerDeleteRecord {
    AppViewGroupIndexer *indexer = [[AppViewGroupIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    BOOL result = [indexer deleteRecord:@"group1"
                                   did:@"did:plc:groupowner"
                            collection:@"chat.bsky.group.definition"
                                 error:&error];
    XCTAssertTrue(result);
}

#pragma mark - AppViewGenericIndexer

- (void)testGenericIndexerInstantiation {
    ATProtoLexiconRegistry *registry = [[ATProtoLexiconRegistry alloc] init];
    ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];
    NSSet *domainCollections = [NSSet setWithArray:@[@"app.bsky.feed.post", @"app.bsky.actor.profile"]];
    AppViewGenericIndexer *indexer = [[AppViewGenericIndexer alloc] initWithRegistry:registry
                                                                           database:self.database
                                                                         validator:validator
                                                         domainIndexerCollections:domainCollections];
    XCTAssertNotNil(indexer);
}

- (void)testGenericIndexerRejectsClaimedCollections {
    ATProtoLexiconRegistry *registry = [[ATProtoLexiconRegistry alloc] init];
    ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];
    NSSet *domainCollections = [NSSet setWithArray:@[@"app.bsky.feed.post"]];
    AppViewGenericIndexer *indexer = [[AppViewGenericIndexer alloc] initWithRegistry:registry
                                                                           database:self.database
                                                                         validator:validator
                                                         domainIndexerCollections:domainCollections];
    XCTAssertFalse([indexer canIndexCollection:@"app.bsky.feed.post"]);
}

- (void)testGenericIndexerAddDomainCollection {
    ATProtoLexiconRegistry *registry = [[ATProtoLexiconRegistry alloc] init];
    ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];
    AppViewGenericIndexer *indexer = [[AppViewGenericIndexer alloc] initWithRegistry:registry
                                                                           database:self.database
                                                                         validator:validator
                                                         domainIndexerCollections:[NSSet set]];
    [indexer addDomainIndexerCollection:@"com.example.mycol"];
    XCTAssertFalse([indexer canIndexCollection:@"com.example.mycol"]);
}

#pragma mark - AppViewBookmarkIndexer

- (void)testBookmarkIndexerInstantiation {
    AppViewBookmarkIndexer *indexer = [[AppViewBookmarkIndexer alloc] initWithDatabase:self.database
                                                                     bookmarkService:nil];
    XCTAssertNotNil(indexer);
}

- (void)testBookmarkIndexerConformsToIndexerProtocol {
    AppViewBookmarkIndexer *indexer = [[AppViewBookmarkIndexer alloc] initWithDatabase:self.database
                                                                     bookmarkService:nil];
    XCTAssertTrue([indexer conformsToProtocol:@protocol(AppViewIndexer)]);
}

#pragma mark - Protocol Conformance

- (void)testAllIndexersConformToAppViewIndexerProtocol {
    AppViewActorIndexer *actor = [[AppViewActorIndexer alloc] initWithDatabase:self.database];
    AppViewFeedIndexer *feed = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    AppViewGraphIndexer *graph = [[AppViewGraphIndexer alloc] initWithDatabase:self.database
                                                                relevanceSet:nil
                                                                graphService:nil];
    AppViewNotificationIndexer *notif = [[AppViewNotificationIndexer alloc] initWithDatabase:self.database];
    AppViewGroupIndexer *group = [[AppViewGroupIndexer alloc] initWithDatabase:self.database];

    XCTAssertTrue([actor conformsToProtocol:@protocol(AppViewIndexer)]);
    XCTAssertTrue([feed conformsToProtocol:@protocol(AppViewIndexer)]);
    XCTAssertTrue([graph conformsToProtocol:@protocol(AppViewIndexer)]);
    XCTAssertTrue([notif conformsToProtocol:@protocol(AppViewIndexer)]);
    XCTAssertTrue([group conformsToProtocol:@protocol(AppViewIndexer)]);
}

- (void)testFeedCollectionRoutingIsExclusive {
    AppViewFeedIndexer *feed = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    AppViewGraphIndexer *graph = [[AppViewGraphIndexer alloc] initWithDatabase:self.database
                                                                relevanceSet:nil
                                                                graphService:nil];
    AppViewActorIndexer *actor = [[AppViewActorIndexer alloc] initWithDatabase:self.database];

    NSString *feedCollection = @"app.bsky.feed.post";
    XCTAssertTrue([feed canIndexCollection:feedCollection]);
    XCTAssertFalse([graph canIndexCollection:feedCollection]);
    XCTAssertFalse([actor canIndexCollection:feedCollection]);

    NSString *graphCollection = @"app.bsky.graph.follow";
    XCTAssertFalse([feed canIndexCollection:graphCollection]);
    XCTAssertTrue([graph canIndexCollection:graphCollection]);
    XCTAssertFalse([actor canIndexCollection:graphCollection]);

    NSString *profileCollection = @"app.bsky.actor.profile";
    XCTAssertFalse([feed canIndexCollection:profileCollection]);
    XCTAssertFalse([graph canIndexCollection:profileCollection]);
    XCTAssertTrue([actor canIndexCollection:profileCollection]);
}

@end
