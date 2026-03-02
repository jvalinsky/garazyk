#import <XCTest/XCTest.h>
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/PDSNetworkTransport.h"

// Mock connection
@interface MockHttpConnection : NSObject <PDSNetworkConnection>
@property (nonatomic, strong) NSMutableData *writtenData;
@property (nonatomic, copy) void (^readCompletion)(NSData *, BOOL, NSError *);
@property (nonatomic, assign) PDSNetworkConnectionState state;
@property (nonatomic, copy) void (^stateChangedHandler)(PDSNetworkConnectionState, NSError *);
@property (nonatomic, readonly) NSString *remoteAddress;
@property (nonatomic, readonly) NSString *remoteHost;
@property (nonatomic, readonly) uint16_t remotePort;
@property (nonatomic, assign) BOOL isCancelled;

- (void)simulateReceivedData:(NSData *)data;
- (void)simulateEOF;
@end

@implementation MockHttpConnection

@synthesize remoteAddress = _remoteAddress;
@synthesize remoteHost = _remoteHost;
@synthesize remotePort = _remotePort;

- (instancetype)init {
    if (self = [super init]) {
        _writtenData = [NSMutableData data];
        _state = PDSNetworkConnectionStateReady;
        _remoteAddress = @"127.0.0.1";
        _remoteHost = @"127.0.0.1";
        _remotePort = 12345;
        _isCancelled = NO;
    }
    return self;
}

- (void)startWithQueue:(dispatch_queue_t)queue {
    if (self.stateChangedHandler) {
        self.stateChangedHandler(self.state, nil);
    }
}

- (void)cancel {
    self.isCancelled = YES;
    self.state = PDSNetworkConnectionStateCancelled;
    if (self.stateChangedHandler) {
        self.stateChangedHandler(self.state, nil);
    }
}

- (void)sendData:(NSData *)data completion:(void (^)(NSError * _Nullable))completion {
    [self.writtenData appendData:data];
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
    }
}

- (void)receiveWithMinimumLength:(NSUInteger)minimum maximumLength:(NSUInteger)maximum completion:(void (^)(NSData * _Nullable, BOOL, NSError * _Nullable))completion {
    self.readCompletion = completion;
}

- (void)simulateReceivedData:(NSData *)data {
    if (self.readCompletion) {
        void (^completion)(NSData *, BOOL, NSError *) = self.readCompletion;
        self.readCompletion = nil;
        completion(data, NO, nil);
    } else {
        // If readCompletion is not set yet, wait a tiny bit and try again
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self simulateReceivedData:data];
        });
    }
}

- (void)simulateEOF {
    if (self.readCompletion) {
        void (^completion)(NSData *, BOOL, NSError *) = self.readCompletion;
        self.readCompletion = nil;
        completion(nil, YES, nil);
    }
}
@end

@interface HttpServer (Testing)
- (void)handleNewConnection:(id<PDSNetworkConnection>)connection;
@property (nonatomic, strong) dispatch_queue_t serverQueue;
@property (nonatomic, strong) dispatch_group_t taskGroup;
@property (nonatomic, strong) NSMutableArray<id<PDSNetworkConnection>> *activeConnections;
@end

@interface HttpConnectionCharacterizationTests : XCTestCase
@property (nonatomic, strong) HttpServer *server;
@property (nonatomic, strong) MockHttpConnection *connection;
@end

@implementation HttpConnectionCharacterizationTests

- (void)setUp {
    [super setUp];
    self.server = [HttpServer serverWithPort:0];
    
    // Add a simple handler
    [self.server addRoute:@"GET" path:@"/test" handler:^(HttpRequest *req, HttpResponse *res) {
        [res setBodyString:@"OK"];
        res.statusCode = 200;
    }];
    
    // Add a chunked echo handler
    [self.server addRoute:@"POST" path:@"/echo" handler:^(HttpRequest *req, HttpResponse *res) {
        res.bodyData = req.body;
        res.statusCode = 200;
    }];
    
    self.connection = [[MockHttpConnection alloc] init];
}

- (void)tearDown {
    [self.server stop];
    self.server = nil;
    self.connection = nil;
    [super tearDown];
}

- (void)waitForQueue {
    XCTestExpectation *exp = [self expectationWithDescription:@"Wait for server queue"];
    dispatch_async(self.server.serverQueue, ^{
        [exp fulfill];
    });
    [self waitForExpectations:@[exp] timeout:2.0];
    
    // Also wait for main queue since Mock connection dispatches there
    XCTestExpectation *mainExp = [self expectationWithDescription:@"Wait for main queue"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [mainExp fulfill];
    });
    [self waitForExpectations:@[mainExp] timeout:2.0];
}

