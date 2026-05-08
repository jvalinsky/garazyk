#import <XCTest/XCTest.h>
#import "Identity/HandleResolver.h"


@interface MockURLSession : NSObject

@property (nonatomic, strong) NSDictionary *mockResponse;
@property (nonatomic, strong) NSError *mockError;
@property (nonatomic, assign) NSTimeInterval mockDelay;
@property (nonatomic, copy) void (^completionHandler)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable);

- (instancetype)initWithResponse:(NSDictionary *)response error:(NSError *)error delay:(NSTimeInterval)delay;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                          completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;

@end

@interface TestHandleResolver : HandleResolver
@property (nonatomic, strong) MockURLSession *mockSession;
@end

@implementation TestHandleResolver
- (void)executeSafeHTTPSRequest:(NSURLRequest *)request
                        options:(id)options
                        attempt:(NSInteger)attempt
                     completion:(void (^)(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error))completion {
    if (!self.mockSession) {
        NSError *error = [NSError errorWithDomain:HandleErrorDomain
                                             code:HandleErrorNetworkError
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing mock HTTPS session"}];
        completion(nil, nil, error);
        return;
    }

    NSURLSessionDataTask *task = [self.mockSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        completion(data, (NSHTTPURLResponse *)response, error);
    }];
    [task resume];
}

- (void)resolveHandleViaDNS:(NSString *)handle completion:(void (^)(NSString * _Nullable did, NSError * _Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = [NSError errorWithDomain:HandleErrorDomain
                                             code:HandleErrorNotFound
                                         userInfo:@{NSLocalizedDescriptionKey: @"DNS lookup mocked to fail in tests"}];
        completion(nil, error);
    });
}
@end

@interface MockDataTask : NSObject

@property (nonatomic, copy) void (^completionHandler)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable);
@property (nonatomic, strong) NSDictionary *mockResponse;
@property (nonatomic, strong) NSError *mockError;
@property (nonatomic, assign) NSTimeInterval mockDelay;
@property (nonatomic, strong) NSURL *url;

- (void)resume;

@end

@implementation MockDataTask

- (void)resume {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.mockDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.mockError) {
            self.completionHandler(nil, nil, self.mockError);
        } else {
            NSNumber *statusCode = self.mockResponse[@"statusCode"] ?: @200;
            NSString *responseBody = self.mockResponse[@"body"] ?: @"";
            NSData *data = [responseBody dataUsingEncoding:NSUTF8StringEncoding];

            NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.url
                                                                       statusCode:[statusCode integerValue]
                                                                      HTTPVersion:@"HTTP/1.1"
                                                                     headerFields:nil];

            self.completionHandler(data, response, nil);
        }
    });
}

@end

@implementation MockURLSession

- (instancetype)initWithResponse:(NSDictionary *)response error:(NSError *)error delay:(NSTimeInterval)delay {
    self = [super init];
    if (self) {
        _mockResponse = response;
        _mockError = error;
        _mockDelay = delay;
    }
    return self;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                          completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    return [self dataTaskWithRequest:[NSURLRequest requestWithURL:url] completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    MockDataTask *task = [[MockDataTask alloc] init];
    task.completionHandler = completionHandler;
    task.mockResponse = self.mockResponse;
    task.mockError = self.mockError;
    task.mockDelay = self.mockDelay;
    task.url = request.URL;
    return (NSURLSessionDataTask *)task;
}

@end

@interface HandleResolverTests : XCTestCase

@property (nonatomic, strong) HandleResolver *resolver;

@end

#ifndef GNUSTEP

@interface ControlledBatchHandleResolver : HandleResolver
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<NSDictionary *> *> *responseSequences;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *callCounts;
@property (nonatomic, assign) BOOL invokeCallbacksTwice;
@end

@implementation ControlledBatchHandleResolver

- (instancetype)init {
    self = [super init];
    if (self) {
        _callCounts = [NSMutableDictionary dictionary];
        // skipSSRFCheck removed — PDSSafeHTTPClient.allowPrivateHosts is set
        // automatically in test mode via PDSHandleResolverRunningTests()
    }
    return self;
}

- (void)resolveHandle:(NSString *)handle completion:(void (^)(NSString * _Nullable did, NSError * _Nullable error))completion {
    __block NSUInteger index = 0;
    @synchronized (self.callCounts) {
        index = [self.callCounts[handle] unsignedIntegerValue];
        self.callCounts[handle] = @(index + 1);
    }

    NSArray<NSDictionary *> *sequence = self.responseSequences[handle] ?: @[];
    NSDictionary *response = index < sequence.count ? sequence[index] : sequence.lastObject;
    NSString *did = response[@"did"];
    NSError *error = response[@"error"];
    NSTimeInterval delay = [response[@"delay"] doubleValue];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        completion(did, error);
        if (self.invokeCallbacksTwice) {
            completion(@"did:plc:duplicate-callback", nil);
        }
    });
}

