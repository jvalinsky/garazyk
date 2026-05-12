// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Network/XrpcHandler.h"
#import "App/PDSController.h"
#import "Repository/RepoCommit.h"
#import "Sync/WebSocket/WebSocketConnection.h"
#import "Sync/WebSocket/WebSocketServer.h"
#import "Sync/Relay/EventFormatter.h"
#import "Database/Service/ServiceDatabases.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Network/HttpRequest.h"
#import <sqlite3.h>

@interface MockWebSocketConnection : WebSocketConnection
@property (nonatomic, strong) NSMutableArray *sentMessages;
@property (nonatomic, copy) NSDictionary *mockQueryParams;
@property (nonatomic, assign) BOOL didClose;
@property (nonatomic, assign) NSInteger closedCode;
@property (nonatomic, copy) NSString *closedReason;
@property (nonatomic, assign) NSUInteger simulatedPendingSendCount;
@property (nonatomic, assign) NSUInteger simulatedPendingSendBytes;
@end

@implementation MockWebSocketConnection
- (instancetype)init {
    // Skip super init if it requires args we don't have, or just use performSelector
    // WebSocketConnection init is likely just NSObject init + property setup
    self = [super init];
    if (self) {
        _sentMessages = [NSMutableArray array];
    }
    return self;
}
- (void)sendMessage:(NSData *)message {
    [_sentMessages addObject:message];
}
- (NSDictionary *)queryParams {
    return _mockQueryParams;
}
- (void)close {
    self.didClose = YES;
}
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason {
    self.didClose = YES;
    self.closedCode = code;
    self.closedReason = reason ?: @"";
}
- (NSUInteger)pendingSendCount {
    return self.simulatedPendingSendCount;
}
- (NSUInteger)pendingSendBytes {
    return self.simulatedPendingSendBytes;
}
@end

@interface SubscribeReposHandler (TestAccess)
- (void)sendInitialRepositoryStateToConnection:(WebSocketConnection *)connection cursor:(nullable NSString *)cursor;
@property (nonatomic, assign) NSUInteger maxReplayEventsPerConnection;
@property (nonatomic, assign) NSUInteger maxPendingSendsPerConnection;
@property (nonatomic, assign) NSUInteger maxPendingBytesPerConnection;
@end

@interface SubscribeReposHandlerTests : XCTestCase
@property (nonatomic, strong) SubscribeReposHandler *handler;
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, copy) NSString *tempDir;
@end

@implementation SubscribeReposHandlerTests

- (void)setUp {
    [super setUp];
    
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    self.controller = [[PDSController alloc] initWithDirectory:self.tempDir serviceMaxSize:10 userDatabaseSize:10];
    
    // Ensure DBs are initialized
    NSError *error = nil;
    if (![self.controller.serviceDatabases serviceDatabaseWithError:&error]) {
        XCTFail(@"Failed to init DB: %@", error);
    }

    // This suite installs its own handler against the controller databases.
    // Stop the application-owned handler so account/record notifications do not
    // double-write the same sequencer rows during tests.
    [self.controller.subscribeReposHandler stop];
    
    self.handler = [[SubscribeReposHandler alloc]
        initWithServiceDatabases:self.controller.serviceDatabases
                userDatabasePool:self.controller.userDatabasePool];
    [self.handler startObservingNotifications];
}

