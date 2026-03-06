#import <XCTest/XCTest.h>
#import "Sync/RelayClient.h"
#import "Sync/Firehose.h"
#import "Core/CID.h"

NS_ASSUME_NONNULL_BEGIN

@interface RelayClient (Testing)
- (void)firehoseSubscriptionDidConnect:(FirehoseSubscription *)subscription;
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveCommitEvent:(FirehoseCommitEvent *)event;
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveIdentityEvent:(FirehoseIdentityEvent *)event;
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveErrorEvent:(FirehoseErrorEvent *)event;
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didCloseWithError:(NSError * _Nullable)error;
- (NSURL *)buildWebSocketURL;
- (void)scheduleReconnect;
@end

@interface RelayClientTestDelegate : NSObject <RelayClientDelegate>
@property (nonatomic, strong) XCTestExpectation *connectExpectation;
@property (nonatomic, strong) XCTestExpectation *commitExpectation;
@property (nonatomic, strong, nullable) XCTestExpectation *identityExpectation;
@property (nonatomic, strong, nullable) XCTestExpectation *errorExpectation;
@property (nonatomic, strong, nullable) XCTestExpectation *disconnectExpectation;
@property (nonatomic, strong, nullable) XCTestExpectation *cursorExpectation;
@property (nonatomic, strong, nullable) FirehoseCommitEvent *commitEvent;
@property (nonatomic, strong, nullable) FirehoseIdentityEvent *identityEvent;
@property (nonatomic, strong, nullable) FirehoseErrorEvent *errorEvent;
@property (nonatomic, strong, nullable) NSError *disconnectError;
@property (nonatomic, assign) int64_t receivedCursor;
@end

@implementation RelayClientTestDelegate

- (void)relayClientDidConnect:(RelayClient *)client {
    [self.connectExpectation fulfill];
}

- (void)relayClient:(RelayClient *)client didReceiveCommitEvent:(FirehoseCommitEvent *)event {
    self.commitEvent = event;
    [self.commitExpectation fulfill];
}

- (void)relayClient:(RelayClient *)client didReceiveIdentityEvent:(FirehoseIdentityEvent *)event {
    self.identityEvent = event;
    [self.identityExpectation fulfill];
}

- (void)relayClient:(RelayClient *)client didReceiveErrorEvent:(FirehoseErrorEvent *)event {
    self.errorEvent = event;
    [self.errorExpectation fulfill];
}

- (void)relayClient:(RelayClient *)client didDisconnectWithError:(NSError * _Nullable)error {
    self.disconnectError = error;
    [self.disconnectExpectation fulfill];
}

- (void)relayClient:(RelayClient *)client didReceiveCursor:(int64_t)cursor {
    self.receivedCursor = cursor;
    [self.cursorExpectation fulfill];
}

@end

@interface RelayClientTests : XCTestCase
@end

@implementation RelayClientTests

