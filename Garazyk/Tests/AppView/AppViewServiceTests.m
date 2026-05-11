// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"
#import "AppView/Server/Indexers/AppViewFeedIndexer.h"
#import "AppView/Server/Indexers/AppViewGraphIndexer.h"
#import "AppView/Server/Indexers/AppViewNotificationIndexer.h"
#import "AppView/Server/Relevance/AppViewRelevanceSet.h"
#import "AppView/Services/BookmarkService.h"
#import "AppView/Services/FeedService.h"
#import "AppView/Services/GraphService.h"
#import "AppView/Services/NotificationService.h"
#import "AppView/Services/RecordLifecycleHandler.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/PDSRecordEvents.h"

#pragma mark - Test helpers

static NSDictionary *AVSCall(SEL selector, NSDictionary *payload) {
    NSMutableDictionary *call = payload ? [payload mutableCopy] : [NSMutableDictionary dictionary];
    call[@"selector"] = NSStringFromSelector(selector);
    return [call copy];
}

@interface AppViewFeedIndexer (Testing)
- (BOOL)handleIngestEvent:(AppViewIngestEvent *)event error:(NSError **)error;
- (BOOL)processPendingDelta:(AppViewPendingDelta *)delta error:(NSError **)error;
- (BOOL)deleteRecord:(NSString *)rkey did:(NSString *)did collection:(NSString *)collection error:(NSError **)error;
@end

@interface AppViewGraphIndexer (Testing)
- (BOOL)handleIngestEvent:(AppViewIngestEvent *)event error:(NSError **)error;
- (BOOL)processPendingDelta:(AppViewPendingDelta *)delta error:(NSError **)error;
- (BOOL)deleteRecord:(NSString *)rkey did:(NSString *)did collection:(NSString *)collection error:(NSError **)error;
@end

@interface AppViewNotificationIndexer (Testing)
- (BOOL)handleIngestEvent:(AppViewIngestEvent *)event error:(NSError **)error;
- (BOOL)processPendingDelta:(AppViewPendingDelta *)delta error:(NSError **)error;
- (BOOL)deleteRecord:(NSString *)rkey did:(NSString *)did collection:(NSString *)collection error:(NSError **)error;
@end

#pragma mark - Routing test doubles

@interface RoutingFeedIndexer : AppViewFeedIndexer
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *indexCalls;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *deleteCalls;
@end

@implementation RoutingFeedIndexer
- (instancetype)initWithDatabase:(AppViewDatabase *)database {
    self = [super initWithDatabase:database];
    if (self) {
        _indexCalls = [NSMutableArray array];
        _deleteCalls = [NSMutableArray array];
    }
    return self;
}

- (BOOL)indexRecord:(NSDictionary *)record
                did:(NSString *)did
         collection:(NSString *)collection
                cid:(nullable NSString *)cid
              error:(NSError **)error {
    [self.indexCalls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"collection": collection ?: [NSNull null],
        @"cid": cid ?: [NSNull null],
        @"type": record[@"$type"] ?: [NSNull null],
    })];
    return YES;
}

- (BOOL)deleteRecord:(NSString *)rkey did:(NSString *)did collection:(NSString *)collection error:(NSError **)error {
    [self.deleteCalls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"collection": collection ?: [NSNull null],
        @"rkey": rkey ?: [NSNull null],
    })];
    return YES;
}
@end

@interface RoutingGraphIndexer : AppViewGraphIndexer
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *indexCalls;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *deleteCalls;
@end

@implementation RoutingGraphIndexer
- (instancetype)initWithDatabase:(AppViewDatabase *)database {
    self = [super initWithDatabase:database relevanceSet:nil];
    if (self) {
        _indexCalls = [NSMutableArray array];
        _deleteCalls = [NSMutableArray array];
    }
    return self;
}

- (BOOL)indexRecord:(NSDictionary *)record
                did:(NSString *)did
         collection:(NSString *)collection
                cid:(nullable NSString *)cid
              error:(NSError **)error {
    [self.indexCalls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"collection": collection ?: [NSNull null],
        @"cid": cid ?: [NSNull null],
        @"type": record[@"$type"] ?: [NSNull null],
    })];
    return YES;
}

- (BOOL)deleteRecord:(NSString *)rkey did:(NSString *)did collection:(NSString *)collection error:(NSError **)error {
    [self.deleteCalls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"collection": collection ?: [NSNull null],
        @"rkey": rkey ?: [NSNull null],
    })];
    return YES;
}
@end

@interface RoutingNotificationIndexer : AppViewNotificationIndexer
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *indexCalls;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *deleteCalls;
@end

@implementation RoutingNotificationIndexer
- (instancetype)initWithDatabase:(AppViewDatabase *)database {
    self = [super initWithDatabase:database];
    if (self) {
        _indexCalls = [NSMutableArray array];
        _deleteCalls = [NSMutableArray array];
    }
    return self;
}

- (BOOL)indexRecord:(NSDictionary *)record
                did:(NSString *)did
         collection:(NSString *)collection
                cid:(nullable NSString *)cid
              error:(NSError **)error {
    [self.indexCalls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"collection": collection ?: [NSNull null],
        @"cid": cid ?: [NSNull null],
        @"type": record[@"$type"] ?: [NSNull null],
    })];
    return YES;
}

- (BOOL)deleteRecord:(NSString *)rkey did:(NSString *)did collection:(NSString *)collection error:(NSError **)error {
    [self.deleteCalls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"collection": collection ?: [NSNull null],
        @"rkey": rkey ?: [NSNull null],
    })];
    return YES;
}
@end

