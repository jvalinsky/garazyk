// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/WebSocket/PDSWebSocketNetworkAdapter.h"
#import "Sync/WebSocket/WebSocketCodec.h"

@interface MockNetworkConnection : NSObject <PDSNetworkConnection>
@property (nonatomic, strong) NSMutableData *sentData;
@property (nonatomic, copy) void (^receiveCompletion)(NSData *data, BOOL isComplete, NSError *error);
@property (nonatomic, strong) NSMutableArray<NSData *> *pendingData;
@property (nonatomic, assign) BOOL isEOF;
- (void)injectReceiveData:(NSData *)data;
- (void)injectReceiveComplete;
@end

@implementation MockNetworkConnection

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

@interface PDSWebSocketTransportTests : XCTestCase
@property (nonatomic, strong) PDSWebSocketNetworkAdapter *adapter;
@property (nonatomic, strong) MockNetworkConnection *mockConnection;
@property (nonatomic, strong) WebSocketCodec *codec;
@end

@implementation PDSWebSocketTransportTests

- (void)setUp {
    [super setUp];
    self.mockConnection = [[MockNetworkConnection alloc] init];
    self.adapter = [[PDSWebSocketNetworkAdapter alloc] initWithConnection:self.mockConnection];
    self.codec = [[WebSocketCodec alloc] init];
}

- (void)tearDown {
    self.adapter = nil;
    self.mockConnection = nil;
    self.codec = nil;
    [super tearDown];
}

- (void)testAdapterConformsToProtocol {
    XCTAssertTrue([self.adapter conformsToProtocol:@protocol(PDSWebSocketTransport)]);
}

- (void)testSendMessageEncodesAsWebSocketFrame {
    XCTestExpectation *sendExpectation = [self expectationWithDescription:@"Send completion called"];
    __block NSError *sendError = nil;
    NSData *payload = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];

    [self.adapter sendMessage:payload completion:^(NSError * _Nullable error) {
        sendError = error;
        [sendExpectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertNil(sendError);
    XCTAssertGreaterThan(self.mockConnection.sentData.length, 0);
}

- (void)testReceiveMessageDecodesAndInvokesHandler {
    XCTestExpectation *handlerExpectation = [self expectationWithDescription:@"Handler called"];

    NSData *payload = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *frame = [self.codec binaryFrame:payload];

    self.adapter.messageHandler = ^(NSData * _Nonnull data) {
        XCTAssertEqualObjects(data, payload);
        [handlerExpectation fulfill];
    };

    [self.adapter start];
    [self.mockConnection injectReceiveData:frame];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testPingAutoRespondsWithPong {
    XCTestExpectation *pongExpectation = [self expectationWithDescription:@"Pong sent"];

    NSData *pingFrame = [self.codec pingFrame:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XCTAssertGreaterThanOrEqual(self.mockConnection.sentData.length, pingFrame.length);
        [pongExpectation fulfill];
    });

    [self.adapter start];
    [self.mockConnection injectReceiveData:pingFrame];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testCloseFrameInvokesCloseHandler {
    XCTestExpectation *closeExpectation = [self expectationWithDescription:@"Close handler called"];

    NSData *closeFrame = [self.codec closeFrame:1000 reason:@"done"];

    self.adapter.closeHandler = ^(NSInteger code, NSString * _Nonnull reason) {
        XCTAssertEqual(code, 1000);
        XCTAssertEqualObjects(reason, @"done");
        [closeExpectation fulfill];
    };

    [self.adapter start];
    [self.mockConnection injectReceiveData:closeFrame];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testAbnormalEOFInvokesCloseWithCode1006 {
    XCTestExpectation *closeExpectation = [self expectationWithDescription:@"Close handler called"];

    self.adapter.closeHandler = ^(NSInteger code, NSString * _Nonnull reason) {
        XCTAssertEqual(code, 1006);
        [closeExpectation fulfill];
    };

    [self.adapter start];
    [self.mockConnection injectReceiveComplete];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testSendOnClosedConnectionReturnsError {
    XCTestExpectation *sendExpectation = [self expectationWithDescription:@"send after close fails"];

    NSData *closeFrame = [self.codec closeFrame:1000 reason:@"closing"];

    self.adapter.closeHandler = ^(NSInteger code, NSString * _Nonnull reason) {
        [self.adapter sendMessage:[@"test" dataUsingEncoding:NSUTF8StringEncoding]
                       completion:^(NSError * _Nullable error) {
            XCTAssertNotNil(error);
            [sendExpectation fulfill];
        }];
    };

    [self.adapter start];
    [self.mockConnection injectReceiveData:closeFrame];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

@end