- (void)tearDown {
    [self waitForHandlerIdle];
    [self.handler stop];
    [self.controller stopServer];
    [XrpcDispatcher resetSharedDispatcher];
    self.handler = nil;
    self.controller = nil;
    @autoreleasepool { }  // Drain to ensure deallocs before file deletion
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

- (void)waitForHandlerIdle {
    [self waitForHandler:self.handler idleWithTimeout:1.0];
}

- (void)waitForHandler:(SubscribeReposHandler *)handler idleWithTimeout:(NSTimeInterval)timeout {
    if (!handler) {
        return;
    }
    XCTAssertTrue([handler waitForIdleWithTimeout:timeout], @"Timed out waiting for subscribeRepos queues to drain");
}

- (void)testBroadcastCommitWithOpsValidatesMaxSeqIsGreater {
    RepoCommit *commit = [RepoCommit createCommitWithDid:@"did:plc:test" 
                                                   data:[CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"] 
                                                    rev:@"3l66k7pp33p" 
                                                   prev:nil];
    
    NSArray *ops = @[
        @{
            @"action": @"create",
            @"path": @"app.bsky.feed.post/3jqfcqzm3fo2j",
            @"cid": @"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"
        }
    ];
    
    NSArray *blobs = @[
        [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"] ?: [[CID alloc] init]
    ];
    
    // This is a minimal test to ensure we can pass ops and blobs
    // and that they are handled without crashing.
    XCTAssertNoThrow([self.handler broadcastRepositoryCommit:commit 
                                                     forRepo:@"did:plc:test" 
                                                         ops:ops 
                                                       blobs:blobs], 
                      @"Should handle broadcast with ops and blobs");
                      
    [self waitForHandlerIdle];
    NSError *err = nil;
    int64_t maxSeq = [self.controller.serviceDatabases getMaxEventSequence:&err];
    XCTAssertGreaterThan(maxSeq, 0);
}

#ifndef GNUSTEP
- (void)testBackpressureEnforcement {
    RepoCommit *commit = [RepoCommit createCommitWithDid:@"did:plc:test" 
                                                   data:[CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"] 
                                                    rev:@"3l66k7pp33p" 
                                                   prev:nil];
    
    NSArray *ops = @[
        @{
            @"action": @"create",
            @"path": @"app.bsky.feed.post/3jqfcqzm3fo2j",
            @"cid": @"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"
        }
    ];
    
    MockWebSocketConnection *testConn = [[MockWebSocketConnection alloc] init];
    // Use didAcceptConnection directly to bypass connection wrapping
    [(id)self.handler webSocketServer:nil didAcceptConnection:testConn];
    
    // Simulate backpressure by increasing count
    testConn.simulatedPendingSendCount = self.handler.maxPendingSendsPerConnection + 1;
    
    [self.handler broadcastRepositoryCommit:commit forRepo:@"did:plc:test" ops:ops blobs:@[]];
    [self waitForHandlerIdle];
    
    XCTAssertTrue(testConn.didClose, @"Connection should be closed due to count backpressure");
    XCTAssertEqual(testConn.closedCode, 1008);
    
    // Reset and test bytes backpressure
    MockWebSocketConnection *testConn2 = [[MockWebSocketConnection alloc] init];
    [(id)self.handler webSocketServer:nil didAcceptConnection:testConn2];
    
    testConn2.simulatedPendingSendCount = 0;
    testConn2.simulatedPendingSendBytes = self.handler.maxPendingBytesPerConnection + 1;
    
    [self.handler broadcastRepositoryCommit:commit forRepo:@"did:plc:test" ops:ops blobs:@[]];
    [self waitForHandlerIdle];
    
    XCTAssertTrue(testConn2.didClose, @"Connection should be closed due to bytes backpressure");
    XCTAssertEqual(testConn2.closedCode, 1008);
}
#endif

#ifndef GNUSTEP
- (void)testBroadcastPersistsEvent {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    
    [self.handler broadcastIdentityChange:@"did:plc:test_persist" handle:@"test.bsky.social"];
    [self waitForHandlerIdle];

    NSError *error = nil;
    int64_t maxSeq = [self.controller.serviceDatabases getMaxEventSequence:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThan(maxSeq, 0);

    NSArray *events = [self.controller.serviceDatabases getEventsSince:0 limit:1 error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(events.count, 1);

    NSDictionary *event = events[0];
    XCTAssertEqualObjects(event[@"type"], @"identity");
    XCTAssertEqualObjects(event[@"seq"], @(maxSeq));

    NSData *data = event[@"data"];
    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *payload = [formatter decodeEventFromData:data op:&op msgType:&msgType error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(payload);
    XCTAssertEqual(op, 1); // kXRPCStreamOpMessage
    XCTAssertEqualObjects(msgType, @"#identity");
    XCTAssertEqualObjects(payload[@"did"], @"did:plc:test_persist");
    XCTAssertEqualObjects(payload[@"handle"], @"test.bsky.social");
}
#endif

#ifndef GNUSTEP
- (void)testReplayWithCursor {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    
    // 1. Create some persisted events (identity events are persisted, info events are not)
    [self.handler broadcastIdentityChange:@"did:plc:replay1" handle:@"replay1.bsky.social"];
    [self.handler broadcastIdentityChange:@"did:plc:replay2" handle:@"replay2.bsky.social"];
    [self.handler broadcastIdentityChange:@"did:plc:replay3" handle:@"replay3.bsky.social"];
    [self waitForHandlerIdle];
    
    // 2. Simulate connection with cursor=1 (should get events 2 and 3)
    MockWebSocketConnection *conn = [[MockWebSocketConnection alloc] init];
    conn.mockQueryParams = @{@"cursor": @"1"};
    [self.handler sendInitialRepositoryStateToConnection:conn cursor:@"1"];
    [self waitForHandlerIdle];
    
    // Verify received messages using proper stream decoder
    XCTAssertEqual(conn.sentMessages.count, 2, "Should receive 2 events (identity2, identity3)");
    
    if (conn.sentMessages.count >= 2) {
        NSInteger op1 = 0, op2 = 0;
        NSString *type1 = nil;
        NSString *type2 = nil;
        NSError *error = nil;
        
        NSDictionary *msg1 = [formatter decodeEventFromData:conn.sentMessages[0] op:&op1 msgType:&type1 error:&error];
        NSDictionary *msg2 = [formatter decodeEventFromData:conn.sentMessages[1] op:&op2 msgType:&type2 error:&error];
        
        XCTAssertNil(error);
        XCTAssertNotNil(msg1);
        XCTAssertNotNil(msg2);
        XCTAssertEqual(op1, 1); // kXRPCStreamOpMessage
        XCTAssertEqual(op2, 1);
        XCTAssertEqualObjects(type1, @"#identity");
        XCTAssertEqualObjects(type2, @"#identity");
        XCTAssertEqualObjects(msg1[@"did"], @"did:plc:replay2");
        XCTAssertEqualObjects(msg2[@"did"], @"did:plc:replay3");
    }
}
#endif

#ifndef GNUSTEP
- (void)testReplayWithFutureCursorSendsOutdatedCursorInfo {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    // Seed a persisted event so the session has a non-zero sequence
    [self.handler broadcastIdentityChange:@"did:plc:future_cursor_test" handle:@"future.bsky.social"];

    [self waitForHandlerIdle];

    MockWebSocketConnection *conn = [[MockWebSocketConnection alloc] init];
    [self.handler sendInitialRepositoryStateToConnection:conn cursor:@"999999"];

    [self waitForHandlerIdle];

    XCTAssertFalse(conn.didClose, @"Future cursor should NOT close connection; treated as outdated cursor");
    // First message should be an OutdatedCursor info event (op=1, not error op=-1)
    NSInteger op = 0;
    NSString *msgType = nil;
    NSError *decodeError = nil;
    NSDictionary *payload = [formatter decodeEventFromData:conn.sentMessages.firstObject
                                                        op:&op
                                                   msgType:&msgType
                                                     error:&decodeError];
    XCTAssertNil(decodeError);
    XCTAssertEqual(op, 1, @"Info events use op=1");
    XCTAssertEqualObjects(msgType, @"#info");
    XCTAssertEqualObjects(payload[@"name"], @"OutdatedCursor");
}
#endif

#ifndef GNUSTEP
- (void)testUpdateCommitIncludesPreviousRecordCIDInRepoOp {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    NSError *error = nil;

    NSDictionary *account = [self.controller createAccountForEmail:@"prev-op@test.com"
                                                          password:@"password"
                                                            handle:@"prev-op.test"
                                                               did:nil
                                                             error:&error];
    XCTAssertNotNil(account);
    XCTAssertNil(error);
    NSString *did = account[@"did"];
    XCTAssertNotNil(did);

    NSDictionary *recordV1 = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"v1",
        @"createdAt": @"2024-01-01T00:00:00Z"
    };
    BOOL putV1 = [self.controller putRecord:@"app.bsky.feed.post"
                                       rkey:@"prev-op-test"
                                      value:recordV1
                                     forDid:did
                             validationMode:PDSValidationModeOff
                                      error:&error];
    XCTAssertTrue(putV1);
    XCTAssertNil(error);
    [self waitForHandlerIdle];

    NSArray<NSDictionary *> *eventsAfterV1 = [self.controller.serviceDatabases getEventsSince:0 limit:50 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(eventsAfterV1);
    NSDictionary *firstPayload = nil;
    for (NSDictionary *event in [eventsAfterV1 reverseObjectEnumerator]) {
        NSInteger firstOpCode = 0;
        NSString *firstMsgType = nil;
        NSDictionary *decoded = [formatter decodeEventFromData:event[@"data"]
                                                           op:&firstOpCode
                                                      msgType:&firstMsgType
                                                        error:&error];
        XCTAssertNil(error);
        if (firstOpCode == 1 && [firstMsgType isEqualToString:@"#commit"]) {
            firstPayload = decoded;
            break;
        }
    }
    XCTAssertNotNil(firstPayload);
    NSArray *firstOps = firstPayload[@"ops"];
    XCTAssertEqual(firstOps.count, 1U);
    NSDictionary *firstRepoOp = firstOps.firstObject;
    XCTAssertEqualObjects(firstRepoOp[@"action"], @"create");
    CID *firstCID = [firstRepoOp[@"cid"] isKindOfClass:[CID class]] ? firstRepoOp[@"cid"] : nil;
    XCTAssertNotNil(firstCID);

    NSDictionary *recordV2 = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"v2",
        @"createdAt": @"2024-01-01T00:00:01Z"
    };
    BOOL putV2 = [self.controller putRecord:@"app.bsky.feed.post"
                                       rkey:@"prev-op-test"
                                      value:recordV2
                                     forDid:did
                             validationMode:PDSValidationModeOff
                                      error:&error];
    XCTAssertTrue(putV2);
    XCTAssertNil(error);
    [self waitForHandlerIdle];

    NSArray<NSDictionary *> *allEvents = [self.controller.serviceDatabases getEventsSince:0 limit:100 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(allEvents);
    XCTAssertGreaterThanOrEqual(allEvents.count, 2U);

    NSDictionary *latestPayload = nil;
    for (NSDictionary *event in [allEvents reverseObjectEnumerator]) {
        NSInteger latestOpCode = 0;
        NSString *latestMsgType = nil;
        NSDictionary *decoded = [formatter decodeEventFromData:event[@"data"]
                                                            op:&latestOpCode
                                                       msgType:&latestMsgType
                                                         error:&error];
        XCTAssertNil(error);
        if (latestOpCode == 1 && [latestMsgType isEqualToString:@"#commit"]) {
            latestPayload = decoded;
            break;
        }
    }
    XCTAssertNotNil(latestPayload);

    NSArray *latestOps = latestPayload[@"ops"];
    XCTAssertEqual(latestOps.count, 1U);
    NSDictionary *latestRepoOp = latestOps.firstObject;
    XCTAssertEqualObjects(latestRepoOp[@"action"], @"update");

    CID *prevCID = [latestRepoOp[@"prev"] isKindOfClass:[CID class]] ? latestRepoOp[@"prev"] : nil;
    XCTAssertNotNil(prevCID);
    XCTAssertEqualObjects(prevCID.stringValue, firstCID.stringValue);
}
#endif

#ifndef GNUSTEP
- (void)testReplayWithLargeBacklogSendsOutdatedCursorInfoAndContinues {
    self.handler.maxReplayEventsPerConnection = 1;
    EventFormatter *formatter = [[EventFormatter alloc] init];

    // Create persisted events (identity events are persisted, info events are ephemeral)
    [self.handler broadcastIdentityChange:@"did:plc:backlog1" handle:@"backlog1.bsky.social"];
    [self.handler broadcastIdentityChange:@"did:plc:backlog2" handle:@"backlog2.bsky.social"];
    [self.handler broadcastIdentityChange:@"did:plc:backlog3" handle:@"backlog3.bsky.social"];
    [self waitForHandlerIdle];

    // Connect with cursor=1 — the backlog (seq 3 - seq 1 = 2) exceeds maxReplayEventsPerConnection (1)
    MockWebSocketConnection *conn = [[MockWebSocketConnection alloc] init];
    [self.handler sendInitialRepositoryStateToConnection:conn cursor:@"1"];
    [self waitForHandlerIdle];

    XCTAssertFalse(conn.didClose);
    // Should receive: OutdatedCursor info + the latest event (replay limited to 1)
    XCTAssertEqual(conn.sentMessages.count, 2U);

    NSInteger infoOp = 0;
    NSString *infoType = nil;
    NSError *infoDecodeError = nil;
    NSDictionary *infoPayload = [formatter decodeEventFromData:conn.sentMessages[0]
                                                            op:&infoOp
                                                       msgType:&infoType
                                                         error:&infoDecodeError];
    XCTAssertNil(infoDecodeError);
    XCTAssertEqual(infoOp, 1);
    XCTAssertEqualObjects(infoType, @"#info");
    XCTAssertEqualObjects(infoPayload[@"name"], @"OutdatedCursor");

    NSInteger eventOp = 0;
    NSString *eventType = nil;
    NSError *eventDecodeError = nil;
    NSDictionary *eventPayload = [formatter decodeEventFromData:conn.sentMessages[1]
                                                             op:&eventOp
                                                        msgType:&eventType
                                                          error:&eventDecodeError];
    XCTAssertNil(eventDecodeError);
    XCTAssertEqual(eventOp, 1);
    XCTAssertEqualObjects(eventType, @"#identity");
    XCTAssertEqualObjects(eventPayload[@"did"], @"did:plc:backlog3");
}
#endif

#ifndef GNUSTEP
- (void)testBroadcastDetachesConnectionWhenPendingQueueTooLarge {
    self.handler.maxPendingSendsPerConnection = 0;
    EventFormatter *formatter = [[EventFormatter alloc] init];

    MockWebSocketConnection *conn = [[MockWebSocketConnection alloc] init];
    conn.simulatedPendingSendCount = 1;
    NSMutableSet *attached = [self.handler valueForKey:@"attachedConnections"];
    [attached addObject:conn];

    [self.handler broadcastInfo:@"backpressure" message:@"test"];
    [self waitForHandlerIdle];

    XCTAssertTrue(conn.didClose);
    XCTAssertEqual(conn.sentMessages.count, 1U);
    NSInteger op = 0;
    NSString *msgType = nil;
    NSError *decodeError = nil;
    NSDictionary *payload = [formatter decodeEventFromData:conn.sentMessages.firstObject
                                                        op:&op
                                                   msgType:&msgType
                                                     error:&decodeError];
    XCTAssertNil(decodeError);
    XCTAssertEqual(op, -1);
    XCTAssertEqualObjects(msgType, @"#error");
    XCTAssertEqualObjects(payload[@"error"], @"ConsumerTooSlow");
}
#endif

- (void)testBroadcastIdentityChangePersistsEvent {
    XCTAssertNoThrow([self.handler broadcastIdentityChange:@"did:plc:test" handle:@"test.bsky.social"],
                     @"Should handle identity broadcast with handle");
    XCTAssertNoThrow([self.handler broadcastIdentityChange:@"did:plc:test2" handle:nil],
                     @"Should handle identity broadcast without handle");
    [self waitForHandlerIdle];
    NSError *err = nil;
    int64_t maxSeq = [self.controller.serviceDatabases getMaxEventSequence:&err];
    XCTAssertGreaterThan(maxSeq, 0);
}

- (void)testBroadcastAccountTakedownValidatesMaxSeqIsGreater {
    XCTAssertNoThrow([self.handler broadcastAccountTakedown:@"did:plc:malicious"],
                     @"Should handle account takedown broadcast");
    [self waitForHandlerIdle];
    NSError *err = nil;
    int64_t maxSeq = [self.controller.serviceDatabases getMaxEventSequence:&err];
    XCTAssertGreaterThan(maxSeq, 0);
}

- (void)testBroadcastInfoEventDoesNotConsumeSequence {
    // Per ATProto spec: "it is common to have an #info message type that is not persisted"
    // Info events should NOT consume a sequence number and should NOT be persisted.
    int64_t maxSeqBefore = [self.controller.serviceDatabases getMaxEventSequence:nil];
    
    [self.handler broadcastInfo:@"OutdatedCursor" message:@"Requested sequence too far back"];
    [self waitForHandlerIdle];
    
    int64_t maxSeqAfter = [self.controller.serviceDatabases getMaxEventSequence:nil];
    
    // Info events should NOT increment the max sequence
    XCTAssertEqual(maxSeqAfter, maxSeqBefore,
                   @"Info events should not consume a sequence number or be persisted");
}

#ifndef GNUSTEP
- (void)testReplayWithPrunedEventsHandlesGap {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    
    // 1. Broadcast two persisted events (Seq 1, 2)
    [self.handler broadcastIdentityChange:@"did:plc:prune1" handle:@"prune1.bsky.social"];
    [self.handler broadcastIdentityChange:@"did:plc:prune2" handle:@"prune2.bsky.social"];
    [self waitForHandlerIdle];
    
    // 2. Backdate events 1 & 2 in DB to allow pruning
    PDSDatabasePool *pool = self.controller.serviceDatabases.sequencerPool;
    [pool transactWithDid:@"__service__" block:^(id transactor, NSError **err) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSTimeInterval oldTime = [[NSDate dateWithTimeIntervalSinceNow:-7200] timeIntervalSince1970];
        NSString *sql = [NSString stringWithFormat:@"UPDATE events SET created_at = %f WHERE seq <= 2", oldTime];
        sqlite3_exec((sqlite3 *)[store.database internalSQLiteHandle], sql.UTF8String, NULL, NULL, NULL);
    } error:nil];
    
    // 3. Prune events older than 1 hour ago
    NSError *error = nil;
    BOOL pruned = [self.controller.serviceDatabases pruneEventsBefore:[NSDate dateWithTimeIntervalSinceNow:-3600] error:&error];
    XCTAssertTrue(pruned, @"Pruning failed: %@", error);
    
    // Verify count is 0
    NSArray *events = [self.controller.serviceDatabases getEventsSince:0 limit:10 error:nil];
    XCTAssertEqual(events.count, 0, @"Events should be pruned");
    
    // 4. Broadcast Event 3
    [self.handler broadcastIdentityChange:@"did:plc:prune3" handle:@"prune3.bsky.social"];
    [self waitForHandlerIdle];
    
    // 5. Connect with cursor 1 (which refers to a pruned event)
    MockWebSocketConnection *conn = [[MockWebSocketConnection alloc] init];
    [self.handler sendInitialRepositoryStateToConnection:conn cursor:@"1"];
    [self waitForHandlerIdle];
    
    // 6. Verify we receive OutdatedCursor notice followed by Event 3
    XCTAssertFalse(conn.didClose);
    XCTAssertEqual(conn.sentMessages.count, 2U);
    if (conn.sentMessages.count >= 2) {
        NSInteger op1 = 0;
        NSInteger op2 = 0;
        NSString *type1 = nil;
        NSString *type2 = nil;
        NSDictionary *msg1 = [formatter decodeEventFromData:conn.sentMessages[0] op:&op1 msgType:&type1 error:nil];
        NSDictionary *msg2 = [formatter decodeEventFromData:conn.sentMessages[1] op:&op2 msgType:&type2 error:nil];
        XCTAssertEqualObjects(type1, @"#info");
        XCTAssertEqualObjects(type2, @"#identity");
        XCTAssertEqualObjects(msg1[@"name"], @"OutdatedCursor");
        XCTAssertEqualObjects(msg2[@"did"], @"did:plc:prune3");
    }
}
#endif

#ifndef GNUSTEP
- (void)testSequenceInitializationFromDisk {
    // 1. Broadcast a persisted event with current handler
    [self.handler broadcastIdentityChange:@"did:plc:init1" handle:@"init1.bsky.social"];
    [self waitForHandlerIdle];
    
    // Verify seq is 1
    int64_t maxSeq = [self.controller.serviceDatabases getMaxEventSequence:nil];
    XCTAssertEqual(maxSeq, 1);
    
    // 2. Stop handler
    [self.handler stop];
    self.handler = nil;
    
    // 3. Create NEW handler with SAME controller (same DB)
    SubscribeReposHandler *newHandler =
        [[SubscribeReposHandler alloc]
            initWithServiceDatabases:self.controller.serviceDatabases
                    userDatabasePool:self.controller.userDatabasePool];
    
    // 4. Broadcast new persisted event
    [newHandler broadcastIdentityChange:@"did:plc:init2" handle:@"init2.bsky.social"];
    [self waitForHandler:newHandler idleWithTimeout:1.0];
    
    // 5. Verify seq incremented to 2 (not reset to 1)
    maxSeq = [self.controller.serviceDatabases getMaxEventSequence:nil];
    XCTAssertEqual(maxSeq, 2);
    
    NSArray *events = [self.controller.serviceDatabases getEventsSince:0 limit:10 error:nil];
    XCTAssertEqual(events.count, 2);
    XCTAssertEqualObjects(events[1][@"seq"], @2);
    
    [newHandler stop];
}
#endif

@end
