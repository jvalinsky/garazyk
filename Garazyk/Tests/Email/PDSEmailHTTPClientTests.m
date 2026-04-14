#import <XCTest/XCTest.h>
#import "Email/PDSEmailHTTPClient.h"

@interface TestHTTPTask : NSURLSessionDataTask
@property (nonatomic, copy) void (^onResume)(void);
@end

@implementation TestHTTPTask
- (void)resume {
    if (self.onResume) {
        self.onResume();
    }
}
@end

@interface TestHTTPSession : NSObject
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *outcomes;
@property (nonatomic, strong) NSMutableArray<NSURLRequest *> *capturedRequests;
@property (nonatomic, assign) NSUInteger callCount;
@end

@implementation TestHTTPSession

- (instancetype)init {
    self = [super init];
    if (self) {
        _outcomes = [NSMutableArray array];
        _capturedRequests = [NSMutableArray array];
        _callCount = 0;
    }
    return self;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    [self.capturedRequests addObject:request];
    NSUInteger index = self.callCount;
    self.callCount += 1;

    NSDictionary *outcome = index < self.outcomes.count ? self.outcomes[index] : @{};
    TestHTTPTask *task = [[TestHTTPTask alloc] init];
    __weak typeof(self) weakSelf = self;
    task.onResume = ^{
        __unused typeof(weakSelf) strongSelf = weakSelf;
        completionHandler(outcome[@"data"], outcome[@"response"], outcome[@"error"]);
    };
    return task;
}

@end

@interface PDSEmailHTTPClientTests : XCTestCase
@end

@implementation PDSEmailHTTPClientTests

- (PDSEmailHTTPClient *)clientWithSession:(TestHTTPSession *)session {
    NSURL *baseURL = [NSURL URLWithString:@"https://api.example.com"];
    PDSEmailHTTPClient *client = [[PDSEmailHTTPClient alloc] initWithBaseURL:baseURL apiKey:@"test-api-key"];
    [client setValue:session forKey:@"session"];
    return client;
}

- (NSHTTPURLResponse *)responseWithStatus:(NSInteger)status {
    return [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://api.example.com/email"]
                                       statusCode:status
                                      HTTPVersion:@"HTTP/1.1"
                                     headerFields:@{}];
}

- (void)testInitAndDefaults {
    NSURL *baseURL = [NSURL URLWithString:@"https://api.example.com"];
    PDSEmailHTTPClient *client = [[PDSEmailHTTPClient alloc] initWithBaseURL:baseURL apiKey:@"test-api-key"];
    XCTAssertEqualObjects(client.baseURL, baseURL);
    XCTAssertEqualObjects(client.apiKey, @"test-api-key");
    XCTAssertEqual(client.timeoutInterval, 30.0);
    XCTAssertEqual(client.maxRetries, 3);
}

- (void)testPostPathSuccessParsesDictionaryAndSetsHeaders {
    TestHTTPSession *session = [[TestHTTPSession alloc] init];
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"ok": @YES} options:0 error:nil];
    [session.outcomes addObject:@{
        @"data": jsonData,
        @"response": [self responseWithStatus:200]
    }];

    PDSEmailHTTPClient *client = [self clientWithSession:session];
    client.timeoutInterval = 60.0;

    NSError *error = nil;
    NSDictionary *result = [client postPath:@"emails" body:@{@"to": @"a@example.com"} error:&error];

    XCTAssertNil(error);
    XCTAssertEqualObjects(result[@"ok"], @YES);
    XCTAssertEqual(session.callCount, 1u);

    NSURLRequest *request = session.capturedRequests.firstObject;
    XCTAssertEqualObjects(request.HTTPMethod, @"POST");
    XCTAssertEqualObjects([request valueForHTTPHeaderField:@"Content-Type"], @"application/json");
    XCTAssertEqualObjects([request valueForHTTPHeaderField:@"Authorization"], @"Bearer test-api-key");
    XCTAssertEqualWithAccuracy(request.timeoutInterval, 60.0, 0.001);
}

