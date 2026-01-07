#import <Foundation/Foundation.h>
#import "HandleResolver.h"

// Test category to expose private methods and add mock functionality for testing
@interface HandleResolver (Testing)

// Mock response storage for testing
@property (nonatomic, strong) NSDictionary *mockResponse;
@property (nonatomic, strong) NSError *mockError;
@property (nonatomic, assign) NSTimeInterval mockDelay;

// Private method exposure
- (void)resolveHandleViaHTTPS:(NSString *)handle
                   completion:(void (^)(NSString * _Nullable did, NSError * _Nullable error))completion;

@end

// Mock URLSession for testing
@interface MockURLSession : NSObject

@property (nonatomic, strong) NSDictionary *mockResponse;
@property (nonatomic, strong) NSError *mockError;
@property (nonatomic, assign) NSTimeInterval mockDelay;
@property (nonatomic, copy) void (^completionHandler)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable);

- (instancetype)initWithResponse:(NSDictionary *)response error:(NSError *)error delay:(NSTimeInterval)delay;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;

@end

// Mock Data Task
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
    MockDataTask *task = [[MockDataTask alloc] init];
    task.completionHandler = completionHandler;
    task.mockResponse = self.mockResponse;
    task.mockError = self.mockError;
    task.mockDelay = self.mockDelay;
    task.url = url;
    return (NSURLSessionDataTask *)task;
}

@end

