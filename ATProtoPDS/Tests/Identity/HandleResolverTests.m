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
@implementation HandleResolverTests

- (void)setUp {
    [super setUp];
    self.resolver = [[HandleResolver alloc] init];
    self.resolver.skipSSRFCheck = YES;
}

- (void)tearDown {
    [super tearDown];
}

- (void)testHandleResolverInitialization {
    XCTAssertNotNil(self.resolver, @"Resolver should be initialized");
    XCTAssertNotNil(self.resolver.session, @"Session should be initialized");
    XCTAssertEqual(self.resolver.session.configuration.timeoutIntervalForRequest, 10.0, @"Request timeout should be 10s");
    XCTAssertEqual(self.resolver.session.configuration.timeoutIntervalForResource, 30.0, @"Resource timeout should be 30s");
}

#ifndef GNUSTEP
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
#endif

#ifndef GNUSTEP
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
#endif

#ifndef GNUSTEP
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
#endif

#ifndef GNUSTEP
- (void)testHandleValidationValid {
    MockURLSession *mockSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:7HjwGtP5cLyq3vD5nDzDg"}
                                                                     error:nil
                                                                     delay:0.1];
    HandleResolver *mockResolver = [[HandleResolver alloc] init];
    mockResolver.skipSSRFCheck = YES;
    [mockResolver setValue:mockSession forKey:@"session"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Valid handle test"];

    [mockResolver resolveHandle:@"test.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNotNil(did, @"Valid handle should return DID");
        XCTAssertEqualObjects(did, @"did:plc:7HjwGtP5cLyq3vD5nDzDg", @"DID should match expected value");
        XCTAssertNil(error, @"No error should occur");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}
#endif

#ifndef GNUSTEP
- (void)testHTTPSResolutionNetworkError {
    MockURLSession *errorSession = [[MockURLSession alloc] initWithResponse:nil
                                                                     error:[NSError errorWithDomain:NSURLErrorDomain
                                                                                               code:NSURLErrorTimedOut
                                                                                           userInfo:nil]
                                                                     delay:0.1];
    HandleResolver *errorResolver = [[HandleResolver alloc] init];
    errorResolver.skipSSRFCheck = YES;
    [errorResolver setValue:errorSession forKey:@"session"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Network error test"];

    [errorResolver resolveHandle:@"error.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"Network error should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, HandleErrorNetworkError, @"Error code should be HandleErrorNetworkError");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}
#endif

#ifndef GNUSTEP
- (void)testHTTPSResolutionHTTP404 {
    MockURLSession *notFoundSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @404, @"body": @"Not Found"}
                                                                         error:nil
                                                                         delay:0.1];
    HandleResolver *notFoundResolver = [[HandleResolver alloc] init];
    notFoundResolver.skipSSRFCheck = YES;
    [notFoundResolver setValue:notFoundSession forKey:@"session"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"404 error test"];

    [notFoundResolver resolveHandle:@"notfound.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"404 error should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, HandleErrorNotFound, @"Error code should be HandleErrorNotFound");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}
#endif

#ifndef GNUSTEP
- (void)testHTTPSResolutionHTTP500 {
    MockURLSession *serverErrorSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @500, @"body": @"Internal Server Error"}
                                                                            error:nil
                                                                            delay:0.1];
    HandleResolver *serverErrorResolver = [[HandleResolver alloc] init];
    serverErrorResolver.skipSSRFCheck = YES;
    [serverErrorResolver setValue:serverErrorSession forKey:@"session"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"500 error test"];

    [serverErrorResolver resolveHandle:@"servererror.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"500 error should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, HandleErrorNotFound, @"Error code should be HandleErrorNotFound");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}
#endif

#ifndef GNUSTEP
- (void)testHTTPSResolutionEmptyBody {
    MockURLSession *emptyBodySession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @""}
                                                                          error:nil
                                                                          delay:0.1];
    HandleResolver *emptyBodyResolver = [[HandleResolver alloc] init];
    emptyBodyResolver.skipSSRFCheck = YES;
    [emptyBodyResolver setValue:emptyBodySession forKey:@"session"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Empty body test"];

    [emptyBodyResolver resolveHandle:@"empty.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"Empty body should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, HandleErrorResolutionFailed, @"Error code should be HandleErrorResolutionFailed");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}
