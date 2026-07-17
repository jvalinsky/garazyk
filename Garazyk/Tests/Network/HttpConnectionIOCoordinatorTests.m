// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpConnectionIOCoordinator.h"
#import "Network/HttpProtocolDriver.h"
#import "Network/HttpResponseSender.h"
#import "Network/HttpRequest.h"
#import "Network/ATProtoNetworkTransport.h"

@interface MockIOConnection : NSObject <ATProtoNetworkConnection>
@property (nonatomic, strong) NSMutableData *sentData;
@property (nonatomic, copy) void (^receiveCompletion)(NSData *data, BOOL isComplete, NSError *error);
@property (nonatomic, strong) NSMutableArray<NSData *> *pendingData;
@property (nonatomic, assign) BOOL isEOF;
@property (nonatomic, assign) BOOL isCancelled;
@property (nonatomic, assign) NSUInteger cancelCount;
- (void)injectReceiveData:(NSData *)data;
- (void)injectReceiveComplete;
@end

@implementation MockIOConnection

- (instancetype)init {
    self = [super init];
    if (self) {
        self.sentData = [NSMutableData data];
        self.pendingData = [NSMutableArray array];
        self.isEOF = NO;
        self.isCancelled = NO;
        self.cancelCount = 0;
    }
    return self;
}

- (void)sendData:(NSData *)data completion:(void (^)(NSError * _Nullable))completion {
    [self.sentData appendData:data];
    if (completion) {
        completion(nil);
    }
}

- (void)receiveWithMinimumLength:(NSUInteger)minLength
                  maximumLength:(NSUInteger)maxLength
                     completion:(void (^)(NSData * _Nullable, BOOL, NSError * _Nullable))completion {
    if (self.pendingData.count > 0) {
        NSData *data = self.pendingData.firstObject;
        [self.pendingData removeObjectAtIndex:0];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(data, NO, nil);
        });
    } else if (self.isEOF) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, YES, nil);
        });
    } else {
        self.receiveCompletion = completion;
    }
}

- (void)cancel {
    self.isCancelled = YES;
    self.cancelCount += 1;
    self.receiveCompletion = nil;
    [self.pendingData removeAllObjects];
}

- (void)startWithQueue:(dispatch_queue_t)queue {
}

- (void)injectReceiveData:(NSData *)data {
    if (self.receiveCompletion) {
        void (^completion)(NSData *, BOOL, NSError *) = self.receiveCompletion;
        self.receiveCompletion = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(data, NO, nil);
        });
    } else {
        [self.pendingData addObject:data];
    }
}

- (void)injectReceiveComplete {
    if (self.receiveCompletion) {
        void (^completion)(NSData *, BOOL, NSError *) = self.receiveCompletion;
        self.receiveCompletion = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, YES, nil);
        });
    } else {
        self.isEOF = YES;
    }
}

- (nullable NSString *)remoteAddress {
    return @"127.0.0.1";
}

@end

@interface HttpConnectionIOCoordinatorTests : XCTestCase
@property (nonatomic, strong) HttpConnectionIOCoordinator *coordinator;
@property (nonatomic, strong) MockIOConnection *mockConnection;
@property (nonatomic, strong) HttpProtocolDriver *driver;
@property (nonatomic, strong) HttpResponseSender *sender;
@end

@implementation HttpConnectionIOCoordinatorTests

- (void)setUp {
    [super setUp];
    self.mockConnection = [[MockIOConnection alloc] init];
    self.driver = [[HttpProtocolDriver alloc] init];
    self.sender = [[HttpResponseSender alloc] init];
    self.coordinator = [[HttpConnectionIOCoordinator alloc] initWithConnection:self.mockConnection
                                                                      protocol:self.driver
                                                                  responseSender:self.sender];
}

- (void)tearDown {
    [self.coordinator close];
    self.coordinator = nil;
    self.mockConnection = nil;
    self.driver = nil;
    self.sender = nil;
    [super tearDown];
}

