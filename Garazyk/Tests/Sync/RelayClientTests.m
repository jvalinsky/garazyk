// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/Relay/RelayClient.h"
#import "Sync/Firehose/Firehose.h"
#import "Core/CID.h"

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoRelayClient (Testing)
- (void)firehoseSubscriptionDidConnect:(ATProtoFirehoseSubscription *)subscription;
- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveCommitEvent:(ATProtoFirehoseCommitEvent *)event;
- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveSyncEvent:(ATProtoFirehoseSyncEvent *)event;
- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveIdentityEvent:(ATProtoFirehoseIdentityEvent *)event;
- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveErrorEvent:(ATProtoFirehoseErrorEvent *)event;
- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didCloseWithError:(NSError * _Nullable)error;
- (NSURL *)buildWebSocketURL;
- (ATProtoFirehose *)configuredFirehoseForWebSocketURL:(NSURL *)webSocketURL;
- (void)scheduleReconnect;
@end

@interface RelayClientTestDelegate : NSObject <RelayClientDelegate>
@property (nonatomic, strong) XCTestExpectation *connectExpectation;
@property (nonatomic, strong) XCTestExpectation *commitExpectation;
@property (nonatomic, strong, nullable) XCTestExpectation *identityExpectation;
@property (nonatomic, strong, nullable) XCTestExpectation *syncExpectation;
@property (nonatomic, strong, nullable) XCTestExpectation *errorExpectation;
@property (nonatomic, strong, nullable) XCTestExpectation *disconnectExpectation;
@property (nonatomic, strong, nullable) XCTestExpectation *cursorExpectation;
@property (nonatomic, strong, nullable) ATProtoFirehoseCommitEvent *commitEvent;
@property (nonatomic, strong, nullable) ATProtoFirehoseIdentityEvent *identityEvent;
@property (nonatomic, strong, nullable) ATProtoFirehoseSyncEvent *syncEvent;
@property (nonatomic, strong, nullable) ATProtoFirehoseErrorEvent *errorEvent;
@property (nonatomic, strong, nullable) NSError *disconnectError;
@property (nonatomic, assign) int64_t receivedCursor;
@end

@implementation RelayClientTestDelegate

- (void)relayClientDidConnect:(ATProtoRelayClient *)client {
    [self.connectExpectation fulfill];
}

- (void)relayClient:(ATProtoRelayClient *)client didReceiveCommitEvent:(ATProtoFirehoseCommitEvent *)event {
    self.commitEvent = event;
    [self.commitExpectation fulfill];
}

- (void)relayClient:(ATProtoRelayClient *)client didReceiveIdentityEvent:(ATProtoFirehoseIdentityEvent *)event {
    self.identityEvent = event;
    [self.identityExpectation fulfill];
}

- (void)relayClient:(ATProtoRelayClient *)client didReceiveSyncEvent:(ATProtoFirehoseSyncEvent *)event {
    self.syncEvent = event;
    [self.syncExpectation fulfill];
}

- (void)relayClient:(ATProtoRelayClient *)client didReceiveErrorEvent:(ATProtoFirehoseErrorEvent *)event {
    self.errorEvent = event;
    [self.errorExpectation fulfill];
}

- (void)relayClient:(ATProtoRelayClient *)client didDisconnectWithError:(NSError * _Nullable)error {
    self.disconnectError = error;
    [self.disconnectExpectation fulfill];
}

- (void)relayClient:(ATProtoRelayClient *)client didReceiveCursor:(int64_t)cursor {
    self.receivedCursor = cursor;
    [self.cursorExpectation fulfill];
}

@end

@interface RelayClientTests : XCTestCase
@end

@implementation RelayClientTests

