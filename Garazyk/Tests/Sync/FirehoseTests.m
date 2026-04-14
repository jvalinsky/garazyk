#import <XCTest/XCTest.h>
#import "Sync/Firehose.h"
#import "Sync/WebSocketConnection.h"
#import "Core/ATProtoDagCBOR.h"

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

    NSDictionary *message = @{
        @"kind": @"commit",
        @"seq": @(1),
        @"repo": @"did:plc:alice",
        @"commit": @"bafycommit",
        @"ops": @[@{@"action": @"create"}],
        @"blobs": @[@"bafyblob"]
    };
    NSData *data = [ATProtoDagCBOR encodeObject:message error:nil];
    WebSocketConnection *connection = [[WebSocketConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose webSocketConnection:connection didReceiveMessage:data];
    // The delegate will call [expectation fulfill]

    [self waitForExpectations:@[delegate.commitExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.commitEvent.repo, @"did:plc:alice");
    XCTAssertEqualObjects(delegate.commitEvent.commit, @"bafycommit");
    // Removed: 'prevCid' field no longer exists
    XCTAssertEqual(delegate.commitEvent.ops.count, 1);
}
#endif

#ifndef GNUSTEP
- (void)testIdentityEventDispatch {
    Firehose *firehose = [[Firehose alloc] initWithServerURL:[NSURL URLWithString:@"wss://example.com"]];
    FirehoseTestDelegate *delegate = [[FirehoseTestDelegate alloc] init];
    delegate.identityExpectation = [self expectationWithDescription:@"identity"];
    [firehose subscribeWithCursor:0 collections:nil delegate:delegate];

    NSDictionary *message = @{
        @"kind": @"identity",
        @"did": @"did:plc:bob"
    };
    NSData *data = [ATProtoDagCBOR encodeObject:message error:nil];
    WebSocketConnection *connection = [[WebSocketConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose webSocketConnection:connection didReceiveMessage:data];
    // The delegate will call [expectation fulfill]

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

    NSDictionary *message = @{
        @"kind": @"error",
        @"message": @"oops"
    };
    NSData *data = [ATProtoDagCBOR encodeObject:message error:nil];
    WebSocketConnection *connection = [[WebSocketConnection alloc] initWithHost:@"example.com" port:443 path:@"/"];
    [firehose webSocketConnection:connection didReceiveMessage:data];
    // The delegate will call [expectation fulfill]

    [self waitForExpectations:@[delegate.errorExpectation] timeout:1.0];
    XCTAssertEqualObjects(delegate.errorEvent.message, @"oops");
}
#endif

@end

NS_ASSUME_NONNULL_END
