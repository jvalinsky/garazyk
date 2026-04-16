
#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Repository/RepoCommit.h"
#import "Core/CID.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/TID.h"
#import "Services/PDS/PDSRecordService.h"
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Sync/WebSocket/WebSocketConnection.h"

// Expose private property for testing
@interface SubscribeReposHandler (CommitChainTesting)
@property (nonatomic, strong) NSMutableSet<WebSocketConnection *> *attachedConnections;
- (void)ensureSequenceInitialized;
@end

// Mock Connection
@interface CommitChainMockConnection : WebSocketConnection
@property (nonatomic, strong) NSMutableArray<NSData *> *messages;
@property (nonatomic, assign) NSInteger messageCount;
@end

@implementation CommitChainMockConnection
- (instancetype)init {
    self = [super initWithHost:@"mock" port:0 path:@"/"];
    if (self) {
        _messages = [NSMutableArray array];
    }
    return self;
}
- (void)sendMessage:(NSData *)data {
    [self.messages addObject:data];
    self.messageCount++;
}
@end

@interface CommitChainTests : XCTestCase

@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, copy) NSString *tempDir;
@property (nonatomic, copy) NSString *did;

@end

@implementation CommitChainTests

- (void)setUp {
    [super setUp];

    // Create a temporary directory for isolation
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:uuid];
    
    // Initialize controller using modern API
    self.controller = [[PDSController alloc] initWithDirectory:self.tempDir 
                                                serviceMaxSize:5 
                                              userDatabaseSize:5];
    
    // Create a user
    NSError *error = nil;
    NSDictionary *acc = [self.controller createAccountForEmail:@"chain@test.local"
                                                      password:@"password"
                                                        handle:@"chain.test"
                                                           did:nil
                                                         error:&error];
    XCTAssertNotNil(acc, @"Account creation failed: %@", error);
    self.did = acc[@"did"];
}