- (void)testKeepAliveRequests {
    [self.server handleNewConnection:self.connection];
    
    NSString *req1 = @"GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    [self.connection simulateReceivedData:[req1 dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Wait for dispatch group to clear
    dispatch_group_wait(self.server.taskGroup, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC));
    [self waitForQueue]; // Wait for queueing to finish
    
    NSString *respStr = [[NSString alloc] initWithData:self.connection.writtenData encoding:NSUTF8StringEncoding];
    NSLog(@"testKeepAliveRequests req1 respStr: %@", respStr);
    XCTAssertTrue([respStr containsString:@"200 OK"]);
    XCTAssertTrue([respStr containsString:@"OK"]);
    
    // Connection should remain alive
    XCTAssertFalse(self.connection.isCancelled);
    
    // Clear written data for second request
    [self.connection.writtenData setLength:0];
    
    NSString *req2 = @"GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    [self.connection simulateReceivedData:[req2 dataUsingEncoding:NSUTF8StringEncoding]];
    
    dispatch_group_wait(self.server.taskGroup, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC));
    [self waitForQueue];
    
    respStr = [[NSString alloc] initWithData:self.connection.writtenData encoding:NSUTF8StringEncoding];
    XCTAssertTrue([respStr containsString:@"200 OK"]);
}

- (void)testPipelinedRequests {
    [self.server handleNewConnection:self.connection];
    
    NSString *req = @"GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n"
                    @"GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    
    [self.connection simulateReceivedData:[req dataUsingEncoding:NSUTF8StringEncoding]];
    
    dispatch_group_wait(self.server.taskGroup, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC));
    [self waitForQueue];
    
    NSString *respStr = [[NSString alloc] initWithData:self.connection.writtenData encoding:NSUTF8StringEncoding];
    // Check that there are two responses
    NSArray *parts = [respStr componentsSeparatedByString:@"HTTP/1.1 200 OK"];
    // The sans-io parser correctly supports pipelining without zeroing the buffer.
    XCTAssertEqual(parts.count, 3); // 2 occurrences = 3 parts
}

- (void)testChunkedBody {
    [self.server handleNewConnection:self.connection];
    
    NSString *req = @"POST /echo HTTP/1.1\r\n"
                    @"Host: localhost\r\n"
                    @"Transfer-Encoding: chunked\r\n\r\n"
                    @"4\r\nWiki\r\n"
                    @"5\r\npedia\r\n"
                    @"0\r\n\r\n";
    
    [self.connection simulateReceivedData:[req dataUsingEncoding:NSUTF8StringEncoding]];
    
    dispatch_group_wait(self.server.taskGroup, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC));
    [self waitForQueue];
    
    NSString *respStr = [[NSString alloc] initWithData:self.connection.writtenData encoding:NSUTF8StringEncoding];
    XCTAssertTrue([respStr containsString:@"200 OK"]);
    XCTAssertTrue([respStr containsString:@"Wikipedia"]);
}

- (void)testOversizedHeader {
    [self.server handleNewConnection:self.connection];
    
    NSMutableString *req = [NSMutableString stringWithString:@"GET /test HTTP/1.1\r\n"];
    // Add large headers to exceed 16KB limit (kHttpMaxHeaderBytes)
    for (int i=0; i<1000; i++) {
        [req appendString:@"X-Custom-Header: "];
        [req appendString:[@"" stringByPaddingToLength:20 withString:@"A" startingAtIndex:0]];
        [req appendString:@"\r\n"];
    }
    [req appendString:@"\r\n"];
    
    [self.connection simulateReceivedData:[req dataUsingEncoding:NSUTF8StringEncoding]];
    
    dispatch_group_wait(self.server.taskGroup, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC));
    [self waitForQueue];
    
    NSString *respStr = [[NSString alloc] initWithData:self.connection.writtenData encoding:NSUTF8StringEncoding];
    XCTAssertTrue([respStr containsString:@"413"]);
}

- (void)testMissingContentLengthForPost {
    [self.server handleNewConnection:self.connection];
    
    NSString *req = @"POST /echo HTTP/1.1\r\n"
                    @"Host: localhost\r\n\r\n";
    
    [self.connection simulateReceivedData:[req dataUsingEncoding:NSUTF8StringEncoding]];
    
    dispatch_group_wait(self.server.taskGroup, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC));
    [self waitForQueue];
    
    NSString *respStr = [[NSString alloc] initWithData:self.connection.writtenData encoding:NSUTF8StringEncoding];
    XCTAssertTrue([respStr containsString:@"411"]);
}

@end
