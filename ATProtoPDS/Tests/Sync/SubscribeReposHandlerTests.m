#import <XCTest/XCTest.h>
#import "Sync/SubscribeReposHandler.h"
#import "App/PDSController.h"
#import "Repository/RepoCommit.h"
#import "Sync/WebSocketConnection.h"
#import "Sync/WebSocketServer.h"
#import "Sync/EventFormatter.h"
#import "Database/Service/ServiceDatabases.h"
#import "Core/ATProtoCBORSerialization.h"

@interface MockWebSocketConnection : WebSocketConnection
@property (nonatomic, strong) NSMutableArray *sentMessages;
@property (nonatomic, copy) NSDictionary *mockQueryParams;
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
@end

@interface SubscribeReposHandler (TestAccess)
- (void)sendInitialRepositoryStateToConnection:(WebSocketConnection *)connection cursor:(nullable NSString *)cursor;
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
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    self.handler = nil;
    self.controller = nil;
    [super tearDown];
}

- (void)testBroadcastCommitWithOps {
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
}

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
        XCTAssertEqualObjects(msg1[@"info"], @"info2");
        XCTAssertEqualObjects(msg2[@"info"], @"info3");
    }
}

- (void)testBroadcastIdentityChange {
    XCTAssertNoThrow([self.handler broadcastIdentityChange:@"did:plc:test" handle:@"test.bsky.social"],
                     @"Should handle identity broadcast with handle");
    XCTAssertNoThrow([self.handler broadcastIdentityChange:@"did:plc:test2" handle:nil],
                     @"Should handle identity broadcast without handle");
}

- (void)testBroadcastAccountTakedown {
    XCTAssertNoThrow([self.handler broadcastAccountTakedown:@"did:plc:malicious"],
                     @"Should handle account takedown broadcast");
}

- (void)testBroadcastInfoEvent {
    XCTAssertNoThrow([self.handler broadcastInfo:@"OutdatedCursor" message:@"Requested sequence too far back"],
                     @"Should handle info event broadcast");
}

@end
