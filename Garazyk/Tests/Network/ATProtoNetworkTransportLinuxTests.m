// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/ATProtoNetworkTransportLinux.h"

#if !defined(__APPLE__)
#import <sys/socket.h>
#import <unistd.h>
#import <errno.h>

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoNetworkTransportLinuxTests : XCTestCase
@end

@implementation ATProtoNetworkTransportLinuxTests

#ifndef GNUSTEP
- (void)testReceiveBufferedData {
    int fds[2];
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, fds), 0);

    ATProtoNetworkConnectionLinux *conn = [[ATProtoNetworkConnectionLinux alloc] initWithSocket:fds[0] address:@"local"];
    XCTestExpectation *ready = [self expectationWithDescription:@"ready"];
    conn.stateChangedHandler = ^(ATProtoNetworkConnectionState state, NSError * _Nullable error) {
        if (state == ATProtoNetworkConnectionStateReady) {
            [ready fulfill];
        }
    };
    dispatch_queue_t queue = dispatch_queue_create("pds.linux.test", DISPATCH_QUEUE_SERIAL);
    [conn startWithQueue:queue];
    [self waitForExpectations:@[ready] timeout:1.0];

    XCTestExpectation *received = [self expectationWithDescription:@"received"];
    [conn receiveWithMinimumLength:1 maximumLength:5 completion:^(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(data, [@"hello" dataUsingEncoding:NSUTF8StringEncoding]);
        XCTAssertFalse(isComplete);
        [received fulfill];
    }];

    ssize_t sent = send(fds[1], "hello", 5, 0);
    XCTAssertEqual(sent, 5);

    [self waitForExpectations:@[received] timeout:1.0];

    [conn cancel];
    close(fds[1]);
}

- (void)testReceiveWithEOFReturnsPartialData {
    int fds[2];
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, fds), 0);

    ATProtoNetworkConnectionLinux *conn = [[ATProtoNetworkConnectionLinux alloc] initWithSocket:fds[0] address:@"local"];
    dispatch_queue_t queue = dispatch_queue_create("pds.linux.test.eof", DISPATCH_QUEUE_SERIAL);
    [conn startWithQueue:queue];

    XCTestExpectation *received = [self expectationWithDescription:@"received"];
    [conn receiveWithMinimumLength:10 maximumLength:10 completion:^(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(data, [@"bye" dataUsingEncoding:NSUTF8StringEncoding]);
        XCTAssertTrue(isComplete);
        [received fulfill];
    }];

    ssize_t sent = send(fds[1], "bye", 3, 0);
    XCTAssertEqual(sent, 3);
    close(fds[1]);

    [self waitForExpectations:@[received] timeout:1.0];

    [conn cancel];
}

- (void)testOutboundConnectionWithSocketPair {
    int fds[2];
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, fds), 0);

    ATProtoNetworkConnectionLinux *clientConn = [[ATProtoNetworkConnectionLinux alloc] initWithSocket:fds[0] address:@"local"];
    dispatch_queue_t queue = dispatch_queue_create("pds.linux.test.outbound", DISPATCH_QUEUE_SERIAL);
    
    XCTestExpectation *ready = [self expectationWithDescription:@"ready"];
    __block ATProtoNetworkConnectionState lastState = ATProtoNetworkConnectionStatePreparing;
    clientConn.stateChangedHandler = ^(ATProtoNetworkConnectionState state, NSError * _Nullable error) {
        lastState = state;
        if (state == ATProtoNetworkConnectionStateReady) {
            [ready fulfill];
        }
    };
    
    [clientConn startWithQueue:queue];
    [self waitForExpectations:@[ready] timeout:1.0];
    XCTAssertEqual(lastState, ATProtoNetworkConnectionStateReady);
    
    XCTestExpectation *received = [self expectationWithDescription:@"received"];
    [clientConn receiveWithMinimumLength:1 maximumLength:10 completion:^(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(data, [@"test" dataUsingEncoding:NSUTF8StringEncoding]);
        XCTAssertTrue(isComplete);
        [received fulfill];
    }];
    
    ssize_t sent = send(fds[1], "test", 4, 0);
    XCTAssertEqual(sent, 4);
    
    [self waitForExpectations:@[received] timeout:1.0];
    
    [clientConn cancel];
    close(fds[1]);
}

- (void)testOutboundConnectionToLocalhostFails {
    ATProtoNetworkConnectionLinux *conn = [[ATProtoNetworkConnectionLinux alloc] initWithHost:@"127.0.0.1" port:0];
    dispatch_queue_t queue = dispatch_queue_create("pds.linux.test.localhost", DISPATCH_QUEUE_SERIAL);
    
    __block ATProtoNetworkConnectionState finalState = ATProtoNetworkConnectionStatePreparing;
    XCTestExpectation *failed = [self expectationWithDescription:@"failed"];
    conn.stateChangedHandler = ^(ATProtoNetworkConnectionState state, NSError * _Nullable error) {
        finalState = state;
        if (state == ATProtoNetworkConnectionStateFailed) {
            XCTAssertNotNil(error);
            [failed fulfill];
        }
    };
    
    [conn startWithQueue:queue];
    [self waitForExpectations:@[failed] timeout:1.0];
    XCTAssertEqual(finalState, ATProtoNetworkConnectionStateFailed);
}

