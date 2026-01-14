#import <XCTest/XCTest.h>
#import "Network/PDSNetworkTransportLinux.h"

@interface PDSNetworkTransportTests : XCTestCase
@end

@implementation PDSNetworkTransportTests

- (void)testStartWithQueue {
#if defined(__APPLE__)
    XCTSkip(@"PDSNetworkListenerLinux requires Linux socket permissions on macOS.");
#endif
    // Note: This test is designed to fail initially according to the TDD plan
    // We explicitly use the Linux implementation even on Mac for testing purposes
    PDSNetworkListenerLinux *listener = [[PDSNetworkListenerLinux alloc] initWithPort:8080];
    XCTAssertNotNil(listener, @"Listener should be created");
    
    dispatch_queue_t queue = dispatch_queue_create("com.atproto.network.test", DISPATCH_QUEUE_SERIAL);
    
    __block BOOL stateCalled = NO;
    __block PDSNetworkListenerState finalState = PDSNetworkListenerStateWaiting;
    __block NSError *stateError = nil;
    
    listener.stateChangedHandler = ^(PDSNetworkListenerState state, NSError *error) {
        stateCalled = YES;
        finalState = state;
        stateError = error;
        if (error) {
            NSLog(@"PDSNetworkListenerLinux state error: %@", error);
        }
    };
    
    [listener startWithQueue:queue];
    
    // In the new implementation, it should succeed
    XCTAssertTrue(stateCalled, @"State changed handler should be called");
    XCTAssertEqual(finalState, PDSNetworkListenerStateReady, @"Should succeed after implementation");
    
    [listener cancel];
}

@end
