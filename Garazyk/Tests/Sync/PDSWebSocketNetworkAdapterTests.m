// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/WebSocket/PDSWebSocketNetworkAdapter.h"

// Forward declare ATProtoNetworkConnection protocol
@protocol ATProtoNetworkConnection <NSObject>
- (void)sendData:(NSData *)data completion:(void (^)(NSError * _Nullable))completion;
- (void)receiveWithMinimumLength:(NSUInteger)minLength
                   maximumLength:(NSUInteger)maxLength
                      completion:(void (^)(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error))completion;
@end

@interface MockAdapterNetworkConnection : NSObject <ATProtoNetworkConnection>
@property (nonatomic, strong) NSMutableArray<void (^)(NSData *, BOOL, NSError *)> *receiveCallbacks;
@property (nonatomic, strong) NSMutableArray<void (^)(NSError *)> *sendCallbacks;
@property (nonatomic, copy) void (^sendHandler)(NSData *);
@property (nonatomic, assign) BOOL shouldSucceed;
@property (nonatomic, strong, nullable) NSError *receiveError;
@property (nonatomic, assign) BOOL receiveComplete;
@property (nonatomic, strong, nullable) NSData *nextReceiveData;
@end

@implementation MockAdapterNetworkConnection

- (instancetype)init {
  self = [super init];
  if (self) {
    _receiveCallbacks = [NSMutableArray array];
    _sendCallbacks = [NSMutableArray array];
    _shouldSucceed = YES;
  }
  return self;
}

- (void)sendData:(NSData *)data completion:(void (^)(NSError * _Nullable))completion {
  if (self.sendHandler) {
    self.sendHandler(data);
  }
  if (completion) {
    completion(self.shouldSucceed ? nil : [NSError errorWithDomain:@"Test" code:-1 userInfo:nil]);
  }
  if (completion) {
    [self.sendCallbacks addObject:completion];
  }
}

- (void)receiveWithMinimumLength:(NSUInteger)minLength
                   maximumLength:(NSUInteger)maxLength
                      completion:(void (^)(NSData * _Nullable, BOOL, NSError * _Nullable))completion {
  if (completion) {
    [self.receiveCallbacks addObject:completion];
  }
  if (self.receiveError) {
    completion(nil, NO, self.receiveError);
  } else if (self.nextReceiveData) {
    completion(self.nextReceiveData, NO, nil);
  } else if (self.receiveComplete) {
    completion(nil, YES, nil);
  }
}

@end

@interface PDSWebSocketNetworkAdapterTests : XCTestCase
@end

@implementation PDSWebSocketNetworkAdapterTests

- (void)testInitWithConnection_Valid_ReturnsAdapter {
  MockAdapterNetworkConnection *conn = [[MockAdapterNetworkConnection alloc] init];
  PDSWebSocketNetworkAdapter *adapter = [[PDSWebSocketNetworkAdapter alloc] initWithConnection:conn];
  XCTAssertNotNil(adapter);
}

- (void)testInitWithConnection_NilConnection_ReturnsNil {
  PDSWebSocketNetworkAdapter *adapter = [[PDSWebSocketNetworkAdapter alloc] initWithConnection:nil];
  XCTAssertNil(adapter);
}

- (void)testSetAndGetMessageHandler {
  MockAdapterNetworkConnection *conn = [[MockAdapterNetworkConnection alloc] init];
  PDSWebSocketNetworkAdapter *adapter = [[PDSWebSocketNetworkAdapter alloc] initWithConnection:conn];
  XCTAssertNotNil(adapter);

  __block BOOL handlerCalled = NO;
  [adapter setMessageHandler:^(NSData *message) {
    handlerCalled = YES;
  }];

  PDSWebSocketTransportMessageHandler handler = [adapter messageHandler];
  XCTAssertNotNil(handler);

  // Invoke the handler directly
  handler([NSData data]);
  XCTAssertTrue(handlerCalled);
}

- (void)testSetAndGetCloseHandler {
  MockAdapterNetworkConnection *conn = [[MockAdapterNetworkConnection alloc] init];
  PDSWebSocketNetworkAdapter *adapter = [[PDSWebSocketNetworkAdapter alloc] initWithConnection:conn];
  XCTAssertNotNil(adapter);

  __block BOOL handlerCalled = NO;
  [adapter setCloseHandler:^(NSInteger code, NSString *reason) {
    handlerCalled = YES;
  }];

  PDSWebSocketTransportCloseHandler handler = [adapter closeHandler];
  XCTAssertNotNil(handler);

  handler(1000, @"Normal");
  XCTAssertTrue(handlerCalled);
}

