// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/ATProtoNetworkTransportLinux.h"

@interface ATProtoNetworkTransportTests : XCTestCase
@end

@implementation ATProtoNetworkTransportTests

- (void)testStartWithQueue {
#if defined(__APPLE__)
    XCTSkip(@"ATProtoNetworkListenerLinux requires Linux socket permissions on macOS.");
#endif
    // Note: This test is designed to fail initially according to the TDD plan
    // We explicitly use the Linux implementation even on Mac for testing purposes
    ATProtoNetworkListenerLinux *listener = [[ATProtoNetworkListenerLinux alloc] initWithPort:8080];
    XCTAssertNotNil(listener, @"Listener should be created");
    
    dispatch_queue_t queue = dispatch_queue_create("com.atproto.network.test", DISPATCH_QUEUE_SERIAL);
    
    __block BOOL stateCalled = NO;
    __block ATProtoNetworkListenerState finalState = ATProtoNetworkListenerStateWaiting;
    __block NSError *stateError = nil;
    
    listener.stateChangedHandler = ^(ATProtoNetworkListenerState state, NSError *error) {
        stateCalled = YES;
        finalState = state;
        stateError = error;
        if (error) {
            NSLog(@"ATProtoNetworkListenerLinux state error: %@", error);
        }
    };
    
    [listener startWithQueue:queue];
    
    // In the new implementation, it should succeed
    XCTAssertTrue(stateCalled, @"State changed handler should be called");
    XCTAssertEqual(finalState, ATProtoNetworkListenerStateReady, @"Should succeed after implementation");
    
    [listener cancel];
}

@end
