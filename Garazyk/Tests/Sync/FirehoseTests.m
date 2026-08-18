// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/Firehose/Firehose.h"
#import "Sync/WebSocket/WebSocketConnection.h"
#import "Sync/Relay/EventFormatter.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoFirehose (Testing)
- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection didReceiveMessage:(NSData *)message;
- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection didReceiveText:(NSString *)text;
- (void)webSocketConnection:(ATProtoWebSocketConnection *)connection didCloseWithCode:(NSInteger)code reason:(NSString *)reason;
@end

/*!
 @class FirehoseTestCloseRecordingConnection

 @abstract A connection stand-in that records closeWithCode:reason: calls
 instead of touching a real socket/session, so ADR 0039's ingressGate
 refusal path can be verified without opening a network connection.
 */
@interface FirehoseTestCloseRecordingConnection : ATProtoWebSocketConnection
@property (nonatomic, assign) NSInteger closedWithCode;
@property (nonatomic, copy, nullable) NSString *closedWithReason;
@property (nonatomic, assign) NSUInteger closeCallCount;
@end

@implementation FirehoseTestCloseRecordingConnection
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason {
    self.closedWithCode = code;
    self.closedWithReason = reason;
    self.closeCallCount++;
}
@end

@interface FirehoseTestDelegate : NSObject <FirehoseSubscriptionDelegate>
@property (nonatomic, strong) XCTestExpectation *commitExpectation;
@property (nonatomic, strong) XCTestExpectation *identityExpectation;
@property (nonatomic, strong) XCTestExpectation *errorExpectation;
@property (nonatomic, strong) XCTestExpectation *rawExpectation;
@property (nonatomic, strong) XCTestExpectation *closeExpectation;
@property (nonatomic, strong, nullable) ATProtoFirehoseRawEvent *rawEvent;
@property (nonatomic, strong, nullable) ATProtoFirehoseCommitEvent *commitEvent;
@property (nonatomic, strong, nullable) ATProtoFirehoseIdentityEvent *identityEvent;
@property (nonatomic, strong, nullable) ATProtoFirehoseErrorEvent *errorEvent;
@property (nonatomic, strong, nullable) NSError *closeError;
@end

