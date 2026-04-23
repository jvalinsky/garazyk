#import <XCTest/XCTest.h>
#import "Sync/Firehose/Firehose.h"
#import "Sync/WebSocket/WebSocketConnection.h"
#import "Sync/Relay/EventFormatter.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"

NS_ASSUME_NONNULL_BEGIN

@interface Firehose (Testing)
- (void)webSocketConnection:(WebSocketConnection *)connection didReceiveMessage:(NSData *)message;
- (void)webSocketConnection:(WebSocketConnection *)connection didReceiveText:(NSString *)text;
@end

@interface FirehoseTestDelegate : NSObject <FirehoseSubscriptionDelegate>
@property (nonatomic, strong) XCTestExpectation *commitExpectation;
@property (nonatomic, strong) XCTestExpectation *identityExpectation;
@property (nonatomic, strong) XCTestExpectation *errorExpectation;
@property (nonatomic, strong, nullable) FirehoseCommitEvent *commitEvent;
@property (nonatomic, strong, nullable) FirehoseIdentityEvent *identityEvent;
@property (nonatomic, strong, nullable) FirehoseErrorEvent *errorEvent;
@end

@implementation FirehoseTestDelegate

- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveCommitEvent:(FirehoseCommitEvent *)event {
    self.commitEvent = event;
    [self.commitExpectation fulfill];
}

- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveIdentityEvent:(FirehoseIdentityEvent *)event {
    self.identityEvent = event;
    [self.identityExpectation fulfill];
}

- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveErrorEvent:(FirehoseErrorEvent *)event {
    self.errorEvent = event;
    [self.errorExpectation fulfill];
}

@end

@interface FirehoseTests : XCTestCase
@end

@implementation FirehoseTests

#ifndef GNUSTEP
- (void)testCommitEventDispatch {
    Firehose *firehose = [[Firehose alloc] initWithServerURL:[NSURL URLWithString:@"wss://example.com"]];
    FirehoseTestDelegate *delegate = [[FirehoseTestDelegate alloc] init];
    delegate.commitExpectation = [self expectationWithDescription:@"commit"];
    [firehose subscribeWithCursor:0 collections:nil delegate:delegate];

    // Create commit event using EventFormatter for proper XRPC stream frame encoding
    EventFormatter *formatter = [[EventFormatter alloc] init];
    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.seq = 1;
    event.repo = @"did:plc:alice";
    event.commit = [CID cidFromString:@"bafyreibv3zhl3h7v6yyh5w5g3l5g3l5g3l5g3l5g3l5g3l5g3l5g3l5g3l5g3l5"];
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

    WebSocketConnection *connection = [[WebSocketConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose webSocketConnection:connection didReceiveMessage:data];

    [self waitForExpectations:@[delegate.commitExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.commitEvent.repo, @"did:plc:alice");
    XCTAssertNotNil(delegate.commitEvent.commit);
    XCTAssertEqual(delegate.commitEvent.ops.count, 1);
}
#endif

#ifndef GNUSTEP
- (void)testIdentityEventDispatch {
    Firehose *firehose = [[Firehose alloc] initWithServerURL:[NSURL URLWithString:@"wss://example.com"]];
    FirehoseTestDelegate *delegate = [[FirehoseTestDelegate alloc] init];
    delegate.identityExpectation = [self expectationWithDescription:@"identity"];
    [firehose subscribeWithCursor:0 collections:nil delegate:delegate];

    // Create identity event using EventFormatter for proper XRPC stream frame encoding
    EventFormatter *formatter = [[EventFormatter alloc] init];
    FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
    event.seq = 1;
    event.did = @"did:plc:bob";
    event.time = @"2024-01-01T00:00:00Z";

    NSError *error = nil;
    NSData *data = [formatter encodeIdentityEvent:event error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(data);

    WebSocketConnection *connection = [[WebSocketConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose webSocketConnection:connection didReceiveMessage:data];

    [self waitForExpectations:@[delegate.identityExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.identityEvent.did, @"did:plc:bob");
}
#endif

#ifndef GNUSTEP
- (void)testErrorEventDispatch {
    Firehose *firehose = [[Firehose alloc] initWithServerURL:[NSURL URLWithString:@"wss://example.com"]];
    FirehoseTestDelegate *delegate = [[FirehoseTestDelegate alloc] init];
    delegate.errorExpectation = [self expectationWithDescription:@"error"];
    [firehose subscribeWithCursor:0 collections:nil delegate:delegate];

    // Create error frame using EventFormatter
    EventFormatter *formatter = [[EventFormatter alloc] init];
    FirehoseErrorEvent *event = [[FirehoseErrorEvent alloc] init];
    event.error = @"ServerError";
    event.message = @"oops";

    NSError *error = nil;
    NSData *data = [formatter encodeErrorEvent:event error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(data);

    WebSocketConnection *connection = [[WebSocketConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose webSocketConnection:connection didReceiveMessage:data];

    [self waitForExpectations:@[delegate.errorExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.errorEvent.message, @"oops");
}
#endif

@end

NS_ASSUME_NONNULL_END
