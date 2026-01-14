#import <XCTest/XCTest.h>
#import "Sync/RelayClient.h"
#import "Sync/Firehose.h"

NS_ASSUME_NONNULL_BEGIN

@interface RelayClient (Testing)
- (void)firehoseSubscriptionDidConnect:(FirehoseSubscription *)subscription;
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didReceiveCommitEvent:(FirehoseCommitEvent *)event;
@end

@interface RelayClientTestDelegate : NSObject <RelayClientDelegate>
@property (nonatomic, strong) XCTestExpectation *connectExpectation;
@property (nonatomic, strong) XCTestExpectation *commitExpectation;
@property (nonatomic, strong, nullable) FirehoseCommitEvent *commitEvent;
@end

@implementation RelayClientTestDelegate

- (void)relayClientDidConnect:(RelayClient *)client {
    [self.connectExpectation fulfill];
}

- (void)relayClient:(RelayClient *)client didReceiveCommitEvent:(FirehoseCommitEvent *)event {
    self.commitEvent = event;
    [self.commitExpectation fulfill];
}

@end

@interface RelayClientTests : XCTestCase
@end

@implementation RelayClientTests

- (BOOL)waitForCursorInClient:(RelayClient *)client repo:(NSString *)repo expected:(NSString *)expected {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
        NSString *cursor = [client getStoredCursorForRepo:repo];
        if ([cursor isEqualToString:expected]) {
            return YES;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return NO;
}

- (void)testStoreAndGetCursor {
    RelayClient *client = [[RelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    [client storeCursor:@"cursor1" forRepo:@"did:plc:alice"];
    XCTAssertTrue([self waitForCursorInClient:client repo:@"did:plc:alice" expected:@"cursor1"]);
}

- (void)testConnectAndCommitDispatch {
    RelayClient *client = [[RelayClient alloc] initWithServerURL:[NSURL URLWithString:@"https://example.com"]];
    RelayClientTestDelegate *delegate = [[RelayClientTestDelegate alloc] init];
    delegate.connectExpectation = [self expectationWithDescription:@"connect"];
    delegate.commitExpectation = [self expectationWithDescription:@"commit"];
    [client setValue:delegate forKey:@"delegate"];

    FirehoseSubscription *subscription = [[FirehoseSubscription alloc] initWithCursor:nil collections:nil];
    [client firehoseSubscriptionDidConnect:subscription];
    [self waitForExpectations:@[delegate.connectExpectation] timeout:1.0];
    XCTAssertTrue(client.isConnected);

    FirehoseCommitEvent *event = [FirehoseCommitEvent eventWithRepo:@"did:plc:alice"
                                                             commit:@"cursor2"
                                                                ops:@[@{@"action": @"create"}]];
    [client firehoseSubscription:subscription didReceiveCommitEvent:event];

    [self waitForExpectations:@[delegate.commitExpectation] timeout:1.0];
    XCTAssertEqualObjects(client.currentCursor, @"cursor2");
    XCTAssertEqualObjects(delegate.commitEvent.commit, @"cursor2");
}

@end

NS_ASSUME_NONNULL_END