#pragma mark - Service tracking doubles

@interface TrackingNotificationService : NotificationService
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *createCalls;
@property(nonatomic, strong) NSMutableArray<NSString *> *deleteCalls;
@end

@implementation TrackingNotificationService
- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super initWithDatabase:database actorService:nil];
    if (self) {
        _createCalls = [NSMutableArray array];
        _deleteCalls = [NSMutableArray array];
    }
    return self;
}

- (BOOL)createNotificationForActor:(NSString *)actorDID
                          authorDID:(NSString *)authorDID
                             reason:(NSString *)reason
                      reasonSubject:(nullable NSString *)reasonSubject
                         subjectURI:(nullable NSString *)subjectURI
                         subjectCID:(nullable NSString *)subjectCID
                              error:(NSError **)error {
    [self.createCalls addObject:AVSCall(_cmd, @{
        @"actorDID": actorDID ?: [NSNull null],
        @"authorDID": authorDID ?: [NSNull null],
        @"reason": reason ?: [NSNull null],
        @"reasonSubject": reasonSubject ?: [NSNull null],
        @"subjectURI": subjectURI ?: [NSNull null],
        @"subjectCID": subjectCID ?: [NSNull null],
    })];
    return YES;
}

- (BOOL)deleteNotificationsForSubjectURI:(NSString *)subjectURI error:(NSError **)error {
    [self.deleteCalls addObject:subjectURI ?: @"<nil>"];
    return YES;
}
@end

@interface TrackingBookmarkService : BookmarkService
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *indexCalls;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *deleteCalls;
@end

@implementation TrackingBookmarkService
- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super initWithDatabase:database];
    if (self) {
        _indexCalls = [NSMutableArray array];
        _deleteCalls = [NSMutableArray array];
    }
    return self;
}

- (BOOL)indexBookmark:(NSDictionary *)record
                  did:(NSString *)did
                  uri:(NSString *)uri
                  cid:(nullable NSString *)cid
                error:(NSError **)error {
    [self.indexCalls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"uri": uri ?: [NSNull null],
        @"cid": cid ?: [NSNull null],
        @"type": record[@"$type"] ?: [NSNull null],
    })];
    return YES;
}

- (BOOL)unindexBookmarkWithURI:(NSString *)uri did:(NSString *)did error:(NSError **)error {
    [self.deleteCalls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"uri": uri ?: [NSNull null],
    })];
    return YES;
}
@end

@interface TrackingGraphService : GraphService
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *calls;
@end

@implementation TrackingGraphService
- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super initWithDatabase:database];
    if (self) {
        _calls = [NSMutableArray array];
    }
    return self;
}

- (BOOL)indexStarterPack:(NSDictionary *)record did:(NSString *)did rkey:(NSString *)rkey cid:(NSString *)cid error:(NSError **)error {
    [self.calls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"rkey": rkey ?: [NSNull null],
        @"cid": cid ?: [NSNull null],
        @"type": record[@"$type"] ?: [NSNull null],
    })];
    return YES;
}

- (BOOL)unindexStarterPackWithRKey:(NSString *)rkey did:(NSString *)did error:(NSError **)error {
    [self.calls addObject:AVSCall(_cmd, @{@"did": did ?: [NSNull null], @"rkey": rkey ?: [NSNull null]})];
    return YES;
}

- (BOOL)indexList:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid error:(NSError **)error {
    [self.calls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"uri": uri ?: [NSNull null],
        @"cid": cid ?: [NSNull null],
        @"type": record[@"$type"] ?: [NSNull null],
    })];
    return YES;
}

- (BOOL)unindexListWithURI:(NSString *)uri error:(NSError **)error {
    [self.calls addObject:AVSCall(_cmd, @{@"uri": uri ?: [NSNull null]})];
    return YES;
}

- (BOOL)indexListitem:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid error:(NSError **)error {
    [self.calls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"uri": uri ?: [NSNull null],
        @"cid": cid ?: [NSNull null],
        @"type": record[@"$type"] ?: [NSNull null],
    })];
    return YES;
}

- (BOOL)unindexListitemWithURI:(NSString *)uri error:(NSError **)error {
    [self.calls addObject:AVSCall(_cmd, @{@"uri": uri ?: [NSNull null]})];
    return YES;
}
@end

@interface TrackingFeedService : FeedService
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *calls;
@end

@implementation TrackingFeedService
- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super initWithDatabase:database];
    if (self) {
        _calls = [NSMutableArray array];
    }
    return self;
}

- (BOOL)indexThreadgate:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid error:(NSError **)error {
    [self.calls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"uri": uri ?: [NSNull null],
        @"cid": cid ?: [NSNull null],
        @"type": record[@"$type"] ?: [NSNull null],
    })];
    return YES;
}

- (BOOL)unindexThreadgateWithURI:(NSString *)uri error:(NSError **)error {
    [self.calls addObject:AVSCall(_cmd, @{@"uri": uri ?: [NSNull null]})];
    return YES;
}

- (BOOL)indexPostgate:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid error:(NSError **)error {
    [self.calls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"uri": uri ?: [NSNull null],
        @"cid": cid ?: [NSNull null],
        @"type": record[@"$type"] ?: [NSNull null],
    })];
    return YES;
}

- (BOOL)unindexPostgateWithURI:(NSString *)uri error:(NSError **)error {
    [self.calls addObject:AVSCall(_cmd, @{@"uri": uri ?: [NSNull null]})];
    return YES;
}

