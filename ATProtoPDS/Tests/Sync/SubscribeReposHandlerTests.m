#import <XCTest/XCTest.h>
#import "Sync/SubscribeReposHandler.h"
#import "App/PDSController.h"
#import "Repository/RepoCommit.h"
#import "Sync/WebSocketConnection.h"
#import "Sync/WebSocketServer.h"
#import "Sync/EventFormatter.h"
#import "Database/Service/ServiceDatabases.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
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
    
    self.handler = [[SubscribeReposHandler alloc] initWithController:self.controller];
}

- (void)tearDown {
    [self.handler stop];
    [self.controller stopServer];
    self.handler = nil;
    self.controller = nil;
    @autoreleasepool { }  // Drain to ensure deallocs before file deletion
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
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
        [CID cidFromString:@"bafkreidmv76shvthv2m762sk26atksnk7v7hxuvrk6kk6kk6kk6kk6k"]
    ];
    
    // This is a minimal test to ensure we can pass ops and blobs
    // and that they are handled without crashing.
    XCTAssertNoThrow([self.handler broadcastRepositoryCommit:commit 
                                                     forRepo:@"did:plc:test" 
                                                         ops:ops 
                                                       blobs:blobs], 
                      @"Should handle broadcast with ops and blobs");
                      
    XCTestExpectation *persistExp = [self expectationWithDescription:@"Event persisted"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSError *err = nil;
        int64_t maxSeq = [self.controller.serviceDatabases getMaxEventSequence:&err];
        XCTAssertGreaterThan(maxSeq, 0);
        [persistExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
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
    
    // Wait for async dispatch
    XCTestExpectation *expectation = [self expectationWithDescription:@"Backpressure check"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    XCTAssertTrue(testConn.didClose, @"Connection should be closed due to count backpressure");
    XCTAssertEqual(testConn.closedCode, 1008);
    
    // Reset and test bytes backpressure
    MockWebSocketConnection *testConn2 = [[MockWebSocketConnection alloc] init];
    [(id)self.handler webSocketServer:nil didAcceptConnection:testConn2];
    
    testConn2.simulatedPendingSendCount = 0;
    testConn2.simulatedPendingSendBytes = self.handler.maxPendingBytesPerConnection + 1;
    
    [self.handler broadcastRepositoryCommit:commit forRepo:@"did:plc:test" ops:ops blobs:@[]];
    
    XCTestExpectation *expectation2 = [self expectationWithDescription:@"Backpressure check bytes"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [expectation2 fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    XCTAssertTrue(testConn2.didClose, @"Connection should be closed due to bytes backpressure");
    XCTAssertEqual(testConn2.closedCode, 1008);
}
#endif

#ifndef GNUSTEP
- (void)testBroadcastPersistsEvent {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Event persisted"];
    
    EventFormatter *formatter = [[EventFormatter alloc] init];
    
    [self.handler broadcastIdentityChange:@"did:plc:test_persist" handle:@"test.bsky.social"];
    
    // Wait a bit for async dispatch
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
        
        // Decode stream event data using proper decoder
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
        
        [expectation fulfill];
    });
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}
#endif

#ifndef GNUSTEP
- (void)testReplayWithCursor {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    
    // 1. Create some events
    [self.handler broadcastInfo:@"info1" message:@"msg1"];
    [self.handler broadcastInfo:@"info2" message:@"msg2"];
    [self.handler broadcastInfo:@"info3" message:@"msg3"];
    
    // Wait for persistence
    XCTestExpectation *persistExp = [self expectationWithDescription:@"Events persisted"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [persistExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    // 2. Simulate connection with cursor=1 (should get info2 and info3)
    MockWebSocketConnection *conn = [[MockWebSocketConnection alloc] init];
    conn.mockQueryParams = @{@"cursor": @"1"};
    [self.handler sendInitialRepositoryStateToConnection:conn cursor:@"1"];
    
    // Wait for async replay
    XCTestExpectation *replayExp = [self expectationWithDescription:@"Replay finished"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [replayExp fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    
    // Verify received messages using proper stream decoder
    XCTAssertEqual(conn.sentMessages.count, 2, "Should receive 2 events (info2, info3)");
    
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
        XCTAssertEqualObjects(type1, @"#info");
        XCTAssertEqualObjects(type2, @"#info");
        XCTAssertEqualObjects(msg1[@"name"], @"info2");
        XCTAssertEqualObjects(msg2[@"name"], @"info3");
    }
}
#endif

#ifndef GNUSTEP
- (void)testReplayWithFutureCursorSendsFutureCursorError {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    [self.handler broadcastInfo:@"seed" message:@"seed"];

    XCTestExpectation *persistExp = [self expectationWithDescription:@"Seed persisted"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [persistExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    MockWebSocketConnection *conn = [[MockWebSocketConnection alloc] init];
    [self.handler sendInitialRepositoryStateToConnection:conn cursor:@"999999"];

    XCTestExpectation *replayExp = [self expectationWithDescription:@"Future cursor handled"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [replayExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

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
    XCTAssertEqualObjects(payload[@"error"], @"FutureCursor");
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

    XCTestExpectation *firstCommitExp = [self expectationWithDescription:@"First commit persisted"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [firstCommitExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

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

    XCTestExpectation *secondCommitExp = [self expectationWithDescription:@"Second commit persisted"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [secondCommitExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

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

    [self.handler broadcastInfo:@"info1" message:@"msg1"];
    [self.handler broadcastInfo:@"info2" message:@"msg2"];
    [self.handler broadcastInfo:@"info3" message:@"msg3"];

    XCTestExpectation *persistExp = [self expectationWithDescription:@"Events persisted"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [persistExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    MockWebSocketConnection *conn = [[MockWebSocketConnection alloc] init];
    [self.handler sendInitialRepositoryStateToConnection:conn cursor:@"1"];

    XCTestExpectation *replayExp = [self expectationWithDescription:@"Too slow handled"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [replayExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertFalse(conn.didClose);
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
    XCTAssertEqualObjects(eventType, @"#info");
    XCTAssertEqualObjects(eventPayload[@"name"], @"info3");
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

    XCTestExpectation *broadcastExp = [self expectationWithDescription:@"Broadcast finished"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [broadcastExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

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
                     
    XCTestExpectation *persistExp = [self expectationWithDescription:@"Event persisted"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSError *err = nil;
        int64_t maxSeq = [self.controller.serviceDatabases getMaxEventSequence:&err];
        XCTAssertGreaterThan(maxSeq, 0);
        [persistExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testBroadcastAccountTakedownValidatesMaxSeqIsGreater {
    XCTAssertNoThrow([self.handler broadcastAccountTakedown:@"did:plc:malicious"],
                     @"Should handle account takedown broadcast");
                     
    XCTestExpectation *persistExp = [self expectationWithDescription:@"Event persisted"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSError *err = nil;
        int64_t maxSeq = [self.controller.serviceDatabases getMaxEventSequence:&err];
        XCTAssertGreaterThan(maxSeq, 0);
        [persistExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testBroadcastInfoEventValidatesMaxSeqIsGreater {
    XCTAssertNoThrow([self.handler broadcastInfo:@"OutdatedCursor" message:@"Requested sequence too far back"],
                      @"Should handle info event broadcast");
                      
    XCTestExpectation *persistExp = [self expectationWithDescription:@"Event persisted"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSError *err = nil;
        int64_t maxSeq = [self.controller.serviceDatabases getMaxEventSequence:&err];
        XCTAssertGreaterThan(maxSeq, 0);
        [persistExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

#ifndef GNUSTEP
- (void)testReplayWithPrunedEventsHandlesGap {
    EventFormatter *formatter = [[EventFormatter alloc] init];
    
    // 1. Broadcast two events (Seq 1, 2)
    [self.handler broadcastInfo:@"info1" message:@"msg1"];
    [self.handler broadcastInfo:@"info2" message:@"msg2"];
    
    XCTestExpectation *persistExp = [self expectationWithDescription:@"Events 1&2 persisted"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [persistExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    // 2. Backdate events 1 & 2 in DB to allow pruning
    // We use the service pool directly to execute raw SQL update
    PDSDatabasePool *pool = self.controller.serviceDatabases.servicePool;
    [pool transactWithDid:@"__service__" block:^(id transactor, NSError **err) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        // Backdate to 2 hours ago
        NSTimeInterval oldTime = [[NSDate dateWithTimeIntervalSinceNow:-7200] timeIntervalSince1970];
        NSString *sql = [NSString stringWithFormat:@"UPDATE events SET created_at = %f WHERE seq <= 2", oldTime];
        sqlite3_exec(store.db, sql.UTF8String, NULL, NULL, NULL);
    } error:nil];
    
    // 3. Prune events older than 1 hour ago
    NSError *error = nil;
    BOOL pruned = [self.controller.serviceDatabases pruneEventsBefore:[NSDate dateWithTimeIntervalSinceNow:-3600] error:&error];
    XCTAssertTrue(pruned, @"Pruning failed: %@", error);
    
    // Verify count is 0
    NSArray *events = [self.controller.serviceDatabases getEventsSince:0 limit:10 error:nil];
    XCTAssertEqual(events.count, 0, @"Events should be pruned");
    
    // 4. Broadcast Event 3
    [self.handler broadcastInfo:@"info3" message:@"msg3"];
    
    XCTestExpectation *persistExp2 = [self expectationWithDescription:@"Event 3 persisted"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [persistExp2 fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    // 5. Connect with cursor 1 (which refers to a pruned event)
    MockWebSocketConnection *conn = [[MockWebSocketConnection alloc] init];
    // backlog = (Current Seq 3) - (Cursor 1) = 2. Should be fine.
    [self.handler sendInitialRepositoryStateToConnection:conn cursor:@"1"];
    
    XCTestExpectation *replayExp = [self expectationWithDescription:@"Replay finished"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [replayExp fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    
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
        XCTAssertEqualObjects(type2, @"#info");
        XCTAssertEqualObjects(msg1[@"name"], @"OutdatedCursor");
        XCTAssertEqualObjects(msg2[@"name"], @"info3");
    }
}
#endif

#ifndef GNUSTEP
- (void)testSequenceInitializationFromDisk {
    // 1. Broadcast an event with current handler
    [self.handler broadcastInfo:@"init1" message:@"msg1"];
    
    XCTestExpectation *persistExp = [self expectationWithDescription:@"Init persisted"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [persistExp fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    // Verify seq is 1
    int64_t maxSeq = [self.controller.serviceDatabases getMaxEventSequence:nil];
    XCTAssertEqual(maxSeq, 1);
    
    // 2. Stop handler
    [self.handler stop];
    self.handler = nil;
    
    // 3. Create NEW handler with SAME controller (same DB)
    SubscribeReposHandler *newHandler = [[SubscribeReposHandler alloc] initWithController:self.controller];
    
    // 4. Broadcast new event
    [newHandler broadcastInfo:@"init2" message:@"msg2"];
    
    XCTestExpectation *persistExp2 = [self expectationWithDescription:@"Init2 persisted"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [persistExp2 fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
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