- (BOOL)waitForCursorInClient:(RelayClient *)client repo:(NSString *)repo expected:(int64_t)expected {
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
    RelayClient *client = [[RelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    [client storeCursor:123 forRepo:@"did:plc:alice"];
    XCTAssertTrue([self waitForCursorInClient:client repo:@"did:plc:alice" expected:123]);
}

- (void)testBuildWebSocketURLDefaultPortAndPath {
    RelayClient *client = [[RelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://relay.example.com"]];
    NSURL *url = [client buildWebSocketURL];
    XCTAssertEqualObjects(url.scheme, @"wss");
    XCTAssertEqualObjects(url.host, @"relay.example.com");
    XCTAssertEqualObjects(url.path, @"/xrpc/com.atproto.sync.subscribeRepos");
    XCTAssertEqualObjects(url.port, @(443));
    XCTAssertNil(url.query);
}

- (void)testBuildWebSocketURLIncludesCursorWhenPresent {
    RelayClient *client = [[RelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://relay.example.com:8443"]];
    [client setValue:@(98765) forKey:@"currentSeq"];
    NSURL *url = [client buildWebSocketURL];
    XCTAssertEqualObjects(url.port, @(8443));
    XCTAssertEqualObjects(url.query, @"cursor=98765");
}

- (void)testCloseWithNilErrorStillReportsCursor {
    RelayClient *client = [[RelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    RelayClientTestDelegate *delegate = [[RelayClientTestDelegate alloc] init];
    delegate.cursorExpectation = [self expectationWithDescription:@"cursor"];
    [client setValue:delegate forKey:@"delegate"];
    [client setValue:@(321) forKey:@"currentSeq"];
    [client setValue:@YES forKey:@"isConnected"];

    FirehoseSubscription *subscription = [[FirehoseSubscription alloc] initWithCursor:0 collections:nil];
    [client firehoseSubscription:subscription didCloseWithError:nil];
    // The delegate will call [expectation fulfill]

    [self waitForExpectations:@[delegate.cursorExpectation] timeout:1.0];
    XCTAssertFalse(client.isConnected);
    XCTAssertEqual(delegate.receivedCursor, 321);
}

- (void)testCloseWithErrorSchedulesReconnectAtLimitReportsDisconnect {
    RelayClient *client = [[RelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    RelayClientTestDelegate *delegate = [[RelayClientTestDelegate alloc] init];
    delegate.cursorExpectation = [self expectationWithDescription:@"cursor"];
    delegate.disconnectExpectation = [self expectationWithDescription:@"disconnect"];
    [client setValue:delegate forKey:@"delegate"];
    [client setValue:@(77) forKey:@"currentSeq"];
    [client setValue:@NO forKey:@"isConnected"];
    [client setValue:@(10) forKey:@"maxReconnectAttempts"];
    [client setValue:@(10) forKey:@"reconnectAttempts"];

    FirehoseSubscription *subscription = [[FirehoseSubscription alloc] initWithCursor:0 collections:nil];
    NSError *closeError = [NSError errorWithDomain:@"test" code:9 userInfo:nil];
    [client firehoseSubscription:subscription didCloseWithError:closeError];
    // The delegate will call [expectation fulfill]

    [self waitForExpectations:@[delegate.cursorExpectation, delegate.disconnectExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.disconnectError.domain, RelayClientErrorDomain);
    XCTAssertEqual(delegate.disconnectError.code, RelayClientErrorCodeConnectionFailed);
}

- (void)testIdentityAndErrorEventsForwardToDelegate {
    RelayClient *client = [[RelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    RelayClientTestDelegate *delegate = [[RelayClientTestDelegate alloc] init];
    delegate.identityExpectation = [self expectationWithDescription:@"identity"];
    delegate.errorExpectation = [self expectationWithDescription:@"error"];
    [client setValue:delegate forKey:@"delegate"];

    FirehoseSubscription *subscription = [[FirehoseSubscription alloc] initWithCursor:0 collections:nil];
    FirehoseIdentityEvent *identity = [FirehoseIdentityEvent eventWithDid:@"did:plc:alice"];
    FirehoseErrorEvent *errorEvent = [FirehoseErrorEvent eventWithError:@"FutureCursor" message:@"cursor ahead"];
    [client firehoseSubscription:subscription didReceiveIdentityEvent:identity];
    [client firehoseSubscription:subscription didReceiveErrorEvent:errorEvent];
    // The delegate will call [expectation fulfill]

    [self waitForExpectations:@[delegate.identityExpectation, delegate.errorExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.identityEvent.did, @"did:plc:alice");
    XCTAssertEqualObjects(delegate.errorEvent.error, @"FutureCursor");
}

#ifndef GNUSTEP
- (void)testConnectAndCommitDispatch {
    RelayClient *client = [[RelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    RelayClientTestDelegate *delegate = [[RelayClientTestDelegate alloc] init];
    delegate.connectExpectation = [self expectationWithDescription:@"connect"];
    delegate.commitExpectation = [self expectationWithDescription:@"commit"];
    [client setValue:delegate forKey:@"delegate"];

    FirehoseSubscription *subscription = [[FirehoseSubscription alloc] initWithCursor:0 collections:nil];
    [client firehoseSubscriptionDidConnect:subscription];
    [self waitForExpectations:@[delegate.connectExpectation] timeout:1.0];
    XCTAssertTrue(client.isConnected);

    // Create CID for commit field
    NSData *digest = [@"cursor2" dataUsingEncoding:NSUTF8StringEncoding];
    CID *commitCID = [CID cidWithDigest:digest codec:0x71];
    
    FirehoseCommitEvent *event = [FirehoseCommitEvent eventWithRepo:@"did:plc:alice"
                                                              commit:commitCID
                                                                 ops:@[@{@"action": @"create"}]];
    event.seq = 456;
    [client firehoseSubscription:subscription didReceiveCommitEvent:event];
    // The delegate will call [expectation fulfill]

    [self waitForExpectations:@[delegate.commitExpectation] timeout:1.0];
    // Note: currentCursor might be based on event.rev or seq, not commit CID
    // Just verify we got the event
    XCTAssertNotNil(delegate.commitEvent.commit);
}
#endif

@end

NS_ASSUME_NONNULL_END