- (void)testSetAndGetErrorHandler {
  MockAdapterNetworkConnection *conn = [[MockAdapterNetworkConnection alloc] init];
  PDSWebSocketNetworkAdapter *adapter = [[PDSWebSocketNetworkAdapter alloc] initWithConnection:conn];
  XCTAssertNotNil(adapter);

  __block BOOL handlerCalled = NO;
  [adapter setErrorHandler:^(NSError *error) {
    handlerCalled = YES;
  }];

  PDSWebSocketTransportErrorHandler handler = [adapter errorHandler];
  XCTAssertNotNil(handler);

  handler([NSError errorWithDomain:@"Test" code:-1 userInfo:nil]);
  XCTAssertTrue(handlerCalled);
}

- (void)testStart_DoesNotCrash {
  MockAdapterNetworkConnection *conn = [[MockAdapterNetworkConnection alloc] init];
  PDSWebSocketNetworkAdapter *adapter = [[PDSWebSocketNetworkAdapter alloc] initWithConnection:conn];
  XCTAssertNotNil(adapter);

  XCTAssertNoThrow([adapter start]);
}

- (void)testStart_AlreadyStarted_DoesNotDoubleStart {
  MockAdapterNetworkConnection *conn = [[MockAdapterNetworkConnection alloc] init];
  PDSWebSocketNetworkAdapter *adapter = [[PDSWebSocketNetworkAdapter alloc] initWithConnection:conn];
  XCTAssertNotNil(adapter);

  [adapter start];
  // Second start should be a no-op
  XCTAssertNoThrow([adapter start]);
}

- (void)testSendMessage_WithData_CallsConnectionSend {
  MockAdapterNetworkConnection *conn = [[MockAdapterNetworkConnection alloc] init];
  PDSWebSocketNetworkAdapter *adapter = [[PDSWebSocketNetworkAdapter alloc] initWithConnection:conn];
  XCTAssertNotNil(adapter);

  __block BOOL sendCalled = NO;
  conn.sendHandler = ^(NSData *data) {
    sendCalled = YES;
    XCTAssertGreaterThan(data.length, (NSUInteger)0);
  };

  XCTestExpectation *expectation = [self expectationWithDescription:@"send"];
  [adapter sendMessage:[NSData dataWithBytes:"hello" length:5] completion:^(NSError *error) {
    XCTAssertNil(error);
    [expectation fulfill];
  }];

  [self waitForExpectations:@[expectation] timeout:1.0];
  XCTAssertTrue(sendCalled);
}

- (void)testCloseWithCode_CallsConnectionSend {
  MockAdapterNetworkConnection *conn = [[MockAdapterNetworkConnection alloc] init];
  PDSWebSocketNetworkAdapter *adapter = [[PDSWebSocketNetworkAdapter alloc] initWithConnection:conn];
  XCTAssertNotNil(adapter);

  __block BOOL sendCalled = NO;
  conn.sendHandler = ^(NSData *data) {
    sendCalled = YES;
    XCTAssertGreaterThan(data.length, (NSUInteger)0);
  };

  XCTestExpectation *expectation = [self expectationWithDescription:@"close"];
  [adapter closeWithCode:1000 reason:@"Normal closure" completion:^(NSError *error) {
    XCTAssertNil(error);
    [expectation fulfill];
  }];

  [self waitForExpectations:@[expectation] timeout:1.0];
  XCTAssertTrue(sendCalled);
}

- (void)testCloseWithCode_AlreadyClosed_CallsCompletionWithNilError {
  MockAdapterNetworkConnection *conn = [[MockAdapterNetworkConnection alloc] init];
  PDSWebSocketNetworkAdapter *adapter = [[PDSWebSocketNetworkAdapter alloc] initWithConnection:conn];
  XCTAssertNotNil(adapter);

  XCTestExpectation *expectation = [self expectationWithDescription:@"close"];
  [adapter closeWithCode:1000 reason:@"First" completion:^(NSError *error) {
    XCTAssertNil(error);
    // Second close should also complete with nil error
    [adapter closeWithCode:1000 reason:@"Second" completion:^(NSError *error2) {
      XCTAssertNil(error2);
      [expectation fulfill];
    }];
  }];

  [self waitForExpectations:@[expectation] timeout:1.0];
}

- (void)testSendMessage_AfterClose_ReturnsError {
  MockAdapterNetworkConnection *conn = [[MockAdapterNetworkConnection alloc] init];
  PDSWebSocketNetworkAdapter *adapter = [[PDSWebSocketNetworkAdapter alloc] initWithConnection:conn];
  XCTAssertNotNil(adapter);

  XCTestExpectation *expectation = [self expectationWithDescription:@"send after close"];
  [adapter closeWithCode:1000 reason:@"Goodbye" completion:nil];

  // Small delay for close to complete
  dispatch_async(dispatch_get_main_queue(), ^{
    [adapter sendMessage:[NSData data] completion:^(NSError *error) {
      XCTAssertNotNil(error);
      [expectation fulfill];
    }];
  });

  [self waitForExpectations:@[expectation] timeout:1.0];
}

@end