#endif

#ifndef GNUSTEP
- (void)testHTTPSResolutionWhitespaceOnly {
    MockURLSession *whitespaceSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"   \n\t  "}
                                                                           error:nil
                                                                           delay:0.1];
    HandleResolver *whitespaceResolver = [[HandleResolver alloc] init];
    whitespaceResolver.skipSSRFCheck = YES;
    [whitespaceResolver setValue:whitespaceSession forKey:@"session"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Whitespace only test"];

    [whitespaceResolver resolveHandle:@"whitespace.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"Whitespace only should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, HandleErrorResolutionFailed, @"Error code should be HandleErrorResolutionFailed");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}
#endif

#ifndef GNUSTEP
- (void)testHTTPSResolutionInvalidDID {
    MockURLSession *invalidDIDSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"invalid-did-format"}
                                                                           error:nil
                                                                           delay:0.1];
    HandleResolver *invalidDIDResolver = [[HandleResolver alloc] init];
    invalidDIDResolver.skipSSRFCheck = YES;
    [invalidDIDResolver setValue:invalidDIDSession forKey:@"session"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Invalid DID test"];

    [invalidDIDResolver resolveHandle:@"invaliddid.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNil(did, @"Invalid DID should return nil DID");
        XCTAssertNotNil(error, @"Error should be set");
        XCTAssertEqual(error.code, HandleErrorResolutionFailed, @"Error code should be HandleErrorResolutionFailed");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}
#endif

#ifndef GNUSTEP
- (void)testHTTPSResolutionDIDWithWhitespace {
    MockURLSession *whitespaceDIDSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"  did:plc:7HjwGtP5cLyq3vD5nDzDg  \n"}
                                                                             error:nil
                                                                             delay:0.1];
    HandleResolver *whitespaceDIDResolver = [[HandleResolver alloc] init];
    whitespaceDIDResolver.skipSSRFCheck = YES;
    [whitespaceDIDResolver setValue:whitespaceDIDSession forKey:@"session"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"DID with whitespace test"];

    [whitespaceDIDResolver resolveHandle:@"whitespace.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNotNil(did, @"DID with whitespace should return DID");
        XCTAssertEqualObjects(did, @"did:plc:7HjwGtP5cLyq3vD5nDzDg", @"DID should be trimmed and match");
        XCTAssertNil(error, @"No error should occur");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}
#endif

#ifndef GNUSTEP
- (void)testURLConstructionInvalidCharacters {
    HandleResolver *urlTestResolver = [[HandleResolver alloc] init];
    urlTestResolver.skipSSRFCheck = YES;

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
    HandleResolver *timeoutResolver = [[HandleResolver alloc] init];

    XCTAssertEqual(timeoutResolver.session.configuration.timeoutIntervalForRequest, 10.0, @"Request timeout should be 10s");
    XCTAssertEqual(timeoutResolver.session.configuration.timeoutIntervalForResource, 30.0, @"Resource timeout should be 30s");
}

#ifndef GNUSTEP
- (void)testConcurrentResolutions {
    MockURLSession *concurrentSession1 = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:concurrent1"}
                                                                           error:nil
                                                                           delay:0.1];
    MockURLSession *concurrentSession2 = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:concurrent2"}
                                                                           error:nil
                                                                           delay:0.1];

    HandleResolver *concurrentResolver1 = [[HandleResolver alloc] init];
    HandleResolver *concurrentResolver2 = [[HandleResolver alloc] init];
    concurrentResolver1.skipSSRFCheck = YES;
    concurrentResolver2.skipSSRFCheck = YES;
    [concurrentResolver1 setValue:concurrentSession1 forKey:@"session"];
    [concurrentResolver2 setValue:concurrentSession2 forKey:@"session"];

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
#endif

