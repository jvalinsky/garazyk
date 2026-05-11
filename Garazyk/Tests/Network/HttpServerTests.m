// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#include <string.h>
#import "Network/HttpServer.h"
#import "Network/HttpProtocolDriver.h"
#import "Network/HttpResponse.h"
#import "Network/PDSNetworkTransport.h"

typedef id<PDSNetworkListener> (^PDSListenerFactory)(NSUInteger port);
static const NSUInteger kGeneratedChunkCap = 64 * 1024;

static PDSListenerFactory sListenerFactory = nil;
static IMP sOriginalCreateListenerIMP = NULL;

static id<PDSNetworkListener> TestCreateListener(id self, SEL _cmd, NSUInteger port) {
    if (sListenerFactory) {
        return sListenerFactory(port);
    }
    return nil;
}

@interface PDSFakeListener : NSObject <PDSNetworkListener>
@property (nonatomic, copy, nullable) void (^stateChangedHandler)(PDSNetworkListenerState state, NSError * _Nullable error);
@property (nonatomic, copy, nullable) void (^newConnectionHandler)(id<PDSNetworkConnection> connection);
@property (nonatomic, assign) NSUInteger port;
@property (nonatomic, assign) PDSNetworkListenerState stateToReport;
@property (nonatomic, strong, nullable) NSError *errorToReport;
@end

@implementation PDSFakeListener

- (instancetype)initWithPort:(NSUInteger)port state:(PDSNetworkListenerState)state error:(NSError *)error {
    self = [super init];
    if (self) {
        _port = port;
        _stateToReport = state;
        _errorToReport = error;
    }
    return self;
}

- (void)startWithQueue:(dispatch_queue_t)queue {
    dispatch_async(queue, ^{
        if (self.stateChangedHandler) {
            self.stateChangedHandler(self.stateToReport, self.errorToReport);
        }
    });
}

- (void)cancel {
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkListenerStateCancelled, nil);
    }
}

@end

@interface HttpServer (Testing)
- (void)sendResponse:(HttpResponse *)response onConnection:(id<PDSNetworkConnection>)connection;
@end

@interface PDSFakeConnection : NSObject <PDSNetworkConnection>
@property (nonatomic, copy, nullable) void (^stateChangedHandler)(PDSNetworkConnectionState state, NSError * _Nullable error);
@property (nonatomic, strong, readonly, nullable) NSString *remoteAddress;
@property (nonatomic, strong) NSMutableArray<NSData *> *sentData;
@property (nonatomic, assign) NSUInteger receiveCallCount;
@property (nonatomic, assign) BOOL cancelCalled;
@end

@implementation PDSFakeConnection

- (instancetype)init {
    self = [super init];
    if (self) {
        _remoteAddress = @"127.0.0.1";
        _sentData = [NSMutableArray array];
        _receiveCallCount = 0;
        _cancelCalled = NO;
    }
    return self;
}

- (void)startWithQueue:(dispatch_queue_t)queue {
    dispatch_async(queue, ^{
        if (self.stateChangedHandler) {
            self.stateChangedHandler(PDSNetworkConnectionStateReady, nil);
        }
    });
}

- (void)cancel {
    self.cancelCalled = YES;
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkConnectionStateCancelled, nil);
    }
}

- (void)sendData:(NSData *)data completion:(void (^ _Nullable)(NSError * _Nullable error))completion {
    [self.sentData addObject:[data copy]];
    if (completion) {
        completion(nil);
    }
}

- (void)receiveWithMinimumLength:(NSUInteger)minLength
                    maximumLength:(NSUInteger)maxLength
                       completion:(void (^)(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error))completion {
    self.receiveCallCount += 1;
    if (completion) {
        completion(nil, YES, nil);
    }
}

@end

@interface HttpServerTests : XCTestCase
@end

@implementation HttpServerTests

- (void)setUp {
    [super setUp];
    [self swizzleListenerFactory];
}

- (void)tearDown {
    [self restoreListenerFactory];
    sListenerFactory = nil;
    [super tearDown];
}

- (void)swizzleListenerFactory {
    Method method = class_getClassMethod([PDSNetworkTransportFactory class], @selector(createListenerWithPort:));
    if (!method) {
        return;
    }
    if (!sOriginalCreateListenerIMP) {
        sOriginalCreateListenerIMP = method_getImplementation(method);
    }
    method_setImplementation(method, (IMP)TestCreateListener);
}

- (void)restoreListenerFactory {
    if (!sOriginalCreateListenerIMP) {
        return;
    }
    Method method = class_getClassMethod([PDSNetworkTransportFactory class], @selector(createListenerWithPort:));
    if (method) {
        method_setImplementation(method, sOriginalCreateListenerIMP);
    }
}