- (BOOL)indexGenerator:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid error:(NSError **)error {
    [self.calls addObject:AVSCall(_cmd, @{
        @"did": did ?: [NSNull null],
        @"uri": uri ?: [NSNull null],
        @"cid": cid ?: [NSNull null],
        @"type": record[@"$type"] ?: [NSNull null],
    })];
    return YES;
}

- (BOOL)unindexGeneratorWithURI:(NSString *)uri error:(NSError **)error {
    [self.calls addObject:AVSCall(_cmd, @{@"uri": uri ?: [NSNull null]})];
    return YES;
}
@end

#pragma mark - AppViewServiceTests

@interface AppViewServiceTests : XCTestCase
@property(nonatomic, strong) NSString *testDirectory;
@property(nonatomic, strong) AppViewDatabase *database;
@property(nonatomic, strong) AppViewRelevanceSet *relevanceSet;
@property(nonatomic, strong) TrackingNotificationService *notificationService;
@property(nonatomic, strong) TrackingBookmarkService *bookmarkService;
@property(nonatomic, strong) TrackingGraphService *graphService;
@property(nonatomic, strong) TrackingFeedService *feedService;
@property(nonatomic, strong) RecordLifecycleHandler *recordLifecycleHandler;
@end

@implementation AppViewServiceTests

- (void)setUp {
    [super setUp];

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"appview_service_tests.db"];
    NSError *error = nil;
    self.database = [[AppViewDatabase alloc] initWithPath:dbPath error:&error];
    XCTAssertNotNil(self.database, @"Failed to open AppViewDatabase: %@", error);
    XCTAssertTrue([self.database runMigrations:&error], @"Failed to migrate AppViewDatabase: %@", error);

    self.relevanceSet = [[AppViewRelevanceSet alloc]
        initWithDatabase:self.database
                seedDIDs:@[]
               allowlist:@[]
                ttlHours:1];

    self.notificationService = [[TrackingNotificationService alloc] initWithDatabase:self.database];
    self.bookmarkService = [[TrackingBookmarkService alloc] initWithDatabase:self.database];
    self.graphService = [[TrackingGraphService alloc] initWithDatabase:self.database];
    self.feedService = [[TrackingFeedService alloc] initWithDatabase:self.database];

    self.recordLifecycleHandler = [[RecordLifecycleHandler alloc]
        initWithNotificationService:self.notificationService
                      bookmarkService:self.bookmarkService
                         graphService:self.graphService
                          feedService:self.feedService
                             database:(PDSDatabase *)self.database];
}

- (void)tearDown {
    [self.recordLifecycleHandler stopObserving];
    self.recordLifecycleHandler = nil;
    self.feedService = nil;
    self.graphService = nil;
    self.bookmarkService = nil;
    self.notificationService = nil;
    self.relevanceSet = nil;

    [self.database close];
    self.database = nil;

    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

#pragma mark - Helpers

- (AppViewIngestEvent *)ingestEventWithDid:(NSString *)did ops:(NSArray<NSDictionary *> *)ops {
    AppViewIngestEvent *event = [[AppViewIngestEvent alloc] init];
    event.seq = 1;
    event.relayURL = @"wss://relay.example";
    event.did = did;
    event.rev = @"rev1";
    event.cid = @"cid1";
    event.eventType = @"#commit";
    event.ops = ops;
    event.rawEnvelope = [NSData data];
    event.receivedAt = [NSDate date];
    return event;
}

- (NSData *)encodedCBORForRecord:(NSDictionary *)record {
    NSError *error = nil;
    NSData *data = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&error];
    XCTAssertNotNil(data, @"Failed to encode CBOR: %@", error);
    return data;
}

- (void)postRecordChangeWithDid:(NSString *)did
                     collection:(NSString *)collection
                          rkey:(NSString *)rkey
                         action:(NSString *)action
                            cid:(nullable NSString *)cid
                         record:(nullable NSDictionary *)record {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (did) {
        userInfo[@"did"] = did;
    }
    if (collection) {
        userInfo[@"collection"] = collection;
    }
    if (rkey) {
        userInfo[@"rkey"] = rkey;
    }
    if (action) {
        userInfo[@"action"] = action;
    }
    if (cid) {
        userInfo[@"cid"] = cid;
    }
    if (record) {
        userInfo[@"recordCBOR"] = [self encodedCBORForRecord:record];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                        object:nil
                                                      userInfo:userInfo];
}

- (void)waitUntilDID:(NSString *)did becomesRelevant:(BOOL)expected {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
        if ([self.database isDIDRelevant:did] == expected) {
            return;
        }
        [NSThread sleepForTimeInterval:0.01];
    }
    XCTAssertEqual([self.database isDIDRelevant:did], expected);
}

#pragma mark - Feed indexer

- (void)testFeedIndexerCanIndexSupportedCollections {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];

    NSArray<NSString *> *supported = @[
        @"app.bsky.feed.post",
        @"app.bsky.feed.repost",
        @"app.bsky.feed.like",
        @"app.bsky.feed.generator",
        @"app.bsky.feed.threadgate",
        @"app.bsky.feed.postgate",
    ];
    for (NSString *collection in supported) {
        XCTAssertTrue([indexer canIndexCollection:collection], @"%@ should be supported", collection);
    }

    NSArray<NSString *> *unsupported = @[@"app.bsky.graph.follow", @"app.bsky.actor.profile", @"com.example.custom"];
    for (NSString *collection in unsupported) {
        XCTAssertFalse([indexer canIndexCollection:collection], @"%@ should not be supported", collection);
    }
}