/// Comprehensive unit tests for HandleResolver class
/// Tests HTTPS resolution, error handling, validation, network failures, and edge cases
int runHandleResolverTests(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"🧪 Running HandleResolver Tests");
        NSUInteger totalTests = 0;
        NSUInteger passedTests = 0;

        // Test 1: HandleResolver Initialization
        totalTests++;
        HandleResolver *resolver = [[HandleResolver alloc] init];
        if (resolver && resolver.session &&
            resolver.session.configuration.timeoutIntervalForRequest == 10.0 &&
            resolver.session.configuration.timeoutIntervalForResource == 30.0) {
            passedTests++;
            NSLog(@"✅ HandleResolver Initialization: PASSED");
        } else {
            NSLog(@"❌ HandleResolver Initialization: FAILED");
        }

        // Test 2: Handle Validation - Empty String
        totalTests++;
        __block NSString *emptyResultDID = nil;
        __block NSError *emptyResultError = nil;
        __block BOOL emptyTestCompleted = NO;

        [resolver resolveHandle:@"" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            emptyResultDID = did;
            emptyResultError = error;
            emptyTestCompleted = YES;
        }];

        // Wait for completion
        NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
        while (!emptyTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 1.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (!emptyResultDID && emptyResultError && emptyResultError.code == HandleErrorInvalidFormat) {
            passedTests++;
            NSLog(@"✅ Handle Validation (Empty): PASSED");
        } else {
            NSLog(@"❌ Handle Validation (Empty): FAILED - DID: %@, Error: %@", emptyResultDID, emptyResultError);
        }

        // Test 3: Handle Validation - Null String
        totalTests++;
        __block NSString *nullResultDID = nil;
        __block NSError *nullResultError = nil;
        __block BOOL nullTestCompleted = NO;

        [resolver resolveHandle:nil completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            nullResultDID = did;
            nullResultError = error;
            nullTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!nullTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 1.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (!nullResultDID && nullResultError && nullResultError.code == HandleErrorInvalidFormat) {
            passedTests++;
            NSLog(@"✅ Handle Validation (Null): PASSED");
        } else {
            NSLog(@"❌ Handle Validation (Null): FAILED - DID: %@, Error: %@", nullResultDID, nullResultError);
        }

        // Test 4: Handle Validation - No Dot
        totalTests++;
        __block NSString *noDotResultDID = nil;
        __block NSError *noDotResultError = nil;
        __block BOOL noDotTestCompleted = NO;

        [resolver resolveHandle:@"invalidhandle" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            noDotResultDID = did;
            noDotResultError = error;
            noDotTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!noDotTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 1.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (!noDotResultDID && noDotResultError && noDotResultError.code == HandleErrorInvalidFormat) {
            passedTests++;
            NSLog(@"✅ Handle Validation (No Dot): PASSED");
        } else {
            NSLog(@"❌ Handle Validation (No Dot): FAILED - DID: %@, Error: %@", noDotResultDID, noDotResultError);
        }

        // Test 5: Handle Validation - Valid Format
        totalTests++;
        MockURLSession *mockSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:7HjwGtP5cLyq3vD5nDzDg"}
                                                                         error:nil
                                                                         delay:0.1];
        HandleResolver *mockResolver = [[HandleResolver alloc] init];
        [mockResolver setValue:mockSession forKey:@"session"];

        __block NSString *validResultDID = nil;
        __block NSError *validResultError = nil;
        __block BOOL validTestCompleted = NO;

        [mockResolver resolveHandle:@"test.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            validResultDID = did;
            validResultError = error;
            validTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!validTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 2.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (validResultDID && [validResultDID isEqualToString:@"did:plc:7HjwGtP5cLyq3vD5nDzDg"] && !validResultError) {
            passedTests++;
            NSLog(@"✅ Handle Validation (Valid): PASSED");
        } else {
            NSLog(@"❌ Handle Validation (Valid): FAILED - DID: %@, Error: %@", validResultDID, validResultError);
        }

        // Test 6: HTTPS Resolution - Network Error
        totalTests++;
        MockURLSession *errorSession = [[MockURLSession alloc] initWithResponse:nil
                                                                         error:[NSError errorWithDomain:NSURLErrorDomain
                                                                                                   code:NSURLErrorTimedOut
                                                                                               userInfo:nil]
                                                                         delay:0.1];
        HandleResolver *errorResolver = [[HandleResolver alloc] init];
        [errorResolver setValue:errorSession forKey:@"session"];

        __block NSString *errorResultDID = nil;
        __block NSError *errorResultError = nil;
        __block BOOL errorTestCompleted = NO;

        [errorResolver resolveHandle:@"error.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            errorResultDID = did;
            errorResultError = error;
            errorTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!errorTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 2.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (!errorResultDID && errorResultError && errorResultError.code == HandleErrorNetworkError) {
            passedTests++;
            NSLog(@"✅ HTTPS Resolution (Network Error): PASSED");
        } else {
            NSLog(@"❌ HTTPS Resolution (Network Error): FAILED - DID: %@, Error: %@", errorResultDID, errorResultError);
        }

        // Test 7: HTTPS Resolution - HTTP 404 Error
        totalTests++;
        MockURLSession *notFoundSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @404, @"body": @"Not Found"}
                                                                            error:nil
                                                                            delay:0.1];
        HandleResolver *notFoundResolver = [[HandleResolver alloc] init];
        [notFoundResolver setValue:notFoundSession forKey:@"session"];

        __block NSString *notFoundResultDID = nil;
        __block NSError *notFoundResultError = nil;
        __block BOOL notFoundTestCompleted = NO;

        [notFoundResolver resolveHandle:@"notfound.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            notFoundResultDID = did;
            notFoundResultError = error;
            notFoundTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!notFoundTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 2.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (!notFoundResultDID && notFoundResultError && notFoundResultError.code == HandleErrorNotFound) {
            passedTests++;
            NSLog(@"✅ HTTPS Resolution (HTTP 404): PASSED");
        } else {
            NSLog(@"❌ HTTPS Resolution (HTTP 404): FAILED - DID: %@, Error: %@", notFoundResultDID, notFoundResultError);
        }

        // Test 8: HTTPS Resolution - HTTP 500 Error
        totalTests++;
        MockURLSession *serverErrorSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @500, @"body": @"Internal Server Error"}
                                                                               error:nil
                                                                               delay:0.1];
        HandleResolver *serverErrorResolver = [[HandleResolver alloc] init];
        [serverErrorResolver setValue:serverErrorSession forKey:@"session"];

        __block NSString *serverErrorResultDID = nil;
        __block NSError *serverErrorResultError = nil;
        __block BOOL serverErrorTestCompleted = NO;

        [serverErrorResolver resolveHandle:@"servererror.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            serverErrorResultDID = did;
            serverErrorResultError = error;
            serverErrorTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!serverErrorTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 2.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (!serverErrorResultDID && serverErrorResultError && serverErrorResultError.code == HandleErrorNotFound) {
            passedTests++;
            NSLog(@"✅ HTTPS Resolution (HTTP 500): PASSED");
        } else {
            NSLog(@"❌ HTTPS Resolution (HTTP 500): FAILED - DID: %@, Error: %@", serverErrorResultDID, serverErrorResultError);
        }

        // Test 9: HTTPS Resolution - Empty Response Body
        totalTests++;
        MockURLSession *emptyBodySession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @""}
                                                                             error:nil
                                                                             delay:0.1];
        HandleResolver *emptyBodyResolver = [[HandleResolver alloc] init];
        [emptyBodyResolver setValue:emptyBodySession forKey:@"session"];

        __block NSString *emptyBodyResultDID = nil;
        __block NSError *emptyBodyResultError = nil;
        __block BOOL emptyBodyTestCompleted = NO;

        [emptyBodyResolver resolveHandle:@"empty.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            emptyBodyResultDID = did;
            emptyBodyResultError = error;
            emptyBodyTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!emptyBodyTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 2.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (!emptyBodyResultDID && emptyBodyResultError && emptyBodyResultError.code == HandleErrorResolutionFailed) {
            passedTests++;
            NSLog(@"✅ HTTPS Resolution (Empty Body): PASSED");
        } else {
            NSLog(@"❌ HTTPS Resolution (Empty Body): FAILED - DID: %@, Error: %@", emptyBodyResultDID, emptyBodyResultError);
        }

        // Test 10: HTTPS Resolution - Whitespace Only Response
        totalTests++;
        MockURLSession *whitespaceSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"   \n\t  "}
                                                                              error:nil
                                                                              delay:0.1];
        HandleResolver *whitespaceResolver = [[HandleResolver alloc] init];
        [whitespaceResolver setValue:whitespaceSession forKey:@"session"];

        __block NSString *whitespaceResultDID = nil;
        __block NSError *whitespaceResultError = nil;
        __block BOOL whitespaceTestCompleted = NO;

        [whitespaceResolver resolveHandle:@"whitespace.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            whitespaceResultDID = did;
            whitespaceResultError = error;
            whitespaceTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!whitespaceTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 2.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (!whitespaceResultDID && whitespaceResultError && whitespaceResultError.code == HandleErrorResolutionFailed) {
            passedTests++;
            NSLog(@"✅ HTTPS Resolution (Whitespace Only): PASSED");
        } else {
            NSLog(@"❌ HTTPS Resolution (Whitespace Only): FAILED - DID: %@, Error: %@", whitespaceResultDID, whitespaceResultError);
        }

        // Test 11: HTTPS Resolution - Invalid DID Format (No did: prefix)
        totalTests++;
        MockURLSession *invalidDIDSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"invalid-did-format"}
                                                                              error:nil
                                                                              delay:0.1];
        HandleResolver *invalidDIDResolver = [[HandleResolver alloc] init];
        [invalidDIDResolver setValue:invalidDIDSession forKey:@"session"];

        __block NSString *invalidDIDResultDID = nil;
        __block NSError *invalidDIDResultError = nil;
        __block BOOL invalidDIDTestCompleted = NO;

        [invalidDIDResolver resolveHandle:@"invaliddid.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            invalidDIDResultDID = did;
            invalidDIDResultError = error;
            invalidDIDTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!invalidDIDTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 2.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (!invalidDIDResultDID && invalidDIDResultError && invalidDIDResultError.code == HandleErrorResolutionFailed) {
            passedTests++;
            NSLog(@"✅ HTTPS Resolution (Invalid DID): PASSED");
        } else {
            NSLog(@"❌ HTTPS Resolution (Invalid DID): FAILED - DID: %@, Error: %@", invalidDIDResultDID, invalidDIDResultError);
        }

        // Test 12: HTTPS Resolution - Valid DID with Extra Whitespace
        totalTests++;
        MockURLSession *whitespaceDIDSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"  did:plc:7HjwGtP5cLyq3vD5nDzDg  \n"}
                                                                                  error:nil
                                                                                  delay:0.1];
        HandleResolver *whitespaceDIDResolver = [[HandleResolver alloc] init];
        [whitespaceDIDResolver setValue:whitespaceDIDSession forKey:@"session"];

        __block NSString *whitespaceDIDResultDID = nil;
        __block NSError *whitespaceDIDResultError = nil;
        __block BOOL whitespaceDIDTestCompleted = NO;

        [whitespaceDIDResolver resolveHandle:@"whitespace.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            whitespaceDIDResultDID = did;
            whitespaceDIDResultError = error;
            whitespaceDIDTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!whitespaceDIDTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 2.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (whitespaceDIDResultDID && [whitespaceDIDResultDID isEqualToString:@"did:plc:7HjwGtP5cLyq3vD5nDzDg"] && !whitespaceDIDResultError) {
            passedTests++;
            NSLog(@"✅ HTTPS Resolution (DID with Whitespace): PASSED");
        } else {
            NSLog(@"❌ HTTPS Resolution (DID with Whitespace): FAILED - DID: %@, Error: %@", whitespaceDIDResultDID, whitespaceDIDResultError);
        }

        // Test 13: URL Construction - Invalid URL Characters
        totalTests++;
        HandleResolver *urlTestResolver = [[HandleResolver alloc] init];
        __block NSString *urlTestResultDID = nil;
        __block NSError *urlTestResultError = nil;
        __block BOOL urlTestCompleted = NO;

        // This should fail at URL construction
        [urlTestResolver resolveHandle:@"invalid url.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            urlTestResultDID = did;
            urlTestResultError = error;
            urlTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!urlTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 1.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (!urlTestResultDID && urlTestResultError && urlTestResultError.code == HandleErrorInvalidFormat) {
            passedTests++;
            NSLog(@"✅ URL Construction (Invalid Characters): PASSED");
        } else {
            NSLog(@"❌ URL Construction (Invalid Characters): FAILED - DID: %@, Error: %@", urlTestResultDID, urlTestResultError);
        }

        // Test 14: Session Timeout Configuration
        totalTests++;
        HandleResolver *timeoutResolver = [[HandleResolver alloc] init];
        if (timeoutResolver.session.configuration.timeoutIntervalForRequest == 10.0 &&
            timeoutResolver.session.configuration.timeoutIntervalForResource == 30.0) {
            passedTests++;
            NSLog(@"✅ Session Timeout Configuration: PASSED");
        } else {
            NSLog(@"❌ Session Timeout Configuration: FAILED - Request: %.1f, Resource: %.1f",
                  timeoutResolver.session.configuration.timeoutIntervalForRequest,
                  timeoutResolver.session.configuration.timeoutIntervalForResource);
        }

        // Test 15: Concurrent Resolutions
        totalTests++;
        MockURLSession *concurrentSession1 = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:concurrent1"}
                                                                               error:nil
                                                                               delay:0.1];
        MockURLSession *concurrentSession2 = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:concurrent2"}
                                                                               error:nil
                                                                               delay:0.1];

        HandleResolver *concurrentResolver1 = [[HandleResolver alloc] init];
        HandleResolver *concurrentResolver2 = [[HandleResolver alloc] init];
        [concurrentResolver1 setValue:concurrentSession1 forKey:@"session"];
        [concurrentResolver2 setValue:concurrentSession2 forKey:@"session"];

        __block NSString *concurrentResultDID1 = nil;
        __block NSError *concurrentResultError1 = nil;
        __block BOOL concurrentTestCompleted1 = NO;

        __block NSString *concurrentResultDID2 = nil;
        __block NSError *concurrentResultError2 = nil;
        __block BOOL concurrentTestCompleted2 = NO;

        [concurrentResolver1 resolveHandle:@"concurrent1.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            concurrentResultDID1 = did;
            concurrentResultError1 = error;
            concurrentTestCompleted1 = YES;
        }];

        [concurrentResolver2 resolveHandle:@"concurrent2.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            concurrentResultDID2 = did;
            concurrentResultError2 = error;
            concurrentTestCompleted2 = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while ((!concurrentTestCompleted1 || !concurrentTestCompleted2) && [[NSDate date] timeIntervalSince1970] - startTime < 2.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (concurrentResultDID1 && [concurrentResultDID1 isEqualToString:@"did:plc:concurrent1"] && !concurrentResultError1 &&
            concurrentResultDID2 && [concurrentResultDID2 isEqualToString:@"did:plc:concurrent2"] && !concurrentResultError2) {
            passedTests++;
            NSLog(@"✅ Concurrent Resolutions: PASSED");
        } else {
            NSLog(@"❌ Concurrent Resolutions: FAILED - DID1: %@ (Error: %@), DID2: %@ (Error: %@)",
                  concurrentResultDID1, concurrentResultError1, concurrentResultDID2, concurrentResultError2);
        }

        // Test 16: Large Handle Handling
        totalTests++;
        NSString *largeHandle = [@"" stringByPaddingToLength:1000 withString:@"a" startingAtIndex:0];
        largeHandle = [largeHandle stringByAppendingString:@".example.com"];

        MockURLSession *largeHandleSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:large"}
                                                                               error:nil
                                                                               delay:0.1];
        HandleResolver *largeHandleResolver = [[HandleResolver alloc] init];
        [largeHandleResolver setValue:largeHandleSession forKey:@"session"];

        __block NSString *largeHandleResultDID = nil;
        __block NSError *largeHandleResultError = nil;
        __block BOOL largeHandleTestCompleted = NO;

        [largeHandleResolver resolveHandle:largeHandle completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            largeHandleResultDID = did;
            largeHandleResultError = error;
            largeHandleTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!largeHandleTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 2.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (largeHandleResultDID && [largeHandleResultDID isEqualToString:@"did:plc:large"] && !largeHandleResultError) {
            passedTests++;
            NSLog(@"✅ Large Handle Handling: PASSED");
        } else {
            NSLog(@"❌ Large Handle Handling: FAILED - DID: %@, Error: %@", largeHandleResultDID, largeHandleResultError);
        }

        // Test 17: Special Characters in Handle
        totalTests++;
        MockURLSession *specialCharSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:special"}
                                                                               error:nil
                                                                               delay:0.1];
        HandleResolver *specialCharResolver = [[HandleResolver alloc] init];
        [specialCharResolver setValue:specialCharSession forKey:@"session"];

        __block NSString *specialCharResultDID = nil;
        __block NSError *specialCharResultError = nil;
        __block BOOL specialCharTestCompleted = NO;

        [specialCharResolver resolveHandle:@"test-handle.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            specialCharResultDID = did;
            specialCharResultError = error;
            specialCharTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!specialCharTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 2.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (specialCharResultDID && [specialCharResultDID isEqualToString:@"did:plc:special"] && !specialCharResultError) {
            passedTests++;
            NSLog(@"✅ Special Characters in Handle: PASSED");
        } else {
            NSLog(@"❌ Special Characters in Handle: FAILED - DID: %@, Error: %@", specialCharResultDID, specialCharResultError);
        }

        // Test 18: Memory Management
        totalTests++;
        @autoreleasepool {
            HandleResolver *tempResolver = [[HandleResolver alloc] init];
            MockURLSession *tempSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:temp"}
                                                                            error:nil
                                                                            delay:0.1];
            [tempResolver setValue:tempSession forKey:@"session"];

            __block NSString *tempResultDID = nil;
            __block NSError *tempResultError = nil;
            __block BOOL tempTestCompleted = NO;

            [tempResolver resolveHandle:@"temp.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
                tempResultDID = did;
                tempResultError = error;
                tempTestCompleted = YES;
            }];

            startTime = [[NSDate date] timeIntervalSince1970];
            while (!tempTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 2.0) {
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            }

            if (tempResultDID && [tempResultDID isEqualToString:@"did:plc:temp"] && !tempResultError) {
                passedTests++;
                NSLog(@"✅ Memory Management: PASSED");
            } else {
                NSLog(@"❌ Memory Management: FAILED - DID: %@, Error: %@", tempResultDID, tempResultError);
            }
        }

        // Test 19: Error Domain Consistency
        totalTests++;
        NSError *domainError = [NSError errorWithDomain:HandleErrorDomain code:HandleErrorInvalidFormat userInfo:nil];
        if ([domainError.domain isEqualToString:HandleErrorDomain]) {
            passedTests++;
            NSLog(@"✅ Error Domain Consistency: PASSED");
        } else {
            NSLog(@"❌ Error Domain Consistency: FAILED - Domain: %@", domainError.domain);
        }

        // Test 20: Multiple Dots in Handle
        totalTests++;
        MockURLSession *multiDotSession = [[MockURLSession alloc] initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:multidot"}
                                                                            error:nil
                                                                            delay:0.1];
        HandleResolver *multiDotResolver = [[HandleResolver alloc] init];
        [multiDotResolver setValue:multiDotSession forKey:@"session"];

        __block NSString *multiDotResultDID = nil;
        __block NSError *multiDotResultError = nil;
        __block BOOL multiDotTestCompleted = NO;

        [multiDotResolver resolveHandle:@"sub.test.example.com" completion:^(NSString * _Nullable did, NSError * _Nullable error) {
            multiDotResultDID = did;
            multiDotResultError = error;
            multiDotTestCompleted = YES;
        }];

        startTime = [[NSDate date] timeIntervalSince1970];
        while (!multiDotTestCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 2.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (multiDotResultDID && [multiDotResultDID isEqualToString:@"did:plc:multidot"] && !multiDotResultError) {
            passedTests++;
            NSLog(@"✅ Multiple Dots in Handle: PASSED");
        } else {
            NSLog(@"❌ Multiple Dots in Handle: FAILED - DID: %@, Error: %@", multiDotResultDID, multiDotResultError);
        }

        // Summary
        NSLog(@"🎯 HandleResolver Test Results: %lu/%lu tests passed", (unsigned long)passedTests, (unsigned long)totalTests);

        if (passedTests == totalTests) {
            NSLog(@"🎉 All HandleResolver tests PASSED! The resolver is working correctly.");
        } else {
            NSLog(@"⚠️  Some HandleResolver tests FAILED. Please review the implementation.");
        }

        // Return the number of tests that passed (not just 0/1)
        return (int)passedTests;
    }
}

int main(int argc, const char * argv[]) {
    return runHandleResolverTests(argc, argv);
}