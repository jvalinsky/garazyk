#import <XCTest/XCTest.h>
#import "Network/HttpConnectionIOCoordinator.h"
#import "Network/HttpProtocolDriver.h"
#import "Network/HttpResponseSender.h"
#import "Network/HttpRequest.h"
#import "Network/PDSNetworkTransport.h"

@interface MockIOConnection : NSObject <PDSNetworkConnection>
@property (nonatomic, strong) NSMutableData *sentData;
@property (nonatomic, copy) void (^receiveCompletion)(NSData *data, BOOL isComplete, NSError *error);
@property (nonatomic, strong) NSMutableArray<NSData *> *pendingData;
@property (nonatomic, assign) BOOL isEOF;
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

@end