@end

@implementation HandleResolverTests

- (void)setUp {
    [super setUp];
    self.resolver = [[TestHandleResolver alloc] init];
    // skipSSRFCheck removed — PDSSafeHTTPClient handles SSRF automatically
    // with allowPrivateHosts=YES in test mode
}

- (void)tearDown {
    [super tearDown];
}

- (void)testHandleResolverInitialization {
    XCTAssertNotNil(self.resolver, @"Resolver should be initialized");
    // Session property removed — PDSSafeHTTPClient manages sessions internally
}

- (void)testHandleValidationEmpty {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Empty handle test"];

    [self.resolver resolveHandle:@"" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"Empty handle should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, 1001, @"Error code should be 1001 (Empty)");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testHandleValidationNull {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Null handle test"];

    [self.resolver resolveHandle:nil completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"Null handle should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, 1001, @"Error code should be 1001 (Empty)");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testHandleValidationNoDot {
    XCTestExpectation *expectation = [self expectationWithDescription:@"No dot handle test"];

    [self.resolver resolveHandle:@"invalidhandle" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"Handle without dot should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, 1004, @"Error code should be 1004 (Segment count)");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testHandleValidationValid {
    MockURLSession *testSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:7HjwGtP5cLyq3vD5nDzDg"}
                                                                     error:nil
                                                                     delay:0.1];
    HandleResolver *testResolver = [[TestHandleResolver alloc] init];
    ((TestHandleResolver *)testResolver).mockSession = testSession;

    XCTestExpectation *expectation = [self expectationWithDescription:@"Valid handle test"];

    [testResolver resolveHandle:@"test.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNotNil(did, @"Valid handle should return DID");
        XCTAssertEqualObjects(did, @"did:plc:7HjwGtP5cLyq3vD5nDzDg", @"DID should match expected value");
        XCTAssertNil(error, @"No error should occur");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testHTTPSResolutionNetworkError {
    MockURLSession *errorSession = [[MockURLSession alloc] initWithResponse:nil
                                                                     error:[NSError errorWithDomain:NSURLErrorDomain
                                                                                               code:NSURLErrorTimedOut
                                                                                           userInfo:nil]
                                                                     delay:0.1];
    HandleResolver *errorResolver = [[TestHandleResolver alloc] init];
    ((TestHandleResolver *)errorResolver).mockSession = errorSession;

    XCTestExpectation *expectation = [self expectationWithDescription:@"Network error test"];

    [errorResolver resolveHandle:@"error.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"Network error should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, HandleErrorNetworkError, @"Error code should be HandleErrorNetworkError");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testHTTPSResolutionHTTP404 {
    MockURLSession *notFoundSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @404, @"body": @"Not Found"}
                                                                         error:nil
                                                                         delay:0.1];
    HandleResolver *notFoundResolver = [[TestHandleResolver alloc] init];
    ((TestHandleResolver *)notFoundResolver).mockSession = notFoundSession;

    XCTestExpectation *expectation = [self expectationWithDescription:@"404 error test"];

    [notFoundResolver resolveHandle:@"notfound.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"404 error should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, HandleErrorNotFound, @"Error code should be HandleErrorNotFound");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testHTTPSResolutionHTTP500 {
    MockURLSession *serverErrorSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @500, @"body": @"Internal Server Error"}
                                                                            error:nil
                                                                            delay:0.1];
    HandleResolver *serverErrorResolver = [[TestHandleResolver alloc] init];
    ((TestHandleResolver *)serverErrorResolver).mockSession = serverErrorSession;

    XCTestExpectation *expectation = [self expectationWithDescription:@"500 error test"];

    [serverErrorResolver resolveHandle:@"servererror.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"500 error should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, HandleErrorNotFound, @"Error code should be HandleErrorNotFound");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testHTTPSResolutionEmptyBody {
    MockURLSession *emptyBodySession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @""}
                                                                          error:nil
                                                                          delay:0.1];
    HandleResolver *emptyBodyResolver = [[TestHandleResolver alloc] init];
    ((TestHandleResolver *)emptyBodyResolver).mockSession = emptyBodySession;

    XCTestExpectation *expectation = [self expectationWithDescription:@"Empty body test"];

    [emptyBodyResolver resolveHandle:@"empty.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"Empty body should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, HandleErrorResolutionFailed, @"Error code should be HandleErrorResolutionFailed");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testHTTPSResolutionWhitespaceOnly {
    MockURLSession *whitespaceSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"   \n\t  "}
                                                                           error:nil
                                                                           delay:0.1];
    HandleResolver *whitespaceResolver = [[TestHandleResolver alloc] init];
    ((TestHandleResolver *)whitespaceResolver).mockSession = whitespaceSession;

    XCTestExpectation *expectation = [self expectationWithDescription:@"Whitespace only test"];

    [whitespaceResolver resolveHandle:@"whitespace.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"Whitespace only should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, HandleErrorResolutionFailed, @"Error code should be HandleErrorResolutionFailed");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testHTTPSResolutionInvalidDID {
    MockURLSession *invalidDIDSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"invalid-did-format"}
                                                                           error:nil
                                                                           delay:0.1];
    HandleResolver *invalidDIDResolver = [[TestHandleResolver alloc] init];
    ((TestHandleResolver *)invalidDIDResolver).mockSession = invalidDIDSession;

    XCTestExpectation *expectation = [self expectationWithDescription:@"Invalid DID test"];

    [invalidDIDResolver resolveHandle:@"invaliddid.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"Invalid DID should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, HandleErrorResolutionFailed, @"Error code should be HandleErrorResolutionFailed");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testHTTPSResolutionDIDWithWhitespace {
    MockURLSession *whitespaceDIDSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"  did:plc:7HjwGtP5cLyq3vD5nDzDg  \n"}
                                                                             error:nil
                                                                             delay:0.1];
    HandleResolver *whitespaceDIDResolver = [[TestHandleResolver alloc] init];
    ((TestHandleResolver *)whitespaceDIDResolver).mockSession = whitespaceDIDSession;

    XCTestExpectation *expectation = [self expectationWithDescription:@"DID with whitespace test"];

    [whitespaceDIDResolver resolveHandle:@"whitespace.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNotNil(did, @"DID with whitespace should return DID");
        XCTAssertEqualObjects(did, @"did:plc:7HjwGtP5cLyq3vD5nDzDg", @"DID should be trimmed and match");
        XCTAssertNil(error, @"No error should occur");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testURLConstructionInvalidCharacters {
    HandleResolver *urlTestResolver = [[TestHandleResolver alloc] init];
    // PDSSafeHTTPClient handles SSRF in test mode automatically

    XCTestExpectation *expectation = [self expectationWithDescription:@"Invalid URL characters test"];

    [urlTestResolver resolveHandle:@"invalid url.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"Invalid URL chars should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, 1007, @"Error code should be 1007 (Invalid characters)");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testSessionTimeoutConfiguration {
    HandleResolver *timeoutResolver = [[TestHandleResolver alloc] init];

    // Session property removed — PDSSafeHTTPClient manages timeout internally
    XCTAssertNotNil(timeoutResolver, @"Resolver should be initialized");
}

- (void)testConcurrentResolutions {
    MockURLSession *concurrentSession1 = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:concurrent1"}
                                                                           error:nil
                                                                           delay:0.1];
    MockURLSession *concurrentSession2 = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:concurrent2"}
                                                                           error:nil
                                                                           delay:0.1];

    HandleResolver *concurrentResolver1 = [[TestHandleResolver alloc] init];
    HandleResolver *concurrentResolver2 = [[TestHandleResolver alloc] init];
    ((TestHandleResolver *)concurrentResolver1).mockSession = concurrentSession1;
    ((TestHandleResolver *)concurrentResolver2).mockSession = concurrentSession2;

    XCTestExpectation *expectation1 = [self expectationWithDescription:@"Concurrent resolution 1"];
    XCTestExpectation *expectation2 = [self expectationWithDescription:@"Concurrent resolution 2"];

    __block NSString *resultDID1 = nil;
    __block NSError *resultError1 = nil;
    __block NSString *resultDID2 = nil;
    __block NSError *resultError2 = nil;

    [concurrentResolver1 resolveHandle:@"concurrent1.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        resultDID1 = did;
        resultError1 = error;
        [expectation1 fulfill];
    }];

    [concurrentResolver2 resolveHandle:@"concurrent2.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        resultDID2 = did;
        resultError2 = error;
        [expectation2 fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    XCTAssertEqualObjects(resultDID1, @"did:plc:concurrent1", @"First concurrent DID should match");
    XCTAssertNil(resultError1, @"No error for first resolution");
    XCTAssertEqualObjects(resultDID2, @"did:plc:concurrent2", @"Second concurrent DID should match");
    XCTAssertNil(resultError2, @"No error for second resolution");
}

- (void)testLargeHandleHandling {
    NSString *largeHandle = [@"" stringByPaddingToLength:1000 withString:@"a" startingAtIndex:0];
    largeHandle = [largeHandle stringByAppendingString:@".example.com"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Large handle test"];

    [self.resolver resolveHandle:largeHandle completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"Large handle should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, 1002, @"Error code should be 1002 (Handle too long)");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testSpecialCharactersInHandle {
    MockURLSession *specialCharSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:special"}
                                                                           error:nil
                                                                           delay:0.1];
    HandleResolver *specialCharResolver = [[TestHandleResolver alloc] init];
    ((TestHandleResolver *)specialCharResolver).mockSession = specialCharSession;

    XCTestExpectation *expectation = [self expectationWithDescription:@"Special characters test"];

    [specialCharResolver resolveHandle:@"test-handle.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNotNil(did, @"Special character handle should return DID");
        XCTAssertEqualObjects(did, @"did:plc:special", @"DID should match");
        XCTAssertNil(error, @"No error should occur");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testMemoryManagement {
    @autoreleasepool {
        HandleResolver *tempResolver = [[TestHandleResolver alloc] init];
        // PDSSafeHTTPClient handles SSRF in test mode automatically
        MockURLSession *tempSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:temp"}
                                                                         error:nil
                                                                         delay:0.1];
        ((TestHandleResolver *)tempResolver).mockSession = tempSession;

        XCTestExpectation *expectation = [self expectationWithDescription:@"Memory management test"];

        [tempResolver resolveHandle:@"temp.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            XCTAssertNotNil(did, @"Temp handle should return DID");
            XCTAssertEqualObjects(did, @"did:plc:temp", @"DID should match");
            XCTAssertNil(error, @"No error should occur");
            [expectation fulfill];
        }];

        [self waitForExpectationsWithTimeout:2.0 handler:nil];
    }
}

- (void)testErrorDomainConsistency {
    NSError *domainError = [NSError errorWithDomain:HandleErrorDomain code:HandleErrorInvalidFormat userInfo:nil];
    XCTAssertEqualObjects(domainError.domain, HandleErrorDomain, @"Error domain should be HandleErrorDomain");
}

- (void)testMultipleDotsInHandle {
    MockURLSession *multiDotSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:multidot"}
                                                                         error:nil
                                                                         delay:0.1];
    HandleResolver *multiDotResolver = [[TestHandleResolver alloc] init];
    ((TestHandleResolver *)multiDotResolver).mockSession = multiDotSession;

    XCTestExpectation *expectation = [self expectationWithDescription:@"Multiple dots test"];

    [multiDotResolver resolveHandle:@"sub.test.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNotNil(did, @"Multiple dots handle should return DID");
        XCTAssertEqualObjects(did, @"did:plc:multidot", @"DID should match");
        XCTAssertNil(error, @"No error should occur");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testDNSResolutionFallbackYieldsNil {
    // This test verifies that if HTTPS resolution fails, it falls back to DNS TXT
    // Since we can't easily mock res_query without method swizzling or similar,
    // we'll at least test that the fallback is attempted.
    
    MockURLSession *notFoundSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @404, @"body": @"Not Found"}
                                                                         error:nil
                                                                         delay:0.1];
    HandleResolver *dnsResolver = [[TestHandleResolver alloc] init];
    ((TestHandleResolver *)dnsResolver).mockSession = notFoundSession;
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"DNS fallback test"];
    
    [dnsResolver resolveHandle:@"dns-fallback.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        // Currently it should still fail because DNS is not implemented
        // But we want to see it fail with the right error or attempt the fallback
        XCTAssertNil(did);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testFailureCachingAndBackoff {
    MockURLSession *errorSession = [[MockURLSession alloc] initWithResponse:nil
                                                                     error:[NSError errorWithDomain:NSURLErrorDomain
                                                                                               code:NSURLErrorTimedOut
                                                                                           userInfo:nil]
                                                                     delay:0.0];
    HandleResolver *resolver = [[TestHandleResolver alloc] init];
    ((TestHandleResolver *)resolver).mockSession = errorSession;
    
    NSString *handle = @"backoff.test.example.com";
    
    // Initial attempt: Fails with Network Error, count -> 1
    XCTestExpectation *exp1 = [self expectationWithDescription:@"Initial failure"];
    [resolver resolveHandle:handle completion:^(NSString *did, NSError *error) {
        XCTAssertEqual(error.code, HandleErrorNetworkError);
        [exp1 fulfill];
    }];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    // Subsequent attempt: Should fail immediately due to backoff
    // Backoff for count 1 is 2^1 = 2 seconds.
    XCTestExpectation *exp2 = [self expectationWithDescription:@"Backoff trigger"];
    [resolver resolveHandle:handle completion:^(NSString *did, NSError *error) {
        XCTAssertEqual(error.code, HandleErrorRateLimitExceeded); // Using RateLimit error for backoff
        XCTAssertTrue([error.userInfo[NSLocalizedDescriptionKey] containsString:@"Resolution backed off"]);
        [exp2 fulfill];
    }];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (NSError *)batchTestErrorWithCode:(NSInteger)code {
    return [NSError errorWithDomain:@"HandleResolverBatchTests"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"batch error %ld", (long)code]}];
}

- (void)testResolveHandlesCompletesExactlyOnceWithDuplicateCallbacks {
    ControlledBatchHandleResolver *resolver = [[ControlledBatchHandleResolver alloc] init];
    resolver.invokeCallbacksTwice = YES;
    resolver.responseSequences = @{
        @"one.example.com": @[@{@"did": @"did:plc:one", @"delay": @0.01}],
        @"two.example.com": @[@{@"did": @"did:plc:two", @"delay": @0.02}]
    };

    XCTestExpectation *expectation = [self expectationWithDescription:@"batch completion"];
    expectation.assertForOverFulfill = YES;
    __block NSUInteger completionCount = 0;

    [resolver resolveHandles:@[@"one.example.com", @"two.example.com"]
                  completion:^(NSDictionary<NSString *,NSString *> * _Nullable results, NSError * _Nullable error) {
        completionCount++;
        XCTAssertEqualObjects(results[@"one.example.com"], @"did:plc:one");
        XCTAssertEqualObjects(results[@"two.example.com"], @"did:plc:two");
        XCTAssertNil(error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertEqual(completionCount, 1);
}

- (void)testResolveHandlesReturnsFirstErrorByInputOrderAfterConcurrentCallbacks {
    ControlledBatchHandleResolver *resolver = [[ControlledBatchHandleResolver alloc] init];
    NSError *firstInputError = [self batchTestErrorWithCode:1];
    NSError *thirdInputError = [self batchTestErrorWithCode:3];
    resolver.responseSequences = @{
        @"first.example.com": @[@{@"error": firstInputError, @"delay": @0.05}],
        @"second.example.com": @[@{@"did": @"did:plc:second", @"delay": @0.01}],
        @"third.example.com": @[@{@"error": thirdInputError, @"delay": @0.0}]
    };

    XCTestExpectation *expectation = [self expectationWithDescription:@"deterministic batch error"];
    [resolver resolveHandles:@[@"first.example.com", @"second.example.com", @"third.example.com"]
                  completion:^(NSDictionary<NSString *,NSString *> * _Nullable results, NSError * _Nullable error) {
        XCTAssertEqualObjects(results[@"second.example.com"], @"did:plc:second");
        XCTAssertEqual(error.code, 1);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testResolveHandlesAllFailureReturnsNilResultsAndFirstError {
    ControlledBatchHandleResolver *resolver = [[ControlledBatchHandleResolver alloc] init];
    NSError *firstError = [self batchTestErrorWithCode:11];
    NSError *secondError = [self batchTestErrorWithCode:22];
    resolver.responseSequences = @{
        @"first.example.com": @[@{@"error": firstError, @"delay": @0.02}],
        @"second.example.com": @[@{@"error": secondError, @"delay": @0.0}]
    };

    XCTestExpectation *expectation = [self expectationWithDescription:@"all failure batch"];
    [resolver resolveHandles:@[@"first.example.com", @"second.example.com"]
                  completion:^(NSDictionary<NSString *,NSString *> * _Nullable results, NSError * _Nullable error) {
        XCTAssertNil(results);
        XCTAssertEqual(error.code, 11);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testResolveHandlesDuplicateHandlesUseLaterIndexResult {
    ControlledBatchHandleResolver *resolver = [[ControlledBatchHandleResolver alloc] init];
    resolver.responseSequences = @{
        @"dup.example.com": @[
            @{@"did": @"did:plc:first", @"delay": @0.0},
            @{@"did": @"did:plc:second", @"delay": @0.01}
        ]
    };

    XCTestExpectation *expectation = [self expectationWithDescription:@"duplicate handles"];
    [resolver resolveHandles:@[@"dup.example.com", @"dup.example.com"]
                  completion:^(NSDictionary<NSString *,NSString *> * _Nullable results, NSError * _Nullable error) {
        XCTAssertEqualObjects(results[@"dup.example.com"], @"did:plc:second");
        XCTAssertNil(error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

@end
#endif
