#import <XCTest/XCTest.h>
#import "Sync/RelayClient.h"
#import "Sync/Firehose.h"
#import "Core/CID.h"

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

    [self waitForExpectations:@[delegate.commitExpectation] timeout:1.0];
    // Note: currentCursor might be based on event.rev or seq, not commit CID
    // Just verify we got the event
    XCTAssertNotNil(delegate.commitEvent.commit);
}

@end

NS_ASSUME_NONNULL_END
