// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Sync/WebSocket/WebSocketConnection.h"
#import "Sync/Relay/EventFormatter.h"
#import "Repository/CAR.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import "Database/Pool/DatabasePool.h"
#import "Services/PDS/PDSRecordService.h"
#import "Admin/PDSAdminController.h" 

// Expose private property for testing
@interface ATProtoSubscribeReposHandler (Testing)
@property (nonatomic, strong) NSMutableSet<ATProtoWebSocketConnection *> *attachedConnections;
- (void)ensureSequenceInitialized;
- (void)startObservingNotifications;
@end

// Mock Connection
@interface FirehoseIntegrationMockConnection : ATProtoWebSocketConnection
@property (nonatomic, strong) NSData *lastMessage;
@property (nonatomic, assign) NSInteger messageCount;
@end

@implementation FirehoseIntegrationMockConnection
- (instancetype)init {
    return [super initWithHost:@"mock" port:0 path:@"/"];
}
- (void)sendMessage:(NSData *)data {
    self.lastMessage = data;
    self.messageCount++;
}
@end

@interface FirehoseIntegrationTests : XCTestCase
@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, copy) NSString *tempDir;
@property (nonatomic, copy) NSString *did;
@end

@implementation FirehoseIntegrationTests

- (void)setUp {
    [super setUp];
    
    NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:guid];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    // Initialize controller
    self.controller = [[PDSController alloc] initWithDirectory:self.tempDir
                                                serviceMaxSize:5
                                              userDatabaseSize:5];
    
    // Create an account
    NSError *error = nil;
    NSDictionary *account = [self.controller createAccountForEmail:@"alice@test.com"
                                                         password:@"password"
                                                           handle:@"alice.test"
                                                              did:nil
                                                            error:&error];
    XCTAssertNotNil(account, @"Failed to create account: %@", error);
    self.did = account[@"did"];
}

- (void)tearDown {
    [self.controller stopServer];
    if (self.tempDir) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    }
    [super tearDown];
}

#ifndef GNUSTEP
- (void)testBroadcastCommitCARContainsRecordBlocks {
    NSError *error = nil;
    XCTAssertNotNil(self.did);

    // Create Handler using new initializer
    ATProtoSubscribeReposHandler *handler = [[ATProtoSubscribeReposHandler alloc] initWithServiceDatabases:self.controller.serviceDatabases 
                                                                           userDatabasePool:self.controller.userDatabasePool];
    handler.signingKey = [NSData dataWithBytes:"dummykey" length:32];
    
    // Attach mock connection
    FirehoseIntegrationMockConnection *mockConn = [[FirehoseIntegrationMockConnection alloc] init];
    [handler ensureSequenceInitialized];
    // Normally registered by -startOnPort:error:, which this test skips
    // since it drives commits through a mock connection instead of a real
    // WebSocket server; without it, -handleRecordChange: never fires and
    // no commit is ever broadcast.
    [handler startObservingNotifications];

    @synchronized (handler.attachedConnections) {
        [(NSMutableSet *)handler.attachedConnections addObject:mockConn];
    }
    
    // Perform Record Creation
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSString *now = [formatter stringFromDate:[NSDate date]];
    
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello Firehose Integration!",
        @"createdAt": now
    };
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Broadcast received"];
    
    // Create record
    BOOL success = [self.controller putRecord:@"app.bsky.feed.post"
                                         rkey:@"post1"
                                        value:record
                                       forDid:self.did
                               validationMode:PDSValidationModeOff
                                        error:&error];
    
    XCTAssertTrue(success, @"Failed to put record: %@", error);
    
    // Poll mockConn
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (int i=0; i<20; i++) {
            if (mockConn.messageCount > 0) {
                [expectation fulfill];
                break;
            }
            [NSThread sleepForTimeInterval:0.1];
        }
    });

    [self waitForExpectationsWithTimeout:3.0 handler:nil];
    
    XCTAssertGreaterThan(mockConn.messageCount, 0);
    NSData *msg = mockConn.lastMessage;
    XCTAssertNotNil(msg);
    
    // A firehose frame is two concatenated dag-cbor objects (header, then
    // payload) with no length prefix; ATProtoDagCBOR decodeData: rejects
    // trailing bytes after a complete item, so it can't be used to split
    // this buffer manually. Use ATProtoEventFormatter's own incremental decoder
    // instead — the same one the real firehose consumer (ATProtoFirehose.m's
    // handleMessage:) uses.
    ATProtoEventFormatter *eventFormatter = [[ATProtoEventFormatter alloc] init];
    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *payloadMap = [eventFormatter decodeEventFromData:msg op:&op msgType:&msgType error:&error];
    XCTAssertNotNil(payloadMap, @"Failed to decode firehose event: %@", error);
    XCTAssertEqualObjects(msgType, @"#commit");
    
    // "blocks" key contains CAR bytes
    NSData *carData = payloadMap[@"blocks"];
    XCTAssertNotNil(carData);
    
    // Verify CAR Content
    ATProtoCARReader *reader = [ATProtoCARReader readFromData:carData error:&error];
    XCTAssertNotNil(reader, @"Failed to read CAR: %@", error);
    
    // Should contain at least 2 blocks: Commit and Record
    XCTAssertGreaterThanOrEqual(reader.blocks.count, 2);
    
    // Verify Record Block
    BOOL foundRecord = NO;
    for (ATProtoCARBlock *block in reader.blocks) {
        id obj = [ATProtoDagCBOR decodeData:block.data error:nil];
        if ([obj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)obj;
            // Check for record content
            if ([dict[@"text"] isEqualToString:@"Hello Firehose Integration!"]) {
                foundRecord = YES;
                break;
            }
        }
    }
    XCTAssertTrue(foundRecord, @"CAR did not contain the record block");
}
#endif

@end