- (void)tearDown {
    [self.controller stopServer];
    // Clean up temp dir
    if (self.tempDir) {
         [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    }
    [super tearDown];
}

- (void)testCommitChainIntegrity {
    NSError *error = nil;

    // 1. Create initial record (Genesis + 1)
    NSDictionary *record1 = @{@"text": @"post 1", @"createdAt": [[TID tid] stringValue]};
    BOOL success1 = [self.controller putRecord:@"app.bsky.feed.post"
                                          rkey:@"post1"
                                         value:record1
                                        forDid:self.did
                                validationMode:PDSValidationModeOff
                                         error:&error];
    XCTAssertTrue(success1, @"Failed to create record 1: %@", error);
    
    // 2. Fetch Repo Root (Head 1)
    PDSActorStore *store = [self.controller.userDatabasePool storeForDid:self.did error:&error];
    XCTAssertNotNil(store);
    
    NSData *rootBytes1 = [store getRepoRootForDid:self.did error:&error];
    XCTAssertNotNil(rootBytes1, @"Repo root missing");
    
    CID *commit1CID = [CID cidFromBytes:rootBytes1];
    XCTAssertNotNil(commit1CID);
    
    // 3. Verify Commit 1 validity
    NSData *block1 = [store getBlockForCID:[commit1CID bytes] forDid:self.did error:&error];
    XCTAssertNotNil(block1, @"Commit block 1 missing");
    
    NSDictionary *map1 = [ATProtoDagCBOR decodeData:block1 error:&error];
    XCTAssertNotNil(map1, @"Failed to decode commit 1");
    
    XCTAssertNotNil(map1[@"sig"], @"Commit 1 should be signed");
    
    // 4. Create another record
    NSDictionary *record2 = @{@"text": @"post 2", @"createdAt": [[TID tid] stringValue]};
    BOOL success2 = [self.controller putRecord:@"app.bsky.feed.post"
                                          rkey:@"post2"
                                         value:record2
                                        forDid:self.did
                                validationMode:PDSValidationModeOff
                                         error:&error];
    XCTAssertTrue(success2, @"Failed to create record 2: %@", error);
    
    // 5. Fetch Repo Root (Head 2)
    NSData *rootBytes2 = [store getRepoRootForDid:self.did error:&error];
    CID *commit2CID = [CID cidFromBytes:rootBytes2];
    XCTAssertNotNil(commit2CID);
    XCTAssertFalse([commit2CID isEqualToCID:commit1CID], @"Head should advance");
    
    // 6. Verify Commit 2 points to Commit 1
    NSData *block2 = [store getBlockForCID:[commit2CID bytes] forDid:self.did error:&error];
    XCTAssertNotNil(block2);
    
    NSDictionary *map2 = [ATProtoDagCBOR decodeData:block2 error:&error];
    XCTAssertNotNil(map2);
    
    id prevObj = map2[@"prev"];
    CID *prevCID = nil;
    if ([prevObj isKindOfClass:[CID class]]) {
        prevCID = (CID *)prevObj;
    } else if ([prevObj isKindOfClass:[NSString class]]) {
        prevCID = [CID cidFromString:(NSString *)prevObj];
    }
    
    XCTAssertNotNil(prevCID, @"Commit 2 should have prev");
    XCTAssertTrue([prevCID isEqualToCID:commit1CID], @"Commit 2 prev should match Commit 1 CID");
    
    XCTAssertNotNil(map2[@"sig"], @"Commit 2 should be signed");
}

- (NSDictionary *)decodeEventPayload:(NSData *)msg {
    NSError *error = nil;
    id header = [ATProtoDagCBOR decodeData:msg error:&error];
    if (!header || ![header isKindOfClass:[NSDictionary class]]) return nil;

    NSData *headerData = [ATProtoDagCBOR encodeObject:header error:nil];
    if (!headerData || headerData.length >= msg.length) return nil;

    NSData *payloadData = [msg subdataWithRange:NSMakeRange(headerData.length, msg.length - headerData.length)];
    id payload = [ATProtoDagCBOR decodeData:payloadData error:&error];
    if ([payload isKindOfClass:[NSDictionary class]]) return payload;
    return nil;
}

#ifndef GNUSTEP
- (void)testBroadcastCommitSetsSinceField {
    NSError *error = nil;

    // Create handler
    SubscribeReposHandler *handler = [[SubscribeReposHandler alloc] initWithServiceDatabases:self.controller.serviceDatabases
                                                                           userDatabasePool:self.controller.userDatabasePool];
    handler.signingKey = [NSData dataWithBytes:"dummykey" length:32];

    // Attach mock connection
    CommitChainMockConnection *mockConn = [[CommitChainMockConnection alloc] init];
    [handler ensureSequenceInitialized];

    @synchronized (handler.attachedConnections) {
        [handler.attachedConnections addObject:mockConn];
    }

    // Create record 1
    NSDictionary *record1 = @{@"text": @"since test 1", @"createdAt": [[TID tid] stringValue]};
    BOOL success1 = [self.controller putRecord:@"app.bsky.feed.post"
                                          rkey:@"since1"
                                         value:record1
                                        forDid:self.did
                                validationMode:PDSValidationModeOff
                                         error:&error];
    XCTAssertTrue(success1, @"Failed to create record 1: %@", error);

    // Poll until message 1 received
    XCTestExpectation *exp1 = [self expectationWithDescription:@"Message 1"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (int i = 0; i < 30; i++) {
            if (mockConn.messageCount >= 1) {
                [exp1 fulfill];
                return;
            }
            [NSThread sleepForTimeInterval:0.1];
        }
    });
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssertGreaterThanOrEqual(mockConn.messageCount, 1);

    // Decode rev from message 1
    NSDictionary *payload1 = [self decodeEventPayload:mockConn.messages[0]];
    XCTAssertNotNil(payload1, @"Failed to decode message 1");
    NSString *rev1 = payload1[@"rev"];
    XCTAssertNotNil(rev1, @"Message 1 should have rev");

    // Create record 2
    NSDictionary *record2 = @{@"text": @"since test 2", @"createdAt": [[TID tid] stringValue]};
    BOOL success2 = [self.controller putRecord:@"app.bsky.feed.post"
                                          rkey:@"since2"
                                         value:record2
                                        forDid:self.did
                                validationMode:PDSValidationModeOff
                                         error:&error];
    XCTAssertTrue(success2, @"Failed to create record 2: %@", error);

    // Poll until message 2 received
    XCTestExpectation *exp2 = [self expectationWithDescription:@"Message 2"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (int i = 0; i < 30; i++) {
            if (mockConn.messageCount >= 2) {
                [exp2 fulfill];
                return;
            }
            [NSThread sleepForTimeInterval:0.1];
        }
    });
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCTAssertGreaterThanOrEqual(mockConn.messageCount, 2);

    // Decode message 2 and verify since field
    NSDictionary *payload2 = [self decodeEventPayload:mockConn.messages[1]];
    XCTAssertNotNil(payload2, @"Failed to decode message 2");
    NSString *since = payload2[@"since"];
    XCTAssertNotNil(since, @"Message 2 should have since field");
    XCTAssertEqualObjects(since, rev1, @"since should equal rev of previous commit");
}
#endif

@end