- (void)testPostPathSerializationFailureReturnsError {
    TestHTTPSession *session = [[TestHTTPSession alloc] init];
    PDSEmailHTTPClient *client = [self clientWithSession:session];

    NSError *error = nil;
    NSDictionary *result = [client postPath:@"emails" body:@{@"invalid": [NSObject new]} error:&error];

    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(session.callCount, 0u);
}

- (void)testPostPathClientErrorStopsWithoutRetry {
    TestHTTPSession *session = [[TestHTTPSession alloc] init];
    NSData *body = [@"{\"message\":\"bad\"}" dataUsingEncoding:NSUTF8StringEncoding];
    [session.outcomes addObject:@{
        @"data": body,
        @"response": [self responseWithStatus:400]
    }];

    PDSEmailHTTPClient *client = [self clientWithSession:session];
    client.maxRetries = 5;

    NSError *error = nil;
    NSDictionary *result = [client postPath:@"emails" body:@{@"to": @"a@example.com"} error:&error];

    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"PDSEmailHTTPClientErrorDomain");
    XCTAssertEqual(error.code, 400);
    XCTAssertEqual(session.callCount, 1u);
}

- (void)testPostPathHTTPErrorParsesResendMessage {
    TestHTTPSession *session = [[TestHTTPSession alloc] init];
    NSData *errorData = [NSJSONSerialization dataWithJSONObject:@{
        @"statusCode": @422,
        @"name": @"invalid_parameter",
        @"message": @"email is invalid"
    } options:0 error:nil];
    [session.outcomes addObject:@{
        @"data": errorData,
        @"response": [self responseWithStatus:422]
    }];

    PDSEmailHTTPClient *client = [self clientWithSession:session];
    client.maxRetries = 0;

    NSError *error = nil;
    NSDictionary *result = [client postPath:@"emails" body:@{@"to": @"bad"} error:&error];

    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 422);
    XCTAssertEqualObjects(error.userInfo[@"resendErrorName"], @"invalid_parameter");
    XCTAssertEqualObjects(error.userInfo[@"resendErrorMessage"], @"email is invalid");
    XCTAssertEqualObjects(error.localizedDescription, @"email is invalid");
}

- (void)testPostPathSuccessWithInvalidJSONDataReturnsParseError {
    TestHTTPSession *session = [[TestHTTPSession alloc] init];
    NSData *invalidJSON = [@"not-json" dataUsingEncoding:NSUTF8StringEncoding];
    [session.outcomes addObject:@{
        @"data": invalidJSON,
        @"response": [self responseWithStatus:200]
    }];

    PDSEmailHTTPClient *client = [self clientWithSession:session];
    client.maxRetries = 0;

    NSError *error = nil;
    NSDictionary *result = [client postPath:@"emails" body:@{@"to": @"a@example.com"} error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testPostPathSuccessWithEmptyBodyReturnsNilResultWithoutError {
    TestHTTPSession *session = [[TestHTTPSession alloc] init];
    [session.outcomes addObject:@{
        @"data": [NSData data],
        @"response": [self responseWithStatus:200]
    }];

    PDSEmailHTTPClient *client = [self clientWithSession:session];
    client.maxRetries = 0;

    NSError *error = nil;
    NSDictionary *result = [client postPath:@"emails" body:@{@"to": @"a@example.com"} error:&error];
    XCTAssertNil(error);
    XCTAssertNil(result);
}

- (void)testPostPathTaskErrorIsSurfaced {
    TestHTTPSession *session = [[TestHTTPSession alloc] init];
    NSError *taskError = [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorTimedOut
                                         userInfo:nil];
    [session.outcomes addObject:@{
        @"error": taskError
    }];

    PDSEmailHTTPClient *client = [self clientWithSession:session];
    client.maxRetries = 0;

    NSError *error = nil;
    NSDictionary *result = [client postPath:@"emails" body:@{@"to": @"a@example.com"} error:&error];
    XCTAssertNil(result);
    XCTAssertEqualObjects(error, taskError);
}

@end