- (void)testStartFailsWhenListenerFactoryReturnsNil {
    sListenerFactory = nil;
    HttpServer *server = [HttpServer serverWithPort:0];

    NSError *error = nil;
    BOOL started = [server startWithError:&error];

    XCTAssertFalse(started);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, -1);
}

- (void)testStartFailsWhenListenerReportsFailure {
    sListenerFactory = ^id<PDSNetworkListener>(NSUInteger port) {
        NSError *listenerError = [NSError errorWithDomain:@"test.listener" code:42 userInfo:nil];
        return [[PDSFakeListener alloc] initWithPort:port state:PDSNetworkListenerStateFailed error:listenerError];
    };
    HttpServer *server = [HttpServer serverWithPort:0];

    NSError *error = nil;
    BOOL started = [server startWithError:&error];

    XCTAssertFalse(started);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, -3);
}

- (void)testStartSucceedsWhenListenerReady {
    sListenerFactory = ^id<PDSNetworkListener>(NSUInteger port) {
        return [[PDSFakeListener alloc] initWithPort:12345 state:PDSNetworkListenerStateReady error:nil];
    };
    HttpServer *server = [HttpServer serverWithPort:0];

    NSError *error = nil;
    BOOL started = [server startWithError:&error];

    XCTAssertTrue(started);
    XCTAssertNil(error);
    XCTAssertEqual(server.port, 12345);
}