- (void)testRequestReadyHandlerFiredOnCompleteRequest {
    XCTestExpectation *handlerExpectation = [self expectationWithDescription:@"Request handler called"];

    self.coordinator.requestReadyHandler = ^(HttpRequest * _Nonnull request) {
        XCTAssertEqualObjects(request.path, @"/x");
        [handlerExpectation fulfill];
    };

    NSString *reqStr = @"GET /x HTTP/1.1\r\nHost:h\r\n\r\n";
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];

    [self.coordinator start];
    [self.mockConnection injectReceiveData:reqData];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testUpgradeHandlerFiredOnUpgradeRequest {
    XCTestExpectation *handlerExpectation = [self expectationWithDescription:@"Upgrade handler called"];

    self.coordinator.upgradeHandler = ^(HttpRequest * _Nonnull request) {
        XCTAssertNotNil(request);
        [handlerExpectation fulfill];
    };

    NSString *upgradeReq = @"GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n";
    NSData *reqData = [upgradeReq dataUsingEncoding:NSUTF8StringEncoding];

    [self.coordinator start];
    [self.mockConnection injectReceiveData:reqData];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testErrorHandlerFiredOnParseError {
    XCTestExpectation *handlerExpectation = [self expectationWithDescription:@"Error handler called"];

    self.coordinator.errorHandler = ^(NSError * _Nonnull error) {
        XCTAssertNotNil(error);
        [handlerExpectation fulfill];
    };

    NSData *malformedData = [@"GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\nContent-Length: 10\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];

    [self.coordinator start];
    [self.mockConnection injectReceiveData:malformedData];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testPauseStopsSchedulingReads {
    XCTestExpectation *noHandlerExp = [self expectationWithDescription:@"handler not called"];
    noHandlerExp.inverted = YES;

    self.coordinator.requestReadyHandler = ^(HttpRequest * _Nonnull request) {
        [noHandlerExp fulfill];
    };

    [self.coordinator start];
    [self.coordinator pause];
    [self.mockConnection injectReceiveComplete];

    [self waitForExpectationsWithTimeout:0.3 handler:nil];
}

- (void)testResumeAfterPauseResumesReads {
    XCTestExpectation *handlerExpectation = [self expectationWithDescription:@"Request handler called"];

    self.coordinator.requestReadyHandler = ^(HttpRequest * _Nonnull request) {
        [handlerExpectation fulfill];
    };

    NSString *reqStr = @"GET /x HTTP/1.1\r\nHost:h\r\n\r\n";
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];

    [self.coordinator start];
    [self.coordinator pause];
    [self.coordinator resume];
    [self.mockConnection injectReceiveData:reqData];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testIdleHeaderDeadlineTerminatesStalledReceiveExactlyOnce {
    self.coordinator = [[HttpConnectionIOCoordinator alloc]
        initWithConnection:self.mockConnection
                   protocol:self.driver
             responseSender:self.sender
          idleHeaderTimeout:0.05
     aggregateHeaderTimeout:0.25];

    XCTestExpectation *timeoutExpectation = [self expectationWithDescription:@"idle header timeout"];
    __block NSUInteger errorCount = 0;
    self.coordinator.errorHandler = ^(NSError *error) {
        errorCount += 1;
        XCTAssertEqual(error.code, 1);
        XCTAssertEqualObjects(error.domain, @"HttpConnectionIOCoordinator");
        [timeoutExpectation fulfill];
    };

    [self.coordinator start];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTestExpectation *settledExpectation = [self expectationWithDescription:@"timeout settles"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        [settledExpectation fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(errorCount, (NSUInteger)1);
    XCTAssertTrue(self.mockConnection.isCancelled);
    XCTAssertEqual(self.mockConnection.cancelCount, (NSUInteger)1);
    XCTAssertNil(self.mockConnection.receiveCompletion);
}

- (void)testAggregateHeaderDeadlineDoesNotResetForTrickleInput {
    self.coordinator = [[HttpConnectionIOCoordinator alloc]
        initWithConnection:self.mockConnection
                   protocol:self.driver
             responseSender:self.sender
          idleHeaderTimeout:0.08
     aggregateHeaderTimeout:0.14];

    XCTestExpectation *timeoutExpectation = [self expectationWithDescription:@"aggregate header timeout"];
    __block NSUInteger errorCount = 0;
    self.coordinator.errorHandler = ^(NSError *error) {
        errorCount += 1;
        XCTAssertEqual(error.code, 1);
        [timeoutExpectation fulfill];
    };

    [self.coordinator start];
    NSArray<NSNumber *> *delays = @[@0.0, @0.03, @0.06, @0.09];
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self.mockConnection injectReceiveData:[@"G" dataUsingEncoding:NSUTF8StringEncoding]];
        });
    }

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertEqual(errorCount, (NSUInteger)1);
    XCTAssertTrue(self.mockConnection.isCancelled);
    XCTAssertEqual(self.mockConnection.cancelCount, (NSUInteger)1);
}

- (void)testRequestWithinConfiguredHeaderDeadlinesRemainsAccepted {
    self.coordinator = [[HttpConnectionIOCoordinator alloc]
        initWithConnection:self.mockConnection
                   protocol:self.driver
             responseSender:self.sender
          idleHeaderTimeout:0.20
     aggregateHeaderTimeout:0.20];

    XCTestExpectation *requestExpectation = [self expectationWithDescription:@"request accepted"];
    XCTestExpectation *timeoutExpectation = [self expectationWithDescription:@"no timeout"];
    timeoutExpectation.inverted = YES;
    self.coordinator.requestReadyHandler = ^(HttpRequest *request) {
        XCTAssertEqualObjects(request.path, @"/within-limits");
        [requestExpectation fulfill];
    };
    self.coordinator.errorHandler = ^(NSError *error) {
        [timeoutExpectation fulfill];
    };

    [self.coordinator start];
    [self.mockConnection injectReceiveData:[@"GET /within-limits HTTP/1.1\r\nHost: h\r\n\r\n"
                                      dataUsingEncoding:NSUTF8StringEncoding]];

    [self waitForExpectationsWithTimeout:0.15 handler:nil];
    XCTAssertFalse(self.mockConnection.isCancelled);
}

- (void)testCompletedSplitHeaderDoesNotApplyAggregateDeadlineToBody {
    self.coordinator = [[HttpConnectionIOCoordinator alloc]
        initWithConnection:self.mockConnection
                   protocol:self.driver
             responseSender:self.sender
          idleHeaderTimeout:0.20
     aggregateHeaderTimeout:0.08];

    XCTestExpectation *requestExpectation = [self expectationWithDescription:@"body request accepted"];
    XCTestExpectation *timeoutExpectation = [self expectationWithDescription:@"no header timeout after terminator"];
    timeoutExpectation.inverted = YES;
    self.coordinator.requestReadyHandler = ^(HttpRequest *request) {
        XCTAssertEqualObjects(request.path, @"/body");
        XCTAssertEqualObjects(request.body, [@"body" dataUsingEncoding:NSUTF8StringEncoding]);
        [requestExpectation fulfill];
    };
    self.coordinator.errorHandler = ^(NSError *error) {
        [timeoutExpectation fulfill];
    };

    [self.coordinator start];
    [self.mockConnection injectReceiveData:[@"POST /body HTTP/1.1\r\nHost: h\r\nContent-Length: 4\r\n\r"
                                      dataUsingEncoding:NSUTF8StringEncoding]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        [self.mockConnection injectReceiveData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(130 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        [self.mockConnection injectReceiveData:[@"body" dataUsingEncoding:NSUTF8StringEncoding]];
    });

    [self waitForExpectationsWithTimeout:0.18 handler:nil];
    XCTAssertFalse(self.mockConnection.isCancelled);
}

- (void)testCloseForUpgradeDoesNotCancelConnection {
    [self.coordinator start];
    [self.coordinator closeForUpgrade];

    // Allow the async dispatch to settle
    XCTestExpectation *settledExpectation = [self expectationWithDescription:@"closeForUpgrade settled"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        [settledExpectation fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertFalse(self.mockConnection.isCancelled);
    XCTAssertEqual(self.mockConnection.cancelCount, (NSUInteger)0);
}

- (void)testCloseForUpgradeStopsReadScheduling {
    XCTestExpectation *noHandlerExp = [self expectationWithDescription:@"handler not called after closeForUpgrade"];
    noHandlerExp.inverted = YES;

    self.coordinator.requestReadyHandler = ^(HttpRequest *request) {
        [noHandlerExp fulfill];
    };

    [self.coordinator start];
    [self.coordinator closeForUpgrade];

    // Inject data after closeForUpgrade — should not produce a request
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        [self.mockConnection injectReceiveData:[@"GET /x HTTP/1.1\r\nHost: h\r\n\r\n"
                                          dataUsingEncoding:NSUTF8StringEncoding]];
    });

    [self waitForExpectationsWithTimeout:0.3 handler:nil];
    XCTAssertFalse(self.mockConnection.isCancelled);
}

@end
