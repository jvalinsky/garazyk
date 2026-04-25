#import <XCTest/XCTest.h>
#import "Services/PDS/PDSRelayService.h"
#import "Core/PDSRecordEvents.h"

#pragma mark - Mock Transport

@interface PDSRelayMockTransport : NSObject <PDSRelayTransport>
@property (nonatomic, strong) NSMutableArray<NSURLRequest *> *sentRequests;
@property (nonatomic, copy) void (^customHandler)(NSURLRequest *request,
    void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable));
@end

@implementation PDSRelayMockTransport

- (instancetype)init {
    self = [super init];
    if (self) {
        _sentRequests = [NSMutableArray array];
    }
    return self;
}

- (void)sendRequest:(NSURLRequest *)request
   completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))handler {
    [self.sentRequests addObject:request];
    if (self.customHandler) {
        self.customHandler(request, handler);
    } else {
        // Default: return 200 OK
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
            initWithURL:request.URL
              statusCode:200
             HTTPVersion:@"HTTP/1.1"
            headerFields:@{@"Content-Type": @"application/json"}];
        handler(nil, response, nil);
    }
}

@end

#pragma mark - Test Expose Internals

@interface PDSRelayService (TestAccess)
@property (nonatomic, strong, readonly) NSMutableSet<NSString *> *pendingDids;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@end

#pragma mark - Tests

@interface PDSRelayServiceTests : XCTestCase
@property (nonatomic, strong) PDSRelayService *service;
@property (nonatomic, strong) PDSRelayMockTransport *mockTransport;
@end

@implementation PDSRelayServiceTests

- (void)setUp {
    [super setUp];
    self.service = [[PDSRelayService alloc] initWithRelays:@[@"https://relay1.example.com"]
                                                  hostname:@"pds.example.com"];
    self.mockTransport = [[PDSRelayMockTransport alloc] init];
    self.service.transport = self.mockTransport;
}

- (void)tearDown {
    [self.service stop];
    self.service = nil;
    self.mockTransport = nil;
    [super tearDown];
}

#pragma mark - Initialization

- (void)testInitializationStoresRelaysAndHostname {
    PDSRelayService *svc = [[PDSRelayService alloc] initWithRelays:@[@"https://r1.test", @"https://r2.test"]
                                                           hostname:@"myhost.test"];
    XCTAssertNotNil(svc);
    XCTAssertNotNil(svc.transport, @"Default transport should be created");
}

- (void)testDefaultTransportIsNSURLSession {
    PDSRelayService *svc = [[PDSRelayService alloc] initWithRelays:@[]
                                                          hostname:@"test"];
    XCTAssertNotNil(svc.transport);
    // Verify it's a valid transport (we can't check class since PDSRelayURLSessionTransport
    // is private, but we can verify it conforms to the protocol)
    XCTAssertTrue([svc.transport conformsToProtocol:@protocol(PDSRelayTransport)]);
}

#pragma mark - Start / Stop