- (void)testOutboundConnectionToInvalidHost {
    ATProtoNetworkConnectionLinux *conn = [[ATProtoNetworkConnectionLinux alloc] initWithHost:@"invalid.host.that.does.not.exist" port:9999];
    dispatch_queue_t queue = dispatch_queue_create("pds.linux.test.invalid", DISPATCH_QUEUE_SERIAL);
    
    __block ATProtoNetworkConnectionState finalState = ATProtoNetworkConnectionStatePreparing;
    XCTestExpectation *failed = [self expectationWithDescription:@"failed"];
    conn.stateChangedHandler = ^(ATProtoNetworkConnectionState state, NSError * _Nullable error) {
        finalState = state;
        if (state == ATProtoNetworkConnectionStateFailed) {
            XCTAssertNotNil(error);
            [failed fulfill];
        }
    };
    
    [conn startWithQueue:queue];
    [self waitForExpectations:@[failed] timeout:2.0];
    XCTAssertEqual(finalState, ATProtoNetworkConnectionStateFailed);
}

- (void)testSendDataOnConnectedSocket {
    int fds[2];
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, fds), 0);

    ATProtoNetworkConnectionLinux *conn = [[ATProtoNetworkConnectionLinux alloc] initWithSocket:fds[0] address:@"local"];
    dispatch_queue_t queue = dispatch_queue_create("pds.linux.test.send", DISPATCH_QUEUE_SERIAL);
    
    XCTestExpectation *ready = [self expectationWithDescription:@"ready"];
    conn.stateChangedHandler = ^(ATProtoNetworkConnectionState state, NSError * _Nullable error) {
        if (state == ATProtoNetworkConnectionStateReady) {
            [ready fulfill];
        }
    };
    [conn startWithQueue:queue];
    [self waitForExpectations:@[ready] timeout:1.0];
    
    XCTestExpectation *sent = [self expectationWithDescription:@"sent"];
    [conn sendData:[@"hello" dataUsingEncoding:NSUTF8StringEncoding] completion:^(NSError * _Nullable error) {
        XCTAssertNil(error);
        [sent fulfill];
    }];
    
    [self waitForExpectations:@[sent] timeout:1.0];
    
    uint8_t buffer[64];
    ssize_t received = recv(fds[1], buffer, sizeof(buffer), 0);
    XCTAssertEqual(received, 5);
    XCTAssertEqual(memcmp(buffer, "hello", 5), 0);
    
    [conn cancel];
    close(fds[1]);
}

- (void)testCancelCompletesPendingReceiveWithCancelledError {
    int fds[2];
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, fds), 0);

    ATProtoNetworkConnectionLinux *conn = [[ATProtoNetworkConnectionLinux alloc] initWithSocket:fds[0] address:@"local"];
    dispatch_queue_t queue = dispatch_queue_create("pds.linux.test.cancel.receive", DISPATCH_QUEUE_SERIAL);
    [conn startWithQueue:queue];

    XCTestExpectation *cancelled = [self expectationWithDescription:@"cancelled read"];
    [conn receiveWithMinimumLength:64 maximumLength:128 completion:^(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error) {
        XCTAssertNil(data);
        XCTAssertFalse(isComplete);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, ECANCELED);
        [cancelled fulfill];
    }];

    [conn cancel];
    [self waitForExpectations:@[cancelled] timeout:1.0];
    close(fds[1]);
}

- (void)testSendDataAfterCancelReturnsCancelledError {
    int fds[2];
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, fds), 0);

    ATProtoNetworkConnectionLinux *conn = [[ATProtoNetworkConnectionLinux alloc] initWithSocket:fds[0] address:@"local"];
    dispatch_queue_t queue = dispatch_queue_create("pds.linux.test.cancel.send", DISPATCH_QUEUE_SERIAL);
    [conn startWithQueue:queue];
    [conn cancel];

    XCTestExpectation *completion = [self expectationWithDescription:@"send completion"];
    [conn sendData:[@"data" dataUsingEncoding:NSUTF8StringEncoding] completion:^(NSError * _Nullable error) {
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, ECANCELED);
        [completion fulfill];
    }];

    [self waitForExpectations:@[completion] timeout:1.0];
    close(fds[1]);
}

- (void)testListenerFailsForInvalidBindHost {
    ATProtoNetworkListenerLinux *listener =
        [[ATProtoNetworkListenerLinux alloc] initWithHost:@"invalid-bind-host" port:0];
    dispatch_queue_t queue =
        dispatch_queue_create("pds.linux.test.invalid-bind", DISPATCH_QUEUE_SERIAL);
    XCTestExpectation *failed = [self expectationWithDescription:@"listener failed"];
    listener.stateChangedHandler = ^(ATProtoNetworkListenerState state,
                                     NSError *_Nullable error) {
        if (state == ATProtoNetworkListenerStateFailed) {
            XCTAssertNotNil(error);
            XCTAssertEqual(error.code, EADDRNOTAVAIL);
            [failed fulfill];
        }
    };
    [listener startWithQueue:queue];
    [self waitForExpectations:@[ failed ] timeout:1.0];
}
#endif

@end

NS_ASSUME_NONNULL_END

#else

@interface ATProtoNetworkTransportLinuxTests : XCTestCase
@end

@implementation ATProtoNetworkTransportLinuxTests

- (void)testSkippedOnApple {
    XCTSkip(@"Linux-only transport tests.");
}

@end

#endif
