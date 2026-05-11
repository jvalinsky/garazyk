// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/WebSocket/PDSWebSocketServer.h"
#import "Sync/WebSocket/PDSWebSocketTransport.h"
#import "Network/PDSNetworkTransport.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

@class MockWebSocketTransport;
@class MockNetworkListener;

@interface PDSWebSocketServerTests : XCTestCase
@property (nonatomic, strong) PDSWebSocketServer *server;
@property (nonatomic, strong) MockNetworkListener *listener;
@end

@interface MockWebSocketTransport : NSObject <PDSWebSocketTransport>
@property (nonatomic, copy, nullable) void (^messageHandler)(NSData *data);
@property (nonatomic, copy, nullable) void (^closeHandler)(NSInteger code, NSString *reason);
@property (nonatomic, copy, nullable) void (^errorHandler)(NSError *error);
@end

@implementation MockWebSocketTransport
- (void)sendMessage:(NSData *)data completion:(void (^)(NSError * _Nullable))completion {
    if (completion) completion(nil);
}
- (void)closeWithCode:(NSInteger)code reason:(nullable NSString *)reason completion:(void (^)(NSError * _Nullable))completion {
    if (completion) completion(nil);
}
- (void)start {
}
@end

@interface MockWebSocketServerNetworkConnection : NSObject <PDSNetworkConnection>
@property (nonatomic, copy, nullable) void (^stateChangedHandler)(PDSNetworkConnectionState state, NSError *error);
@end

@implementation MockWebSocketServerNetworkConnection
- (NSString *)remoteAddress { return @"127.0.0.1"; }
- (void)cancel {}
- (void)startWithQueue:(dispatch_queue_t)queue {
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkConnectionStateReady, nil);
    }
}
- (void)sendData:(NSData *)data completion:(void (^)(NSError * _Nullable))completion {
    if (completion) completion(nil);
}
- (void)receiveWithMinimumLength:(NSUInteger)minLength
                  maximumLength:(NSUInteger)maxLength
                     completion:(void (^)(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error))completion {
    if (completion) completion(nil, YES, nil);
}
@end

@interface MockNetworkListener : NSObject <PDSNetworkListener>
@property (nonatomic, copy, nullable) void (^stateChangedHandler)(PDSNetworkListenerState state, NSError *error);
@property (nonatomic, copy, nullable) void (^newConnectionHandler)(id<PDSNetworkConnection> connection);
@property (nonatomic, assign) NSUInteger port;
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation MockNetworkListener
- (instancetype)init {
    self = [super init];
    if (self) {
        _port = 49152;
    }
    return self;
}
- (void)startWithQueue:(dispatch_queue_t)queue {
    dispatch_async(queue, ^{
        if (self.stateChangedHandler) {
            self.stateChangedHandler(PDSNetworkListenerStateReady, nil);
        }
    });
}
- (void)cancel {
    self.cancelled = YES;
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkListenerStateCancelled, nil);
    }
}
- (void)simulateConnection {
    if (self.newConnectionHandler) {
        self.newConnectionHandler([[MockWebSocketServerNetworkConnection alloc] init]);
    }
}
@end

@implementation PDSWebSocketServerTests

- (void)setUp {
    [super setUp];
    self.listener = [[MockNetworkListener alloc] init];
    __weak typeof(self) weakSelf = self;
    self.server = [[PDSWebSocketServer alloc] initWithPort:0 listenerFactory:^id<PDSNetworkListener> _Nullable(NSUInteger port) {
        return weakSelf.listener;
    }];
}

- (void)tearDown {
    [self.server stop];
    self.server = nil;
    self.listener = nil;
    [super tearDown];
}

- (void)testServerStartsAndPortIsNonzero {
    NSError *error = nil;
    BOOL success = [self.server startWithError:&error];

    XCTAssertTrue(success);
    XCTAssertNil(error);

    NSPredicate *portPredicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [(PDSWebSocketServer *)evaluatedObject port] > 0;
    }];
    [self expectationForPredicate:portPredicate evaluatedWithObject:self.server handler:nil];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testServerStopCancelsListener {
    NSError *error1 = nil;
    BOOL success1 = [self.server startWithError:&error1];
    XCTAssertTrue(success1);

    [self.server stop];
    XCTAssertTrue(self.listener.cancelled);

    NSError *error2 = nil;
    MockNetworkListener *listener2 = [[MockNetworkListener alloc] init];
    PDSWebSocketServer *server2 = [[PDSWebSocketServer alloc] initWithPort:self.server.port listenerFactory:^id<PDSNetworkListener> _Nullable(NSUInteger port) {
        return listener2;
    }];
    BOOL success2 = [server2 startWithError:&error2];

    if (success2) {
        [server2 stop];
    }
}

- (void)testConnectionHandlerCalledOnNewConnection {
    XCTestExpectation *connectionExpectation = [self expectationWithDescription:@"Connection handler called"];

    self.server.connectionHandler = ^(id<PDSWebSocketTransport> transport) {
        XCTAssertNotNil(transport);
        [connectionExpectation fulfill];
    };

    NSError *error = nil;
    BOOL success = [self.server startWithError:&error];
    XCTAssertTrue(success);

    [self.listener simulateConnection];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testDelegateNewTransportRoutesToConnectionHandler {
    XCTestExpectation *handlerExpectation = [self expectationWithDescription:@"Handler called"];

    self.server.connectionHandler = ^(id<PDSWebSocketTransport> transport) {
        XCTAssertNotNil(transport);
        [handlerExpectation fulfill];
    };

    MockWebSocketTransport *mockTransport = [[MockWebSocketTransport alloc] init];
    [self.server delegateNewTransport:mockTransport forPath:@"/ws"];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testStartFailsWithInvalidPort {
#if !defined(__APPLE__)
    PDSWebSocketServer *serverRootPort = [[PDSWebSocketServer alloc] initWithPort:1];
    NSError *error = nil;
    BOOL success = [serverRootPort startWithError:&error];

    if (geteuid() != 0) {
        XCTAssertFalse(success);
        XCTAssertNotNil(error);
    }
#endif
}

@end