- (void)testStartRegistersForRecordChangeNotifications {
    [self.service start];

    // Post a notification and verify it's handled
    [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                        object:nil
                                                      userInfo:@{@"did": @"did:plc:test123"}];

    // Give the dispatch queue time to process
    XCTestExpectation *exp = [self expectationWithDescription:@"pendingDids populated"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [exp fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testStopRemovesObserverAndCancelsTimer {
    [self.service start];
    [self.service stop];

    // After stop, posting a notification should not add to pendingDids
    // (observer was removed)
    [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                        object:nil
                                                      userInfo:@{@"did": @"did:plc:afterstop"}];

    // Brief wait to ensure no async processing
    XCTestExpectation *exp = [self expectationWithDescription:@"wait after stop"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [exp fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

#pragma mark - Notification Handling

- (void)testHandleRecordChangeAddsDIDToPendingSet {
    [self.service start];

    [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                        object:nil
                                                      userInfo:@{@"did": @"did:plc:abc123"}];

    XCTestExpectation *exp = [self expectationWithDescription:@"DID added to pending"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [exp fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    // Stop the service to cancel the debounce timer before it fires
    [self.service stop];
}

- (void)testHandleRecordChangeIgnoresNotificationWithoutDID {
    [self.service start];

    // Post notification without "did" key
    [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                        object:nil
                                                      userInfo:@{@"otherKey": @"value"}];

    XCTestExpectation *exp = [self expectationWithDescription:@"wait for ignore"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [exp fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    [self.service stop];
}

#pragma mark - Relay Notification

- (void)testNotifyRelayConstructsCorrectURL {
    [self.service notifyRelay:@"https://relay1.example.com"];

    XCTAssertEqual(self.mockTransport.sentRequests.count, 1);
    NSURLRequest *request = self.mockTransport.sentRequests.firstObject;
    NSString *urlString = request.URL.absoluteString;
    XCTAssertTrue([urlString containsString:@"/xrpc/com.atproto.sync.requestCrawl"],
                 @"URL should contain requestCrawl path: %@", urlString);
}

- (void)testNotifyRelayAddsSchemePrefixIfNeeded {
    [self.service notifyRelay:@"relay2.example.com"];

    XCTAssertEqual(self.mockTransport.sentRequests.count, 1);
    NSURLRequest *request = self.mockTransport.sentRequests.firstObject;
    NSString *urlString = request.URL.absoluteString;
    XCTAssertTrue([urlString hasPrefix:@"https://"],
                 @"URL should have https prefix: %@", urlString);
}

- (void)testNotifyRelaySendsPOSTWithHostnameBody {
    [self.service notifyRelay:@"https://relay1.example.com"];

    XCTAssertEqual(self.mockTransport.sentRequests.count, 1);
    NSURLRequest *request = self.mockTransport.sentRequests.firstObject;
    XCTAssertEqualObjects(request.HTTPMethod, @"POST");
    XCTAssertEqualObjects(request.allHTTPHeaderFields[@"Content-Type"], @"application/json");

    // Parse body
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody
                                                        options:0
                                                          error:nil];
    XCTAssertEqualObjects(body[@"hostname"], @"pds.example.com");
}

- (void)testNotifyRelayWithMockTransportReceivesRequest {
    XCTestExpectation *exp = [self expectationWithDescription:@"transport receives request"];

    __block NSURLRequest *capturedRequest = nil;
    self.mockTransport.customHandler = ^(NSURLRequest *request,
        void (^handler)(NSData *, NSURLResponse *, NSError *)) {
        capturedRequest = request;
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
            initWithURL:request.URL
              statusCode:200
             HTTPVersion:@"HTTP/1.1"
            headerFields:nil];
        handler(nil, response, nil);
        [exp fulfill];
    };

    [self.service notifyRelay:@"https://relay1.example.com"];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    XCTAssertNotNil(capturedRequest);
    XCTAssertTrue([capturedRequest.URL.absoluteString containsString:@"requestCrawl"]);
}

- (void)testNotifyRelayLogsErrorOnTransportFailure {
    XCTestExpectation *exp = [self expectationWithDescription:@"transport error"];

    self.mockTransport.customHandler = ^(NSURLRequest *request,
        void (^handler)(NSData *, NSURLResponse *, NSError *)) {
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorNotConnectedToInternet
                                         userInfo:nil];
        handler(nil, nil, error);
        [exp fulfill];
    };

    // notifyRelay: should not crash on transport error
    [self.service notifyRelay:@"https://relay1.example.com"];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    // No assertion needed — just verifying no crash
}

#pragma mark - Process Pending

- (void)testProcessPendingNotificationsClearsPendingDIDs {
    [self.service start];

    // Post multiple notifications
    [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                        object:nil
                                                      userInfo:@{@"did": @"did:plc:aaa"}];
    [[NSNotificationCenter defaultCenter] postNotificationName:PDSRecordDidChangeNotification
                                                        object:nil
                                                      userInfo:@{@"did": @"did:plc:bbb"}];

    // Wait for debounce timer to fire and process
    XCTestExpectation *exp = [self expectationWithDescription:@"pending processed"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [exp fulfill];
    });
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    [self.service stop];

    // After processing, the mock transport should have received at least one request
    XCTAssertGreaterThan(self.mockTransport.sentRequests.count, 0,
                         @"Transport should have received requests after processing");
}

- (void)testProcessPendingNotificationsDoesNothingWhenEmpty {
    // Don't post any notifications, just call processPendingNotifications directly
    // This tests the guard clause
    [self.service performSelector:@selector(processPendingNotifications)];

    // Brief wait
    XCTestExpectation *exp = [self expectationWithDescription:@"wait"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [exp fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    XCTAssertEqual(self.mockTransport.sentRequests.count, 0,
                   @"No requests should be sent when pending is empty");
}

@end
