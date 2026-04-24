#import <XCTest/XCTest.h>
#import "Network/HttpConnectionIOCoordinator.h"
#import "Network/HttpProtocolDriver.h"
#import "Network/HttpResponseSender.h"
#import "Network/HttpRequest.h"

@interface MockIOConnection : NSObject <PDSNetworkConnection>
@property (nonatomic, strong) NSMutableData *sentData;
@property (nonatomic, copy) void (^receiveCompletion)(NSData *data, BOOL isComplete, NSError *error);
- (void)injectReceiveData:(NSData *)data;
- (void)injectReceiveComplete;
@end

@implementation MockIOConnection

- (instancetype)init {
    self = [super init];
    if (self) {
        self.sentData = [NSMutableData data];
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
    self.receiveCompletion = completion;
}

- (void)injectReceiveData:(NSData *)data {
    if (self.receiveCompletion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.receiveCompletion) {
                self.receiveCompletion(data, NO, nil);
            }
        });
    }
}

- (void)injectReceiveComplete {
    if (self.receiveCompletion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.receiveCompletion) {
                self.receiveCompletion(nil, YES, nil);
            }
        });
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self.mockConnection injectReceiveData:reqData];
    });

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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self.mockConnection injectReceiveData:reqData];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testErrorHandlerFiredOnParseError {
    XCTestExpectation *handlerExpectation = [self expectationWithDescription:@"Error handler called"];

    self.coordinator.errorHandler = ^(NSError * _Nonnull error) {
        XCTAssertNotNil(error);
        [handlerExpectation fulfill];
    };

    NSData *malformedData = [@"GARBAGE!!!" dataUsingEncoding:NSUTF8StringEncoding];

    [self.coordinator start];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self.mockConnection injectReceiveData:malformedData];
    });

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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self.mockConnection injectReceiveData:reqData];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

@end