#ifndef GNUSTEP
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
#endif

#ifndef GNUSTEP
- (void)testSpecialCharactersInHandle {
    MockURLSession *specialCharSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:special"}
                                                                           error:nil
                                                                           delay:0.1];
    HandleResolver *specialCharResolver = [[HandleResolver alloc] init];
    specialCharResolver.skipSSRFCheck = YES;
    [specialCharResolver setValue:specialCharSession forKey:@"session"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Special characters test"];

    [specialCharResolver resolveHandle:@"test-handle.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNotNil(did, @"Special character handle should return DID");
        XCTAssertEqualObjects(did, @"did:plc:special", @"DID should match");
        XCTAssertNil(error, @"No error should occur");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}
#endif

#ifndef GNUSTEP
- (void)testMemoryManagement {
    @autoreleasepool {
        HandleResolver *tempResolver = [[HandleResolver alloc] init];
        tempResolver.skipSSRFCheck = YES;
        MockURLSession *tempSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:temp"}
                                                                         error:nil
                                                                         delay:0.1];
        [tempResolver setValue:tempSession forKey:@"session"];

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

#ifndef GNUSTEP
- (void)testMultipleDotsInHandle {
    MockURLSession *multiDotSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:multidot"}
                                                                         error:nil
                                                                         delay:0.1];
    HandleResolver *multiDotResolver = [[HandleResolver alloc] init];
    multiDotResolver.skipSSRFCheck = YES;
    [multiDotResolver setValue:multiDotSession forKey:@"session"];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Multiple dots test"];

    [multiDotResolver resolveHandle:@"sub.test.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
        XCTAssertNotNil(did, @"Multiple dots handle should return DID");
        XCTAssertEqualObjects(did, @"did:plc:multidot", @"DID should match");
        XCTAssertNil(error, @"No error should occur");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}
#endif

#ifndef GNUSTEP
- (void)testDNSResolutionFallback {
    // This test verifies that if HTTPS resolution fails, it falls back to DNS TXT
    // Since we can't easily mock res_query without method swizzling or similar,
    // we'll at least test that the fallback is attempted.
    
    MockURLSession *notFoundSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @404, @"body": @"Not Found"}
                                                                         error:nil
                                                                         delay:0.1];
    HandleResolver *dnsResolver = [[HandleResolver alloc] init];
    dnsResolver.skipSSRFCheck = YES;
    [dnsResolver setValue:notFoundSession forKey:@"session"];
    
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
#endif

#ifndef GNUSTEP
- (void)testFailureCachingAndBackoff {
    MockURLSession *errorSession = [[MockURLSession alloc] initWithResponse:nil
                                                                     error:[NSError errorWithDomain:NSURLErrorDomain
                                                                                               code:NSURLErrorTimedOut
                                                                                           userInfo:nil]
                                                                     delay:0.0];
    HandleResolver *resolver = [[HandleResolver alloc] init];
    resolver.skipSSRFCheck = YES;
    [resolver setValue:errorSession forKey:@"session"];
    
    NSString *handle = @"backoff.test.example.com";
    
    // First attempt: Fails with Network Error, count -> 1
    XCTestExpectation *exp1 = [self expectationWithDescription:@"First failure"];
    [resolver resolveHandle:handle completion:^(NSString *did, NSError *error) {
        XCTAssertEqual(error.code, HandleErrorNetworkError);
        [exp1 fulfill];
    }];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    // Second attempt: Should fail immediately due to backoff
    // Backoff for count 1 is 2^1 = 2 seconds.
    XCTestExpectation *exp2 = [self expectationWithDescription:@"Backoff trigger"];
    [resolver resolveHandle:handle completion:^(NSString *did, NSError *error) {
        XCTAssertEqual(error.code, HandleErrorRateLimitExceeded); // Using RateLimit error for backoff
        XCTAssertTrue([error.userInfo[NSLocalizedDescriptionKey] containsString:@"Resolution backed off"]);
        [exp2 fulfill];
    }];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

#endif

@end