- (BOOL)waitForCursorInClient:(ATProtoRelayClient *)client repo:(NSString *)repo expected:(int64_t)expected {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
        int64_t cursor = [client getStoredCursorForRepo:repo];
        if (cursor == expected) {
            return YES;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return NO;
}

- (void)testStoreAndGetCursor {
    ATProtoRelayClient *client = [[ATProtoRelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    [client storeCursor:123 forRepo:@"did:plc:alice"];
    XCTAssertTrue([self waitForCursorInClient:client repo:@"did:plc:alice" expected:123]);
}

- (void)testSetAccessTokenDoesNotReenterSetter {
    ATProtoRelayClient *client = [[ATProtoRelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    XCTAssertNoThrow([client setAccessToken:@"test-token"]);
    XCTAssertEqualObjects([client valueForKey:@"accessToken"], @"test-token");
    ATProtoFirehose *firehose =
        [client configuredFirehoseForWebSocketURL:
            [NSURL URLWithString:@"wss://example.com/xrpc/com.atproto.sync.subscribeRepos"]];
    XCTAssertEqualObjects(firehose.accessToken, @"test-token");
}

- (void)testStoredCursorDoesNotRegress {
    ATProtoRelayClient *client = [[ATProtoRelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    [client storeCursor:200 forRepo:@"did:plc:alice"];
    [client storeCursor:199 forRepo:@"did:plc:alice"];
    XCTAssertTrue([self waitForCursorInClient:client repo:@"did:plc:alice" expected:200]);
}

- (void)testBuildWebSocketURLDefaultPortAndPath {
    ATProtoRelayClient *client = [[ATProtoRelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://relay.example.com"]];
    NSURL *url = [client buildWebSocketURL];
    XCTAssertEqualObjects(url.scheme, @"wss");
    XCTAssertEqualObjects(url.host, @"relay.example.com");
    XCTAssertEqualObjects(url.path, @"/xrpc/com.atproto.sync.subscribeRepos");
    XCTAssertEqualObjects(url.port, @(443));
    XCTAssertNil(url.query);
}

- (void)testBuildWebSocketURLIncludesCursorWhenPresent {
    ATProtoRelayClient *client = [[ATProtoRelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://relay.example.com:8443"]];
    [client setValue:@(98765) forKey:@"currentSeq"];
    NSURL *url = [client buildWebSocketURL];
    XCTAssertEqualObjects(url.port, @(8443));
    XCTAssertEqualObjects(url.query, @"cursor=98765");
}

- (void)testCloseWithNilErrorStillReportsCursor {
    ATProtoRelayClient *client = [[ATProtoRelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    RelayClientTestDelegate *delegate = [[RelayClientTestDelegate alloc] init];
    delegate.cursorExpectation = [self expectationWithDescription:@"cursor"];
    [client setValue:delegate forKey:@"delegate"];
    [client setValue:@(321) forKey:@"currentSeq"];
    [client setValue:@YES forKey:@"isConnected"];

    ATProtoFirehoseSubscription *subscription = [[ATProtoFirehoseSubscription alloc] initWithCursor:0 collections:nil];
    [client firehoseSubscription:subscription didCloseWithError:nil];
    // The delegate will call [expectation fulfill]

    [self waitForExpectations:@[delegate.cursorExpectation] timeout:1.0];
    XCTAssertFalse(client.isConnected);
    XCTAssertEqual(delegate.receivedCursor, 321);
}

- (void)testCloseWithErrorSchedulesReconnectAtLimitReportsDisconnect {
    ATProtoRelayClient *client = [[ATProtoRelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    RelayClientTestDelegate *delegate = [[RelayClientTestDelegate alloc] init];
    delegate.cursorExpectation = [self expectationWithDescription:@"cursor"];
    delegate.disconnectExpectation = [self expectationWithDescription:@"disconnect"];
    [client setValue:delegate forKey:@"delegate"];
    [client setValue:@(77) forKey:@"currentSeq"];
    [client setValue:@NO forKey:@"isConnected"];
    [client setValue:@YES forKey:@"shouldReconnect"];
    [client setValue:@(10) forKey:@"maxReconnectAttempts"];
    [client setValue:@(10) forKey:@"reconnectAttempts"];


    ATProtoFirehoseSubscription *subscription = [[ATProtoFirehoseSubscription alloc] initWithCursor:0 collections:nil];
    NSError *closeError = [NSError errorWithDomain:@"test" code:9 userInfo:nil];
    [client firehoseSubscription:subscription didCloseWithError:closeError];
    // The delegate will call [expectation fulfill]

    [self waitForExpectations:@[delegate.cursorExpectation, delegate.disconnectExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.disconnectError.domain, RelayClientErrorDomain);
    XCTAssertEqual(delegate.disconnectError.code, RelayClientErrorCodeConnectionFailed);
}

- (void)testIdentityAndErrorEventsForwardToDelegate {
    ATProtoRelayClient *client = [[ATProtoRelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    RelayClientTestDelegate *delegate = [[RelayClientTestDelegate alloc] init];
    delegate.identityExpectation = [self expectationWithDescription:@"identity"];
    delegate.errorExpectation = [self expectationWithDescription:@"error"];
    [client setValue:delegate forKey:@"delegate"];

    ATProtoFirehoseSubscription *subscription = [[ATProtoFirehoseSubscription alloc] initWithCursor:0 collections:nil];
    ATProtoFirehoseIdentityEvent *identity = [ATProtoFirehoseIdentityEvent eventWithDid:@"did:plc:alice"];
    ATProtoFirehoseErrorEvent *errorEvent = [ATProtoFirehoseErrorEvent eventWithError:@"FutureCursor" message:@"cursor ahead"];
    [client firehoseSubscription:subscription didReceiveIdentityEvent:identity];
    [client firehoseSubscription:subscription didReceiveErrorEvent:errorEvent];
    // The delegate will call [expectation fulfill]

    [self waitForExpectations:@[delegate.identityExpectation, delegate.errorExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.identityEvent.did, @"did:plc:alice");
    XCTAssertEqualObjects(delegate.errorEvent.error, @"FutureCursor");
}

- (void)testSyncEventForwardsToDelegateAndAdvancesCursor {
    ATProtoRelayClient *client = [[ATProtoRelayClient alloc]
        initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    RelayClientTestDelegate *delegate = [[RelayClientTestDelegate alloc] init];
    delegate.syncExpectation = [self expectationWithDescription:@"sync"];
    [client setValue:delegate forKey:@"delegate"];

    ATProtoFirehoseSubscription *subscription =
        [[ATProtoFirehoseSubscription alloc] initWithCursor:0 collections:nil];
    ATProtoFirehoseSyncEvent *sync =
        [ATProtoFirehoseSyncEvent eventWithDid:@"did:plc:alice"
                                    rev:@"3mrogbz3mwr2t"
                                 blocks:[NSData dataWithBytes:"car" length:3]];
    sync.seq = 456;
    [client firehoseSubscription:subscription didReceiveSyncEvent:sync];

    [self waitForExpectations:@[delegate.syncExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.syncEvent, sync);
    XCTAssertEqual(client.currentSeq, 456);
}

#ifndef GNUSTEP
- (void)testConnectAndCommitDispatch {
    ATProtoRelayClient *client = [[ATProtoRelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    RelayClientTestDelegate *delegate = [[RelayClientTestDelegate alloc] init];
    delegate.connectExpectation = [self expectationWithDescription:@"connect"];
    delegate.commitExpectation = [self expectationWithDescription:@"commit"];
    [client setValue:delegate forKey:@"delegate"];

    ATProtoFirehoseSubscription *subscription = [[ATProtoFirehoseSubscription alloc] initWithCursor:0 collections:nil];
    [client firehoseSubscriptionDidConnect:subscription];
    [self waitForExpectations:@[delegate.connectExpectation] timeout:1.0];
    XCTAssertTrue(client.isConnected);

    // Create ATProtoCID for commit field
    NSData *digest = [@"cursor2" dataUsingEncoding:NSUTF8StringEncoding];
    ATProtoCID *commitCID = [ATProtoCID cidWithDigest:digest codec:0x71];
    
    ATProtoFirehoseCommitEvent *event = [ATProtoFirehoseCommitEvent eventWithRepo:@"did:plc:alice"
                                                              commit:commitCID
                                                                 ops:@[@{@"action": @"create"}]];
    event.seq = 456;
    [client firehoseSubscription:subscription didReceiveCommitEvent:event];
    // The delegate will call [expectation fulfill]

    [self waitForExpectations:@[delegate.commitExpectation] timeout:1.0];
    // Note: currentCursor might be based on event.rev or seq, not commit ATProtoCID
    // Just verify we got the event
    XCTAssertNotNil(delegate.commitEvent.commit);
}

- (void)testOutOfOrderCommitDoesNotRegressReconnectCursor {
    ATProtoRelayClient *client = [[ATProtoRelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    ATProtoFirehoseSubscription *subscription = [[ATProtoFirehoseSubscription alloc] initWithCursor:0 collections:nil];
    ATProtoCID *commitCID = [ATProtoCID cidWithDigest:[@"monotonic" dataUsingEncoding:NSUTF8StringEncoding]
                                  codec:0x71];

    ATProtoFirehoseCommitEvent *newer = [ATProtoFirehoseCommitEvent eventWithRepo:@"did:plc:alice"
                                                             commit:commitCID
                                                                ops:@[]];
    newer.seq = 200;
    [client firehoseSubscription:subscription didReceiveCommitEvent:newer];

    ATProtoFirehoseCommitEvent *older = [ATProtoFirehoseCommitEvent eventWithRepo:@"did:plc:alice"
                                                             commit:commitCID
                                                                ops:@[]];
    older.seq = 199;
    [client firehoseSubscription:subscription didReceiveCommitEvent:older];

    XCTAssertEqual(client.currentSeq, 200);
    XCTAssertTrue([self waitForCursorInClient:client repo:@"did:plc:alice" expected:200]);
}
#endif

@end

NS_ASSUME_NONNULL_END
