#import <XCTest/XCTest.h>
#import "Sync/WebSocket/PDSWebSocketServer.h"
#import "Sync/WebSocket/PDSWebSocketTransport.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

@class MockWebSocketTransport;

@interface PDSWebSocketServerTests : XCTestCase
@property (nonatomic, strong) PDSWebSocketServer *server;
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

@implementation PDSWebSocketServerTests

- (void)setUp {
    [super setUp];
    self.server = [[PDSWebSocketServer alloc] initWithPort:0];
}

- (void)tearDown {
    [self.server stop];
    self.server = nil;
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

    NSError *error2 = nil;
    PDSWebSocketServer *server2 = [[PDSWebSocketServer alloc] initWithPort:self.server.port];
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

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        int sock = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons((uint16_t)self.server.port);
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

        if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
            close(sock);
        }
    });

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