@implementation FirehoseTestDelegate

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveCommitEvent:(ATProtoFirehoseCommitEvent *)event {
    self.commitEvent = event;
    [self.commitExpectation fulfill];
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveIdentityEvent:(ATProtoFirehoseIdentityEvent *)event {
    self.identityEvent = event;
    [self.identityExpectation fulfill];
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveErrorEvent:(ATProtoFirehoseErrorEvent *)event {
    self.errorEvent = event;
    [self.errorExpectation fulfill];
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didReceiveRawEvent:(ATProtoFirehoseRawEvent *)event {
    self.rawEvent = event;
    [self.rawExpectation fulfill];
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription didCloseWithError:(NSError * _Nullable)error {
    self.closeError = error;
    [self.closeExpectation fulfill];
}

@end

@interface FirehoseTests : XCTestCase
@end

@implementation FirehoseTests

#ifndef GNUSTEP
- (void)testCommitEventDispatch {
    ATProtoFirehose *firehose = [[ATProtoFirehose alloc] initWithServerURL:[NSURL URLWithString:@"wss://example.com"]];
    FirehoseTestDelegate *delegate = [[FirehoseTestDelegate alloc] init];
    delegate.commitExpectation = [self expectationWithDescription:@"commit"];
    [firehose subscribeWithCursor:0 collections:nil delegate:delegate];

    // Create commit event using ATProtoEventFormatter for proper XRPC stream frame encoding
    ATProtoEventFormatter *formatter = [[ATProtoEventFormatter alloc] init];
    ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
    event.seq = 1;
    event.repo = @"did:plc:alice";
    event.commit = [ATProtoCID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    event.ops = @[@{@"action": @"create"}];
    event.blobs = @[];
    event.time = @"2024-01-01T00:00:00Z";
    event.rebase = NO;
    event.tooBig = NO;
    event.rev = @"123";

    NSError *error = nil;
    NSData *data = [formatter encodeCommitEvent:event error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(data);

    ATProtoWebSocketConnection *connection = [[ATProtoWebSocketConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose webSocketConnection:connection didReceiveMessage:data];

    [self waitForExpectations:@[delegate.commitExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.commitEvent.repo, @"did:plc:alice");
    XCTAssertNotNil(delegate.commitEvent.commit);
    XCTAssertEqual(delegate.commitEvent.ops.count, 1);
}
#endif

#ifndef GNUSTEP
- (void)testIdentityEventDispatch {
    ATProtoFirehose *firehose = [[ATProtoFirehose alloc] initWithServerURL:[NSURL URLWithString:@"wss://example.com"]];
    FirehoseTestDelegate *delegate = [[FirehoseTestDelegate alloc] init];
    delegate.identityExpectation = [self expectationWithDescription:@"identity"];
    [firehose subscribeWithCursor:0 collections:nil delegate:delegate];

    // Create identity event using ATProtoEventFormatter for proper XRPC stream frame encoding
    ATProtoEventFormatter *formatter = [[ATProtoEventFormatter alloc] init];
    ATProtoFirehoseIdentityEvent *event = [[ATProtoFirehoseIdentityEvent alloc] init];
    event.seq = 1;
    event.did = @"did:plc:bob";
    event.time = @"2024-01-01T00:00:00Z";

    NSError *error = nil;
    NSData *data = [formatter encodeIdentityEvent:event error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(data);

    ATProtoWebSocketConnection *connection = [[ATProtoWebSocketConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose webSocketConnection:connection didReceiveMessage:data];

    [self waitForExpectations:@[delegate.identityExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.identityEvent.did, @"did:plc:bob");
}
#endif

#ifndef GNUSTEP
- (void)testErrorEventDispatch {
    ATProtoFirehose *firehose = [[ATProtoFirehose alloc] initWithServerURL:[NSURL URLWithString:@"wss://example.com"]];
    FirehoseTestDelegate *delegate = [[FirehoseTestDelegate alloc] init];
    delegate.errorExpectation = [self expectationWithDescription:@"error"];
    [firehose subscribeWithCursor:0 collections:nil delegate:delegate];

    // Create error frame using ATProtoEventFormatter
    ATProtoEventFormatter *formatter = [[ATProtoEventFormatter alloc] init];
    ATProtoFirehoseErrorEvent *event = [[ATProtoFirehoseErrorEvent alloc] init];
    event.error = @"ServerError";
    event.message = @"oops";

    NSError *error = nil;
    NSData *data = [formatter encodeErrorEvent:event error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(data);

    ATProtoWebSocketConnection *connection = [[ATProtoWebSocketConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose webSocketConnection:connection didReceiveMessage:data];

    [self waitForExpectations:@[delegate.errorExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.errorEvent.message, @"oops");
}
#endif

- (void)testUnknownWellFormedEventIsDeliveredByteForByte {
    ATProtoFirehose *firehose = [[ATProtoFirehose alloc] initWithServerURL:[NSURL URLWithString:@"wss://example.com"]];
    FirehoseTestDelegate *delegate = [[FirehoseTestDelegate alloc] init];
    delegate.rawExpectation = [self expectationWithDescription:@"raw event"];
    [firehose subscribeWithCursor:0 collections:nil delegate:delegate];

    ATProtoEventFormatter *formatter = [[ATProtoEventFormatter alloc] init];
    NSError *error = nil;
    NSData *frame = [formatter encodeStreamEventWithType:@"#futureEvent"
                                                  payload:@{@"x": @1}
                                                    error:&error];
    XCTAssertNotNil(frame);
    XCTAssertNil(error);

    ATProtoWebSocketConnection *connection = [[ATProtoWebSocketConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose webSocketConnection:connection didReceiveMessage:frame];
    [self waitForExpectations:@[delegate.rawExpectation] timeout:1.0];

    XCTAssertEqualObjects(delegate.rawEvent.messageType, @"#futureEvent");
    XCTAssertEqualObjects(delegate.rawEvent.payload[@"x"], @1);
    XCTAssertEqualObjects(delegate.rawEvent.frameData, frame);
}

- (void)testCloseIncludesCodeAndReasonInErrorUserInfo {
    ATProtoFirehose *firehose = [[ATProtoFirehose alloc] initWithServerURL:[NSURL URLWithString:@"wss://example.com"]];
    FirehoseTestDelegate *delegate = [[FirehoseTestDelegate alloc] init];
    delegate.closeExpectation = [self expectationWithDescription:@"close"];
    [firehose subscribeWithCursor:0 collections:nil delegate:delegate];

    ATProtoWebSocketConnection *connection = [[ATProtoWebSocketConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose webSocketConnection:connection didCloseWithCode:1009 reason:@"Outbound queue limit exceeded"];
    [self waitForExpectations:@[delegate.closeExpectation] timeout:1.0];

    XCTAssertNotNil(delegate.closeError);
    XCTAssertEqualObjects(delegate.closeError.userInfo[FirehoseCloseCodeKey], @1009);
    XCTAssertEqualObjects(delegate.closeError.userInfo[FirehoseCloseReasonKey], @"Outbound queue limit exceeded");
    XCTAssertTrue(FirehoseErrorIsBackpressureClose(delegate.closeError));
}

#ifndef GNUSTEP
// ADR 0039, section 1/3: an installed ingressGate that refuses a Commit
// frame must close the connection with a backpressure-classified code and
// reason instead of delivering the event.
- (void)testIngressGateRefusalClosesConnectionInsteadOfDelivering {
    ATProtoFirehose *firehose = [[ATProtoFirehose alloc] initWithServerURL:[NSURL URLWithString:@"wss://example.com"]];
    FirehoseTestDelegate *delegate = [[FirehoseTestDelegate alloc] init];
    // Deliberately no commitExpectation: the event must never reach the delegate.
    [firehose subscribeWithCursor:0 collections:nil delegate:delegate];

    FirehoseTestCloseRecordingConnection *connection =
        [[FirehoseTestCloseRecordingConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose setValue:connection forKey:@"connection"];

    __block BOOL gateInvoked = NO;
    firehose.ingressGate = ^BOOL(id event, FirehoseEventKind kind) {
        gateInvoked = YES;
        XCTAssertEqual(kind, FirehoseEventKindCommit);
        XCTAssertTrue([event isKindOfClass:[ATProtoFirehoseCommitEvent class]]);
        return NO;
    };

    ATProtoEventFormatter *formatter = [[ATProtoEventFormatter alloc] init];
    ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
    event.seq = 1;
    event.repo = @"did:plc:alice";
    event.commit = [ATProtoCID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    event.ops = @[@{@"action": @"create"}];
    event.blobs = @[];
    event.time = @"2024-01-01T00:00:00Z";
    event.rebase = NO;
    event.tooBig = NO;
    event.rev = @"123";

    NSError *error = nil;
    NSData *data = [formatter encodeCommitEvent:event error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(data);

    [firehose webSocketConnection:connection didReceiveMessage:data];

    XCTAssertTrue(gateInvoked);
    XCTAssertNil(delegate.commitEvent);
    XCTAssertEqual(connection.closeCallCount, (NSUInteger)1);
    // Must match the close vocabulary FirehoseErrorIsBackpressureClose
    // recognizes (code 1008/1009, or "ConsumerTooSlow"/"Outbound queue").
    XCTAssertTrue(connection.closedWithCode == 1008 || connection.closedWithCode == 1009);
    XCTAssertTrue([connection.closedWithReason rangeOfString:@"ConsumerTooSlow" options:NSCaseInsensitiveSearch].location != NSNotFound);
}

// ADR 0039, section 1: a gate that admits the frame must deliver it exactly
// as the nil-gate path does.
- (void)testIngressGateAdmissionDeliversEventNormally {
    ATProtoFirehose *firehose = [[ATProtoFirehose alloc] initWithServerURL:[NSURL URLWithString:@"wss://example.com"]];
    FirehoseTestDelegate *delegate = [[FirehoseTestDelegate alloc] init];
    delegate.commitExpectation = [self expectationWithDescription:@"commit"];
    [firehose subscribeWithCursor:0 collections:nil delegate:delegate];

    FirehoseTestCloseRecordingConnection *connection =
        [[FirehoseTestCloseRecordingConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose setValue:connection forKey:@"connection"];

    __block BOOL gateInvoked = NO;
    firehose.ingressGate = ^BOOL(id event, FirehoseEventKind kind) {
        gateInvoked = YES;
        return YES;
    };

    ATProtoEventFormatter *formatter = [[ATProtoEventFormatter alloc] init];
    ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
    event.seq = 2;
    event.repo = @"did:plc:bob";
    event.commit = [ATProtoCID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    event.ops = @[@{@"action": @"create"}];
    event.blobs = @[];
    event.time = @"2024-01-01T00:00:00Z";
    event.rebase = NO;
    event.tooBig = NO;
    event.rev = @"124";

    NSError *error = nil;
    NSData *data = [formatter encodeCommitEvent:event error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(data);

    [firehose webSocketConnection:connection didReceiveMessage:data];

    [self waitForExpectations:@[delegate.commitExpectation] timeout:1.0];
    XCTAssertTrue(gateInvoked);
    XCTAssertEqualObjects(delegate.commitEvent.repo, @"did:plc:bob");
    XCTAssertEqual(connection.closeCallCount, (NSUInteger)0);
}
#endif

#ifndef GNUSTEP
// ADR 0039, section 1: #info and error frames carry no wireFrameLength and
// no backlog cost, so they are exempt from ingressGate even when the gate
// would refuse everything else.
- (void)testIngressGateDoesNotApplyToErrorFrames {
    ATProtoFirehose *firehose = [[ATProtoFirehose alloc] initWithServerURL:[NSURL URLWithString:@"wss://example.com"]];
    FirehoseTestDelegate *delegate = [[FirehoseTestDelegate alloc] init];
    delegate.errorExpectation = [self expectationWithDescription:@"error"];
    [firehose subscribeWithCursor:0 collections:nil delegate:delegate];

    FirehoseTestCloseRecordingConnection *connection =
        [[FirehoseTestCloseRecordingConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose setValue:connection forKey:@"connection"];

    firehose.ingressGate = ^BOOL(id event, FirehoseEventKind kind) {
        XCTFail(@"ingressGate must not be consulted for error frames");
        return NO;
    };

    ATProtoEventFormatter *formatter = [[ATProtoEventFormatter alloc] init];
    ATProtoFirehoseErrorEvent *event = [[ATProtoFirehoseErrorEvent alloc] init];
    event.error = @"ServerError";
    event.message = @"oops";

    NSError *error = nil;
    NSData *data = [formatter encodeErrorEvent:event error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(data);

    [firehose webSocketConnection:connection didReceiveMessage:data];

    [self waitForExpectations:@[delegate.errorExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.errorEvent.message, @"oops");
    XCTAssertEqual(connection.closeCallCount, (NSUInteger)0);
}
#endif

- (void)testBackpressureCloseHelperRecognizesConsumerTooSlow {
    NSError *error = [NSError errorWithDomain:FirehoseErrorDomain
                                         code:FirehoseErrorCodeSubscriptionClosed
                                     userInfo:@{
        FirehoseCloseCodeKey: @1008,
        FirehoseCloseReasonKey: @"ConsumerTooSlow",
    }];
    XCTAssertTrue(FirehoseErrorIsBackpressureClose(error));
    XCTAssertFalse(FirehoseErrorIsBackpressureClose(nil));
    XCTAssertFalse(FirehoseErrorIsBackpressureClose(
        [NSError errorWithDomain:FirehoseErrorDomain
                            code:FirehoseErrorCodeSubscriptionClosed
                        userInfo:@{FirehoseCloseCodeKey: @1001, FirehoseCloseReasonKey: @"Going away"}]));
}

@end

NS_ASSUME_NONNULL_END