- (void)testSendResponseStreamsChunkedProducerFrames {
    HttpServer *server = [HttpServer serverWithPort:0];
    PDSFakeConnection *connection = [[PDSFakeConnection alloc] init];

    HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusOK];
    response.contentType = @"application/vnd.ipld.car";
    __block NSUInteger chunkIndex = 0;
    NSArray<NSData *> *chunks = @[
        [@"abc" dataUsingEncoding:NSUTF8StringEncoding],
        [@"def" dataUsingEncoding:NSUTF8StringEncoding]
    ];
    [response setBodyChunkProducer:^NSData * _Nullable(NSError **error) {
        if (chunkIndex < chunks.count) {
            return chunks[chunkIndex++];
        }
        return [NSData data];
    } chunkedTransferEncoding:YES];

    [server sendResponse:response onConnection:connection];

    XCTAssertEqual(connection.sentData.count, (NSUInteger)4);
    NSString *headerString = [[NSString alloc] initWithData:connection.sentData[0]
                                                   encoding:NSUTF8StringEncoding];
    XCTAssertNotNil(headerString);
    XCTAssertTrue([headerString containsString:@"HTTP/1.1 200"]);
    XCTAssertNotEqual([headerString rangeOfString:@"Transfer-Encoding: chunked"
                                          options:NSCaseInsensitiveSearch].location,
                      NSNotFound);
    XCTAssertEqual([headerString rangeOfString:@"Content-Length:"
                                       options:NSCaseInsensitiveSearch].location,
                   NSNotFound);
    XCTAssertEqualObjects(connection.sentData[1], [@"3\r\nabc\r\n" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqualObjects(connection.sentData[2], [@"3\r\ndef\r\n" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqualObjects(connection.sentData[3], [@"0\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]);
    // Note: After Phase C refactoring, read scheduling is handled by
    // HttpConnectionIOCoordinator. Since this test bypasses the full
    // connection lifecycle (no coordinator), receiveCallCount/cancelCalled
    // are no longer triggered by sendResponse alone.
}

- (void)testSendResponseCancelsConnectionWhenChunkProducerFails {
    HttpServer *server = [HttpServer serverWithPort:0];
    PDSFakeConnection *connection = [[PDSFakeConnection alloc] init];

    HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusOK];
    response.contentType = @"application/vnd.ipld.car";
    __block NSUInteger invocation = 0;
    [response setBodyChunkProducer:^NSData * _Nullable(NSError **error) {
        NSUInteger current = invocation++;
        if (current == 0) {
            return [@"abc" dataUsingEncoding:NSUTF8StringEncoding];
        }
        if (error) {
            *error = [NSError errorWithDomain:@"test.chunk.producer" code:17 userInfo:nil];
        }
        return nil;
    } chunkedTransferEncoding:YES];

    [server sendResponse:response onConnection:connection];

    XCTAssertEqual(connection.sentData.count, (NSUInteger)2);
    NSString *headerString = [[NSString alloc] initWithData:connection.sentData[0]
                                                   encoding:NSUTF8StringEncoding];
    XCTAssertNotNil(headerString);
    XCTAssertNotEqual([headerString rangeOfString:@"Transfer-Encoding: chunked"
                                          options:NSCaseInsensitiveSearch].location,
                      NSNotFound);
    XCTAssertEqualObjects(connection.sentData[1], [@"3\r\nabc\r\n" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqual(connection.receiveCallCount, (NSUInteger)0);
    XCTAssertTrue(connection.cancelCalled);
}

- (void)testSendResponseSplitsOversizedProducerChunkByPolicy {
    HttpServer *server = [HttpServer serverWithPort:0];
    PDSFakeConnection *connection = [[PDSFakeConnection alloc] init];

    NSMutableData *largePayload = [NSMutableData dataWithLength:(kGeneratedChunkCap * 2) + 137];
    memset(largePayload.mutableBytes, 'x', largePayload.length);

    HttpResponse *response = [HttpResponse responseWithStatusCode:HttpStatusOK];
    response.contentType = @"application/vnd.ipld.car";
    __block BOOL emitted = NO;
    [response setBodyChunkProducer:^NSData * _Nullable(NSError **error) {
        if (emitted) {
            return [NSData data];
        }
        emitted = YES;
        return [largePayload copy];
    } chunkedTransferEncoding:YES];

    [server sendResponse:response onConnection:connection];

    XCTAssertTrue(connection.sentData.count >= 5, @"Expected header, multiple chunk frames, and terminator");
    NSData *terminator = [@"0\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(connection.sentData.lastObject, terminator);

    NSUInteger totalChunkPayloadBytes = 0;
    NSUInteger chunkFrameCount = 0;
    for (NSUInteger i = 1; i + 1 < connection.sentData.count; i++) {
        NSData *frame = connection.sentData[i];
        const uint8_t *bytes = frame.bytes;
        NSUInteger lineEnd = NSNotFound;
        for (NSUInteger j = 0; j + 1 < frame.length; j++) {
            if (bytes[j] == '\r' && bytes[j + 1] == '\n') {
                lineEnd = j;
                break;
            }
        }
        XCTAssertNotEqual(lineEnd, NSNotFound);
        XCTAssertTrue(lineEnd > 0);

        NSData *sizeLineData = [frame subdataWithRange:NSMakeRange(0, lineEnd)];
        NSString *sizeLine = [[NSString alloc] initWithData:sizeLineData encoding:NSUTF8StringEncoding];
        XCTAssertNotNil(sizeLine);
        unsigned long chunkSize = strtoul(sizeLine.UTF8String, NULL, 16);
        XCTAssertTrue(chunkSize > 0);
        XCTAssertTrue(chunkSize <= kGeneratedChunkCap);

        NSUInteger expectedFrameLength = lineEnd + 2 + (NSUInteger)chunkSize + 2;
        XCTAssertEqual(frame.length, expectedFrameLength);
        totalChunkPayloadBytes += (NSUInteger)chunkSize;
        chunkFrameCount += 1;
    }

    XCTAssertTrue(chunkFrameCount >= 3, @"Large payload should be split into multiple wire chunks");
    XCTAssertEqual(totalChunkPayloadBytes, largePayload.length);
    // Note: After Phase C refactoring, read scheduling is handled by
    // HttpConnectionIOCoordinator. Since this test bypasses the full
    // connection lifecycle (no coordinator), receiveCallCount/cancelCalled
    // are no longer triggered by sendResponse alone.
}

- (void)testRejectsAmbiguousTransferEncodingAndContentLength {
    HttpProtocolDriver *driver = [[HttpProtocolDriver alloc] init];

    NSString *rawRequest = @"POST /xrpc/com.atproto.server.getSession HTTP/1.1\r\n"
                           "Host: localhost\r\n"
                           "Transfer-Encoding: chunked\r\n"
                           "Content-Length: 4\r\n"
                           "\r\n"
                           "0\r\n\r\n";
    NSData *requestData = [rawRequest dataUsingEncoding:NSUTF8StringEncoding];

    NSArray<NSNumber *> *events = [driver feedData:requestData];

    // The driver should detect the ambiguous framing as a protocol error
    BOOL hasProtocolError = NO;
    for (NSNumber *event in events) {
        if ([event integerValue] == HttpProtocolEventProtocolError) {
            hasProtocolError = YES;
            break;
        }
    }
    XCTAssertTrue(hasProtocolError, @"Expected HttpProtocolEventProtocolError for ambiguous Transfer-Encoding + Content-Length");

    NSError *parseError = [driver currentParseError];
    XCTAssertNotNil(parseError, @"Expected a parse error to be set");
    NSString *errorDescription = parseError.localizedDescription ?: @"";
    XCTAssertTrue([errorDescription containsString:@"InvalidRequestFraming"] ||
                  [errorDescription containsString:@"ambiguous"] ||
                  [errorDescription containsString:@"Transfer-Encoding"] ||
                  [errorDescription containsString:@"Content-Length"],
                  @"Expected explicit framing error in: %@", errorDescription);
}

@end