- (void)testFeedIndexerValidatesPostsAndSubjects {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;

    BOOL ok = [indexer indexRecord:@{@"text": @"missing type"}
                               did:@"did:plc:feed"
                        collection:@"app.bsky.feed.post"
                               cid:@"cid1"
                             error:&error];
    XCTAssertFalse(ok);
    XCTAssertEqual(error.code, 1);

    error = nil;
    ok = [indexer indexRecord:@{@"$type": @"app.bsky.feed.post"}
                          did:@"did:plc:feed"
                   collection:@"app.bsky.feed.post"
                          cid:@"cid2"
                        error:&error];
    XCTAssertFalse(ok);
    XCTAssertEqual(error.code, 2);

    error = nil;
    ok = [indexer indexRecord:@{@"$type": @"app.bsky.feed.like"}
                          did:@"did:plc:feed"
                   collection:@"app.bsky.feed.like"
                          cid:@"cid3"
                        error:&error];
    XCTAssertFalse(ok);
    XCTAssertEqual(error.code, 3);

    error = nil;
    ok = [indexer indexRecord:@{@"$type": @"app.bsky.feed.post", @"text": @"hello"}
                          did:@"did:plc:feed"
                   collection:@"app.bsky.feed.post"
                          cid:@"cid4"
                        error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);

    error = nil;
    ok = [indexer indexRecord:@{@"$type": @"app.bsky.feed.post", @"embed": @{@"$type": @"app.bsky.embed.images"}}
                          did:@"did:plc:feed"
                   collection:@"app.bsky.feed.post"
                          cid:@"cid5"
                        error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);

    error = nil;
    ok = [indexer indexRecord:@{@"$type": @"app.bsky.feed.repost", @"subject": @{@"uri": @"at://did:plc:target/app.bsky.feed.post/abc"}}
                          did:@"did:plc:feed"
                   collection:@"app.bsky.feed.repost"
                          cid:@"cid6"
                        error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
}

- (void)testFeedIndexerRoutesLiveEvents {
    RoutingFeedIndexer *indexer = [[RoutingFeedIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    AppViewIngestEvent *event = [self ingestEventWithDid:@"did:plc:feed" ops:@[
        @{ @"action": @"create", @"path": @"app.bsky.feed.post/r1", @"cid": @"cid1", @"record": @{ @"$type": @"app.bsky.feed.post", @"text": @"hello" } },
        @{ @"action": @"update", @"path": @"app.bsky.feed.like/r2", @"cid": @"cid2", @"record": @{ @"$type": @"app.bsky.feed.like", @"subject": @{ @"uri": @"at://did:plc:target/app.bsky.feed.post/1" } } },
        @{ @"action": @"delete", @"path": @"app.bsky.feed.generator/r3" },
        @{ @"action": @"create", @"path": @"app.bsky.actor.profile/self", @"cid": @"cid4", @"record": @{ @"$type": @"app.bsky.actor.profile" } },
    ]];

    XCTAssertTrue([indexer handleIngestEvent:event error:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(indexer.indexCalls.count, 2u);
    XCTAssertEqual(indexer.deleteCalls.count, 1u);
    XCTAssertEqualObjects(indexer.deleteCalls.firstObject[@"rkey"], @"r3");
    XCTAssertEqualObjects(indexer.deleteCalls.firstObject[@"collection"], @"app.bsky.feed.generator");
}

- (void)testFeedIndexerProcessesPendingDeltas {
    AppViewFeedIndexer *indexer = [[AppViewFeedIndexer alloc] initWithDatabase:self.database];
    AppViewPendingDelta *delta = [[AppViewPendingDelta alloc]
        initWithDID:@"did:plc:feed"
                seq:10
          commitCID:@"cid1"
                rev:@"rev1"
        rawEnvelope:[NSData data]];

    NSError *error = nil;
    XCTAssertTrue([indexer processPendingDelta:delta error:&error]);
    XCTAssertNil(error);
    XCTAssertTrue([indexer deleteRecord:@"r1" did:@"did:plc:feed" collection:@"app.bsky.feed.post" error:&error]);
    XCTAssertNil(error);
}

#pragma mark - Graph indexer

- (void)testGraphIndexerCanIndexSupportedCollections {
    AppViewGraphIndexer *indexer = [[AppViewGraphIndexer alloc] initWithDatabase:self.database relevanceSet:nil];

    NSArray<NSString *> *supported = @[
        @"app.bsky.graph.follow",
        @"app.bsky.graph.block",
        @"app.bsky.graph.list",
        @"app.bsky.graph.listitem",
        @"app.bsky.graph.listblock",
        @"app.bsky.graph.starterpack",
    ];
    for (NSString *collection in supported) {
        XCTAssertTrue([indexer canIndexCollection:collection], @"%@ should be supported", collection);
    }

    XCTAssertFalse([indexer canIndexCollection:@"app.bsky.feed.post"]);
}

- (void)testGraphIndexerValidatesFollowsAndExpandsRelevance {
    AppViewGraphIndexer *indexer = [[AppViewGraphIndexer alloc] initWithDatabase:self.database relevanceSet:self.relevanceSet];
    NSError *error = nil;

    BOOL ok = [indexer indexRecord:@{@"$type": @"app.bsky.graph.follow"}
                               did:@"did:plc:follower"
                        collection:@"app.bsky.graph.follow"
                               cid:@"cid1"
                             error:&error];
    XCTAssertFalse(ok);
    XCTAssertEqual(error.code, 1);

    NSString *followerDID = @"did:plc:follower";
    NSString *targetDID = @"did:plc:target";
    [self.relevanceSet addDID:followerDID reason:AppViewRelevanceReasonSeed];
    [self waitUntilDID:followerDID becomesRelevant:YES];

    error = nil;
    ok = [indexer indexRecord:@{@"$type": @"app.bsky.graph.follow", @"subject": targetDID}
                          did:followerDID
                   collection:@"app.bsky.graph.follow"
                          cid:@"cid2"
                        error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
    [self waitUntilDID:targetDID becomesRelevant:YES];

    AppViewRelevanceMembership *membership = [self.database loadRelevanceMembershipForDID:targetDID error:nil];
    XCTAssertNotNil(membership);
    XCTAssertEqual(membership.reason, AppViewRelevanceReasonFollowOfSeed);
    XCTAssertNotNil(membership.expiresAt);
}

- (void)testGraphIndexerDoesNotExpandForIrrelevantFollower {
    AppViewGraphIndexer *indexer = [[AppViewGraphIndexer alloc] initWithDatabase:self.database relevanceSet:self.relevanceSet];
    NSError *error = nil;

    NSString *followerDID = @"did:plc:outsider";
    NSString *targetDID = @"did:plc:unexpanded";

    BOOL ok = [indexer indexRecord:@{@"$type": @"app.bsky.graph.follow", @"subject": targetDID}
                               did:followerDID
                        collection:@"app.bsky.graph.follow"
                               cid:@"cid1"
                             error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
    [self waitUntilDID:targetDID becomesRelevant:NO];
}

- (void)testGraphIndexerRoutesLiveEvents {
    RoutingGraphIndexer *indexer = [[RoutingGraphIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    AppViewIngestEvent *event = [self ingestEventWithDid:@"did:plc:graph" ops:@[
        @{ @"action": @"create", @"path": @"app.bsky.graph.follow/r1", @"cid": @"cid1", @"record": @{ @"$type": @"app.bsky.graph.follow", @"subject": @"did:plc:target" } },
        @{ @"action": @"update", @"path": @"app.bsky.graph.list/r2", @"cid": @"cid2", @"record": @{ @"$type": @"app.bsky.graph.list" } },
        @{ @"action": @"delete", @"path": @"app.bsky.graph.listitem/r3" },
        @{ @"action": @"create", @"path": @"app.bsky.actor.profile/self", @"record": @{ @"$type": @"app.bsky.actor.profile" } },
    ]];

    XCTAssertTrue([indexer handleIngestEvent:event error:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(indexer.indexCalls.count, 2u);
    XCTAssertEqual(indexer.deleteCalls.count, 1u);
    XCTAssertEqualObjects(indexer.deleteCalls.firstObject[@"rkey"], @"r3");
    XCTAssertEqualObjects(indexer.deleteCalls.firstObject[@"collection"], @"app.bsky.graph.listitem");
}

- (void)testGraphIndexerProcessesPendingDeltas {
    AppViewGraphIndexer *indexer = [[AppViewGraphIndexer alloc] initWithDatabase:self.database relevanceSet:nil];
    AppViewPendingDelta *delta = [[AppViewPendingDelta alloc]
        initWithDID:@"did:plc:graph"
                seq:10
          commitCID:@"cid1"
                rev:@"rev1"
        rawEnvelope:[NSData data]];

    NSError *error = nil;
    XCTAssertTrue([indexer processPendingDelta:delta error:&error]);
    XCTAssertNil(error);
    XCTAssertTrue([indexer deleteRecord:@"r1" did:@"did:plc:graph" collection:@"app.bsky.graph.follow" error:&error]);
    XCTAssertNil(error);
}

#pragma mark - Notification indexer

- (void)testNotificationIndexerCanIndexSupportedCollections {
    AppViewNotificationIndexer *indexer = [[AppViewNotificationIndexer alloc] initWithDatabase:self.database];

    NSArray<NSString *> *supported = @[
        @"app.bsky.feed.like",
        @"app.bsky.feed.repost",
        @"app.bsky.feed.post",
        @"app.bsky.graph.follow",
    ];
    for (NSString *collection in supported) {
        XCTAssertTrue([indexer canIndexCollection:collection], @"%@ should be supported", collection);
    }

    XCTAssertFalse([indexer canIndexCollection:@"app.bsky.feed.generator"]);
}

- (void)testNotificationIndexerReturnsYesForSupportedNotificationCollections {
    AppViewNotificationIndexer *indexer = [[AppViewNotificationIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;

    NSArray<NSDictionary *> *cases = @[
        @{ @"collection": @"app.bsky.feed.like", @"record": @{ @"$type": @"app.bsky.feed.like", @"subject": @{ @"uri": @"at://did:plc:target/app.bsky.feed.post/r1" } } },
        @{ @"collection": @"app.bsky.feed.repost", @"record": @{ @"$type": @"app.bsky.feed.repost", @"subject": @{ @"uri": @"at://did:plc:target/app.bsky.feed.post/r2" } } },
        @{ @"collection": @"app.bsky.feed.post", @"record": @{ @"$type": @"app.bsky.feed.post", @"reply": @{ @"parent": @{ @"uri": @"at://did:plc:target/app.bsky.feed.post/root" } }, @"facets": @[@{ @"features": @[@{ @"$type": @"app.bsky.richtext.facet#mention", @"did": @"did:plc:mentioned" }] }], @"embed": @{ @"$type": @"app.bsky.embed.record", @"record": @{ @"uri": @"at://did:plc:quoted/app.bsky.feed.post/q1" } } } },
        @{ @"collection": @"app.bsky.graph.follow", @"record": @{ @"$type": @"app.bsky.graph.follow", @"subject": @"did:plc:target" } },
    ];

    for (NSDictionary *item in cases) {
        BOOL ok = [indexer indexRecord:item[@"record"]
                                   did:@"did:plc:author"
                            collection:item[@"collection"]
                                   cid:@"cid1"
                                 error:&error];
        XCTAssertTrue(ok);
        XCTAssertNil(error);
    }
}

- (void)testNotificationIndexerRoutesLiveEvents {
    RoutingNotificationIndexer *indexer = [[RoutingNotificationIndexer alloc] initWithDatabase:self.database];
    NSError *error = nil;
    AppViewIngestEvent *event = [self ingestEventWithDid:@"did:plc:notifs" ops:@[
        @{ @"action": @"create", @"path": @"app.bsky.feed.post/r1", @"cid": @"cid1", @"record": @{ @"$type": @"app.bsky.feed.post", @"text": @"hello" } },
        @{ @"action": @"delete", @"path": @"app.bsky.feed.post/r2" },
        @{ @"action": @"create", @"path": @"app.bsky.actor.profile/self", @"record": @{ @"$type": @"app.bsky.actor.profile" } },
    ]];

    XCTAssertTrue([indexer handleIngestEvent:event error:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(indexer.indexCalls.count, 1u);
    XCTAssertEqual(indexer.deleteCalls.count, 0u);
}

#pragma mark - RecordLifecycleHandler notifications

- (void)testRecordLifecycleHandlerCreatesLikeRepostAndFollowNotifications {
    NSUInteger startingCount = self.notificationService.createCalls.count;

    NSArray<NSDictionary *> *cases = @[
        @{ @"collection": @"app.bsky.feed.like",
           @"record": @{ @"subject": @{ @"uri": @"at://did:plc:liked/app.bsky.feed.post/post1" } },
           @"expectedReason": @"like",
           @"expectedActor": @"did:plc:liked",
           @"expectedReasonSubject": @"at://did:plc:liked/app.bsky.feed.post/post1" },
        @{ @"collection": @"app.bsky.feed.repost",
           @"record": @{ @"subject": @{ @"uri": @"at://did:plc:reposted/app.bsky.feed.post/post2" } },
           @"expectedReason": @"repost",
           @"expectedActor": @"did:plc:reposted",
           @"expectedReasonSubject": @"at://did:plc:reposted/app.bsky.feed.post/post2" },
        @{ @"collection": @"app.bsky.graph.follow",
           @"record": @{ @"subject": @"did:plc:followed" },
           @"expectedReason": @"follow",
           @"expectedActor": @"did:plc:followed",
           @"expectedReasonSubject": [NSNull null] },
    ];

    for (NSDictionary *item in cases) {
        NSString *collection = item[@"collection"];
        NSDictionary *record = item[@"record"];
        [self postRecordChangeWithDid:@"did:plc:author"
                           collection:collection
                                rkey:@"self"
                               action:@"create"
                                  cid:@"cid-create"
                               record:record];
    }

    XCTAssertEqual(self.notificationService.createCalls.count, startingCount + cases.count);

    for (NSUInteger i = 0; i < cases.count; i++) {
        NSDictionary *expected = cases[i];
        NSDictionary *call = self.notificationService.createCalls[startingCount + i];
        NSString *expectedSubjectURI = [NSString stringWithFormat:@"at://%@/%@/%@",
                                        @"did:plc:author",
                                        expected[@"collection"],
                                        @"self"];
        XCTAssertEqualObjects(call[@"actorDID"], expected[@"expectedActor"]);
        XCTAssertEqualObjects(call[@"authorDID"], @"did:plc:author");
        XCTAssertEqualObjects(call[@"reason"], expected[@"expectedReason"]);
        if ([expected[@"expectedReasonSubject"] isKindOfClass:[NSNull class]]) {
            XCTAssertEqualObjects(call[@"reasonSubject"], [NSNull null]);
        } else {
            XCTAssertEqualObjects(call[@"reasonSubject"], expected[@"expectedReasonSubject"]);
        }
        XCTAssertEqualObjects(call[@"subjectURI"], expectedSubjectURI);
        XCTAssertEqualObjects(call[@"subjectCID"], @"cid-create");
    }
}

- (void)testRecordLifecycleHandlerCreatesReplyMentionAndQuoteNotificationsFromPost {
    NSUInteger startingCount = self.notificationService.createCalls.count;
    NSDictionary *record = @{ 
        @"text": @"reply, mention, and quote",
        @"reply": @{ @"parent": @{ @"uri": @"at://did:plc:parent/app.bsky.feed.post/root" } },
        @"facets": @[@{ @"features": @[@{ @"$type": @"app.bsky.richtext.facet#mention", @"did": @"did:plc:mentioned" }] }],
        @"embed": @{ @"$type": @"app.bsky.embed.record", @"record": @{ @"uri": @"at://did:plc:quoted/app.bsky.feed.post/q1" } },
        @"$type": @"app.bsky.feed.post",
    };

    [self postRecordChangeWithDid:@"did:plc:author"
                       collection:@"app.bsky.feed.post"
                            rkey:@"post1"
                           action:@"create"
                              cid:@"cid-post"
                           record:record];

    XCTAssertEqual(self.notificationService.createCalls.count, startingCount + 3u);

    NSArray<NSDictionary *> *calls = [self.notificationService.createCalls subarrayWithRange:NSMakeRange(startingCount, 3)];
    XCTAssertEqualObjects(calls[0][@"reason"], @"reply");
    XCTAssertEqualObjects(calls[0][@"actorDID"], @"did:plc:parent");
    XCTAssertEqualObjects(calls[0][@"reasonSubject"], @"at://did:plc:parent/app.bsky.feed.post/root");

    XCTAssertEqualObjects(calls[1][@"reason"], @"mention");
    XCTAssertEqualObjects(calls[1][@"actorDID"], @"did:plc:mentioned");
    XCTAssertEqualObjects(calls[1][@"reasonSubject"], [NSNull null]);

    XCTAssertEqualObjects(calls[2][@"reason"], @"quote");
    XCTAssertEqualObjects(calls[2][@"actorDID"], @"did:plc:quoted");
    XCTAssertEqualObjects(calls[2][@"reasonSubject"], @"at://did:plc:quoted/app.bsky.feed.post/q1");

    for (NSDictionary *call in calls) {
        XCTAssertEqualObjects(call[@"authorDID"], @"did:plc:author");
        XCTAssertEqualObjects(call[@"subjectURI"], @"at://did:plc:author/app.bsky.feed.post/post1");
        XCTAssertEqualObjects(call[@"subjectCID"], @"cid-post");
    }
}

- (void)testRecordLifecycleHandlerIndexesAndUnindexesServiceCollections {
    NSUInteger startingNotificationDeletes = self.notificationService.deleteCalls.count;
    NSUInteger startingBookmarkIndexes = self.bookmarkService.indexCalls.count;
    NSUInteger startingBookmarkDeletes = self.bookmarkService.deleteCalls.count;
    NSUInteger startingGraphCalls = self.graphService.calls.count;
    NSUInteger startingFeedCalls = self.feedService.calls.count;

    NSArray<NSDictionary *> *createCases = @[
        @{ @"collection": @"app.bsky.bookmark.bookmark",
           @"rkey": @"bookmark1",
           @"record": @{ @"$type": @"app.bsky.bookmark.bookmark" },
           @"cid": @"cid-bookmark" },
        @{ @"collection": @"app.bsky.graph.starterpack",
           @"rkey": @"starter1",
           @"record": @{ @"$type": @"app.bsky.graph.starterpack" },
           @"cid": @"cid-starter" },
        @{ @"collection": @"app.bsky.feed.threadgate",
           @"rkey": @"threadgate1",
           @"record": @{ @"$type": @"app.bsky.feed.threadgate" },
           @"cid": @"cid-thread" },
        @{ @"collection": @"app.bsky.feed.postgate",
           @"rkey": @"postgate1",
           @"record": @{ @"$type": @"app.bsky.feed.postgate" },
           @"cid": @"cid-postgate" },
        @{ @"collection": @"app.bsky.feed.generator",
           @"rkey": @"generator1",
           @"record": @{ @"$type": @"app.bsky.feed.generator" },
           @"cid": @"cid-generator" },
        @{ @"collection": @"app.bsky.graph.list",
           @"rkey": @"list1",
           @"record": @{ @"$type": @"app.bsky.graph.list" },
           @"cid": @"cid-list" },
        @{ @"collection": @"app.bsky.graph.listitem",
           @"rkey": @"listitem1",
           @"record": @{ @"$type": @"app.bsky.graph.listitem" },
           @"cid": @"cid-listitem" },
    ];

    for (NSDictionary *item in createCases) {
        [self postRecordChangeWithDid:@"did:plc:author"
                           collection:item[@"collection"]
                                rkey:item[@"rkey"]
                               action:@"create"
                                  cid:item[@"cid"]
                               record:item[@"record"]];
    }

    XCTAssertEqual(self.notificationService.deleteCalls.count, startingNotificationDeletes);
    XCTAssertEqual(self.bookmarkService.indexCalls.count, startingBookmarkIndexes + 1u);
    XCTAssertEqual(self.bookmarkService.deleteCalls.count, startingBookmarkDeletes);
    XCTAssertEqual(self.graphService.calls.count, startingGraphCalls + 3u);
    XCTAssertEqual(self.feedService.calls.count, startingFeedCalls + 3u);

    NSDictionary *bookmarkCall = self.bookmarkService.indexCalls.lastObject;
    XCTAssertEqualObjects(bookmarkCall[@"uri"], @"at://did:plc:author/app.bsky.bookmark.bookmark/bookmark1");
    XCTAssertEqualObjects(bookmarkCall[@"cid"], @"cid-bookmark");

    NSArray<NSDictionary *> *graphCalls = [self.graphService.calls subarrayWithRange:NSMakeRange(startingGraphCalls, 3)];
    XCTAssertEqualObjects(graphCalls[0][@"selector"], @"indexStarterPack:did:rkey:cid:error:");
    XCTAssertEqualObjects(graphCalls[1][@"selector"], @"indexList:did:uri:cid:error:");
    XCTAssertEqualObjects(graphCalls[2][@"selector"], @"indexListitem:did:uri:cid:error:");

    NSArray<NSDictionary *> *feedCalls = [self.feedService.calls subarrayWithRange:NSMakeRange(startingFeedCalls, 3)];
    XCTAssertEqualObjects(feedCalls[0][@"selector"], @"indexThreadgate:did:uri:cid:error:");
    XCTAssertEqualObjects(feedCalls[1][@"selector"], @"indexPostgate:did:uri:cid:error:");
    XCTAssertEqualObjects(feedCalls[2][@"selector"], @"indexGenerator:did:uri:cid:error:");

    NSArray<NSDictionary *> *deleteCases = @[
        @{ @"collection": @"app.bsky.bookmark.bookmark",
           @"rkey": @"bookmark1",
           @"expectedSelector": @"unindexBookmarkWithURI:did:error:",
           @"service": @"bookmark" },
        @{ @"collection": @"app.bsky.graph.starterpack",
           @"rkey": @"starter1",
           @"expectedSelector": @"unindexStarterPackWithRKey:did:error:",
           @"service": @"graph" },
        @{ @"collection": @"app.bsky.feed.threadgate",
           @"rkey": @"threadgate1",
           @"expectedSelector": @"unindexThreadgateWithURI:error:",
           @"service": @"feed" },
        @{ @"collection": @"app.bsky.feed.postgate",
           @"rkey": @"postgate1",
           @"expectedSelector": @"unindexPostgateWithURI:error:",
           @"service": @"feed" },
        @{ @"collection": @"app.bsky.feed.generator",
           @"rkey": @"generator1",
           @"expectedSelector": @"unindexGeneratorWithURI:error:",
           @"service": @"feed" },
        @{ @"collection": @"app.bsky.graph.list",
           @"rkey": @"list1",
           @"expectedSelector": @"unindexListWithURI:error:",
           @"service": @"graph" },
        @{ @"collection": @"app.bsky.graph.listitem",
           @"rkey": @"listitem1",
           @"expectedSelector": @"unindexListitemWithURI:error:",
           @"service": @"graph" },
    ];

    for (NSDictionary *item in deleteCases) {
        [self postRecordChangeWithDid:@"did:plc:author"
                           collection:item[@"collection"]
                                rkey:item[@"rkey"]
                               action:@"delete"
                                  cid:nil
                               record:nil];
    }

    XCTAssertEqual(self.notificationService.deleteCalls.count, startingNotificationDeletes + deleteCases.count);
    XCTAssertEqual(self.bookmarkService.deleteCalls.count, startingBookmarkDeletes + 1u);

    NSDictionary *bookmarkDelete = self.bookmarkService.deleteCalls.lastObject;
    XCTAssertEqualObjects(bookmarkDelete[@"uri"], @"at://did:plc:author/app.bsky.bookmark.bookmark/bookmark1");

    NSDictionary *lastGraphCall = self.graphService.calls.lastObject;
    XCTAssertEqualObjects(lastGraphCall[@"selector"], @"unindexListitemWithURI:error:");
    XCTAssertEqualObjects(lastGraphCall[@"uri"], @"at://did:plc:author/app.bsky.graph.listitem/listitem1");

    NSDictionary *lastFeedCall = self.feedService.calls.lastObject;
    XCTAssertEqualObjects(lastFeedCall[@"selector"], @"unindexGeneratorWithURI:error:");
    XCTAssertEqualObjects(lastFeedCall[@"uri"], @"at://did:plc:author/app.bsky.feed.generator/generator1");
}

- (void)testRecordLifecycleHandlerIgnoresIncompleteAndSelfReferentialChanges {
    NSUInteger startingCreateCalls = self.notificationService.createCalls.count;
    NSUInteger startingDeleteCalls = self.notificationService.deleteCalls.count;

    [self postRecordChangeWithDid:nil
                       collection:@"app.bsky.feed.post"
                            rkey:@"r1"
                           action:@"create"
                              cid:@"cid1"
                           record:@{@"$type": @"app.bsky.feed.post", @"text": @"ignored"}];
    [self postRecordChangeWithDid:@"did:plc:author"
                       collection:nil
                            rkey:@"r2"
                           action:@"create"
                              cid:@"cid2"
                           record:@{@"$type": @"app.bsky.feed.post", @"text": @"ignored"}];
    [self postRecordChangeWithDid:@"did:plc:author"
                       collection:@"app.bsky.feed.like"
                            rkey:nil
                           action:nil
                              cid:@"cid3"
                           record:@{@"$type": @"app.bsky.feed.like", @"subject": @{ @"uri": @"at://did:plc:author/app.bsky.feed.post/self" }}];

    NSDictionary *selfReferentialPost = @{ 
        @"$type": @"app.bsky.feed.post",
        @"reply": @{ @"parent": @{ @"uri": @"at://did:plc:author/app.bsky.feed.post/root" } },
        @"facets": @[@{ @"features": @[@{ @"$type": @"app.bsky.richtext.facet#mention", @"did": @"did:plc:author" }] }],
        @"embed": @{ @"$type": @"app.bsky.embed.record", @"record": @{ @"uri": @"at://did:plc:author/app.bsky.feed.post/quote" } },
    };
    [self postRecordChangeWithDid:@"did:plc:author"
                       collection:@"app.bsky.feed.post"
                            rkey:@"self"
                           action:@"create"
                              cid:@"cid-self"
                           record:selfReferentialPost];

    XCTAssertEqual(self.notificationService.createCalls.count, startingCreateCalls);
    XCTAssertEqual(self.notificationService.deleteCalls.count, startingDeleteCalls);
}

- (void)testRecordLifecycleHandlerStopObservingPreventsFurtherCallbacks {
    [self.recordLifecycleHandler stopObserving];

    NSUInteger startingCreateCalls = self.notificationService.createCalls.count;
    [self postRecordChangeWithDid:@"did:plc:author"
                       collection:@"app.bsky.feed.like"
                            rkey:@"like1"
                           action:@"create"
                              cid:@"cid1"
                           record:@{@"$type": @"app.bsky.feed.like", @"subject": @{ @"uri": @"at://did:plc:target/app.bsky.feed.post/post1" }}];

    XCTAssertEqual(self.notificationService.createCalls.count, startingCreateCalls);
}

@end
