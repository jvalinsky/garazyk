#import <XCTest/XCTest.h>
#import "Network/PDSNetworkTransportLinux.h"

#if !defined(__APPLE__)
#import <sys/socket.h>
#import <unistd.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSNetworkTransportLinuxTests : XCTestCase
@end

@implementation PDSNetworkTransportLinuxTests

- (void)testReceiveBufferedData {
    int fds[2];
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, fds), 0);

    PDSNetworkConnectionLinux *conn = [[PDSNetworkConnectionLinux alloc] initWithSocket:fds[0] address:@"local"];
    XCTestExpectation *ready = [self expectationWithDescription:@"ready"];
    conn.stateChangedHandler = ^(PDSNetworkConnectionState state, NSError * _Nullable error) {
        if (state == PDSNetworkConnectionStateReady) {
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

    PDSNetworkConnectionLinux *conn = [[PDSNetworkConnectionLinux alloc] initWithSocket:fds[0] address:@"local"];
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

@end

NS_ASSUME_NONNULL_END

#else

@interface PDSNetworkTransportLinuxTests : XCTestCase
@end

@implementation PDSNetworkTransportLinuxTests

- (void)testSkippedOnApple {
    XCTSkip(@"Linux-only transport tests.");
}

@end

#endif
