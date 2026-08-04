// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSCaptchaRegistrationGateTests.m

 @abstract Tests for the CAPTCHA registration gate's siteverify
           implementation, fail-closed behavior, and provider routing.

 @discussion
    Covers the phase-23 slice 1 acceptance gate:
    - No secret key configured → fail closed (returns NO, not YES)
    - Secret key + valid token → accepted (mock siteverify returns success:true)
    - Secret key + fabricated token → rejected (mock returns success:false)
    - siteverify network error → 503 (not 200)
    - siteverify timeout → 503 (not 200)
    - hCaptcha provider routes to the hCaptcha URL, not Turnstile

    The mock injection follows the PDSResendEmailProviderTests.m pattern:
    a Testing category exposes the safeHTTPClient property for override,
    and a mock ATProtoSafeHTTPClient subclass returns canned responses.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "Registration/PDSCaptchaRegistrationGate.h"
#import "Registration/PDSRegistrationGate.h"
#import "Registration/PDSInviteCodeRegistrationGate.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Database/Service/ServiceDatabases.h"

// Expose private property for testing
@interface PDSCaptchaRegistrationGate (Testing)
@property (nonatomic, strong) ATProtoSafeHTTPClient *safeHTTPClient;
@property (nonatomic, assign) NSTimeInterval siteverifyTimeout;
@end

#pragma mark - Mock ATProtoSafeHTTPClient

@interface MockSiteverifyResponse : NSObject
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, copy, nullable) NSData *bodyData;
@property (nonatomic, copy, nullable) NSString *bodyString;
@property (nonatomic, copy, nullable) NSDictionary *bodyJSON;
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic, assign) NSTimeInterval artificialDelay;
@end

@implementation MockSiteverifyResponse
@end

@interface MockCaptchaSiteverifyHTTPClient : ATProtoSafeHTTPClient
@property (nonatomic, strong) MockSiteverifyResponse *mockResponse;
@property (nonatomic, copy, nullable) NSURL *lastRequestURL;
@property (nonatomic, copy, nullable) NSString *lastRequestMethod;
@property (nonatomic, copy, nullable) NSString *lastRequestBodyString;
@end

@implementation MockCaptchaSiteverifyHTTPClient

- (void)performSafeDataTaskWithRequest:(NSURLRequest *)request
                                options:(nullable ATProtoSafeHTTPClientOptions *)options
                             completion:(void (^)(NSData * _Nullable,
                                                  NSHTTPURLResponse * _Nullable,
                                                  NSError * _Nullable))completion {
    self.lastRequestURL = request.URL;
    self.lastRequestMethod = request.HTTPMethod;

    // Capture the request body for verification
    NSData *bodyData = request.HTTPBody;
    if (bodyData) {
        self.lastRequestBodyString = [[NSString alloc] initWithData:bodyData
                                                           encoding:NSUTF8StringEncoding];
    }

    MockSiteverifyResponse *mock = self.mockResponse;
    if (!mock) {
        // Default: return a success response
        NSData *defaultData = [@"{\"success\":true}" dataUsingEncoding:NSUTF8StringEncoding];
        NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                              statusCode:200
                                                             HTTPVersion:@"1.1"
                                                            headerFields:nil];
        completion(defaultData, resp, nil);
        return;
    }

    if (mock.artificialDelay > 0) {
        // Simulate delay by not calling completion immediately.
        // The gate's semaphore wait will time out.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                      (int64_t)(mock.artificialDelay * NSEC_PER_SEC)),
                        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (mock.error) {
                completion(nil, nil, mock.error);
            } else {
                [self deliverMockResponse:mock forURL:request.URL completion:completion];
            }
        });
        return;
    }

    if (mock.error) {
        completion(nil, nil, mock.error);
        return;
    }

    [self deliverMockResponse:mock forURL:request.URL completion:completion];
}

- (void)deliverMockResponse:(MockSiteverifyResponse *)mock
                     forURL:(NSURL *)url
                 completion:(void (^)(NSData * _Nullable,
                                      NSHTTPURLResponse * _Nullable,
                                      NSError * _Nullable))completion {
    NSData *data = nil;
    if (mock.bodyData) {
        data = mock.bodyData;
    } else if (mock.bodyString) {
        data = [mock.bodyString dataUsingEncoding:NSUTF8StringEncoding];
    } else if (mock.bodyJSON) {
        data = [NSJSONSerialization dataWithJSONObject:mock.bodyJSON options:0 error:nil];
    } else {
        data = [@"{\"success\":true}" dataUsingEncoding:NSUTF8StringEncoding];
    }

    NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:url
                                                          statusCode:mock.statusCode ?: 200
                                                         HTTPVersion:@"1.1"
                                                        headerFields:nil];
    completion(data, resp, nil);
}

@end

#pragma mark - Tests

@interface PDSCaptchaRegistrationGateTests : XCTestCase
@property (nonatomic, strong) MockCaptchaSiteverifyHTTPClient *mockClient;
@end

@implementation PDSCaptchaRegistrationGateTests

- (void)setUp {
    [super setUp];
    self.mockClient = [[MockCaptchaSiteverifyHTTPClient alloc] init];
}

- (void)tearDown {
    self.mockClient = nil;
    [super tearDown];
}

#pragma mark - Gate Identifier

- (void)testCaptchaGateIdentifier {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:nil
                                                   secretKey:@"test-secret"];
    XCTAssertEqualObjects(gate.gateIdentifier, @"captcha");
}

#pragma mark - Missing/Empty Token

- (void)testCaptchaGateRejectsMissingToken {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorCaptchaRequired);
}

- (void)testCaptchaGateRejectsEmptyToken {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @""}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorCaptchaRequired);
}

#pragma mark - No Secret Key → Fail Closed

- (void)testCaptchaGateFailsClosedWhenNoSecretKeyConfigured {
    // The headline defect: previously this returned YES (accepting any token
    // presence). Now it must fail closed.
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:nil];
    gate.safeHTTPClient = self.mockClient;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"some-token"}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result, @"Gate must fail closed when no secret key is configured");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInvalidCaptcha);
    XCTAssertTrue([error.localizedDescription containsString:@"no secret key"],
                  @"Error message should mention the missing secret key");
}

- (void)testCaptchaGateFailsClosedWhenEmptySecretKeyConfigured {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@""];
    gate.safeHTTPClient = self.mockClient;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"some-token"}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result, @"Gate must fail closed when secret key is empty string");
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInvalidCaptcha);
}

#pragma mark - Siteverify Success

- (void)testCaptchaGateAcceptsValidTokenWithSiteverifySuccess {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;

    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.statusCode = 200;
    mock.bodyJSON = @{@"success": @YES};
    self.mockClient.mockResponse = mock;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"valid-token-xyz"}
                                      configuration:nil
                                              error:&error];
    XCTAssertTrue(result, @"Valid token with siteverify success:true should pass");
    XCTAssertNil(error);
}

#pragma mark - Siteverify success:false → Reject (400)

- (void)testCaptchaGateRejectsFabricatedTokenWithSiteverifyFailure {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;

    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.statusCode = 200;
    mock.bodyJSON = @{@"success": @NO, @"error-codes": @[@"invalid-input-response"]};
    self.mockClient.mockResponse = mock;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"fabricated-token"}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result, @"Token with siteverify success:false should be rejected");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInvalidCaptcha);
    XCTAssertEqualObjects([error.userInfo objectForKey:@"httpStatus"], @(400));
}

#pragma mark - Siteverify Network Error → 503

- (void)testCaptchaGateReturns503OnSiteverifyNetworkError {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;

    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.error = [NSError errorWithDomain:@"TestNetworkError"
                                     code:NSURLErrorNotConnectedToInternet
                                 userInfo:@{NSLocalizedDescriptionKey: @"No internet connection"}];
    self.mockClient.mockResponse = mock;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"some-token"}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result, @"Network error must not accept the token");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInvalidCaptcha);
    XCTAssertEqualObjects([error.userInfo objectForKey:@"httpStatus"], @(503),
                          @"Network error should map to 503, not 400");
}

- (void)testCaptchaGateReturns503OnSiteverifyNon200Status {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;

    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.statusCode = 500;
    mock.bodyString = @"Internal Server Error";
    self.mockClient.mockResponse = mock;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"some-token"}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInvalidCaptcha);
    XCTAssertEqualObjects([error.userInfo objectForKey:@"httpStatus"], @(503),
                          @"5xx from siteverify should map to 503");
}

- (void)testCaptchaGateReturns503OnUnparseableResponse {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;

    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.statusCode = 200;
    mock.bodyString = @"not json at all";
    self.mockClient.mockResponse = mock;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"some-token"}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInvalidCaptcha);
    XCTAssertEqualObjects([error.userInfo objectForKey:@"httpStatus"], @(503),
                          @"Unparseable response should map to 503");
}

#pragma mark - Siteverify Timeout → 503

- (void)testCaptchaGateReturns503OnSiteverifyTimeout {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;
    // Use a short timeout so the test doesn't block for 12 seconds.
    gate.siteverifyTimeout = 0.5;

    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    // Delay longer than the 0.5s timeout so the semaphore times out.
    mock.artificialDelay = 2.0;
    mock.statusCode = 200;
    mock.bodyJSON = @{@"success": @YES};
    self.mockClient.mockResponse = mock;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"some-token"}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result, @"Timeout must not accept the token");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInvalidCaptcha);
    XCTAssertEqualObjects([error.userInfo objectForKey:@"httpStatus"], @(503),
                          @"Timeout should map to 503, not 400 or 200");
}

#pragma mark - hCaptcha Provider Routing

- (void)testCaptchaGateHCaptchaRoutesToHCaptchaURL {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"hcaptcha"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;

    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.statusCode = 200;
    mock.bodyJSON = @{@"success": @YES};
    self.mockClient.mockResponse = mock;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"hcaptcha-token"}
                                      configuration:nil
                                              error:&error];
    XCTAssertTrue(result);
    XCTAssertNotNil(self.mockClient.lastRequestURL);
    XCTAssertEqualObjects(self.mockClient.lastRequestURL.absoluteString,
                          @"https://hcaptcha.com/siteverify",
                          @"hCaptcha provider must route to the hCaptcha siteverify URL");
}

- (void)testCaptchaGateTurnstileRoutesToTurnstileURL {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;

    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.statusCode = 200;
    mock.bodyJSON = @{@"success": @YES};
    self.mockClient.mockResponse = mock;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"turnstile-token"}
                                      configuration:nil
                                              error:&error];
    XCTAssertTrue(result);
    XCTAssertNotNil(self.mockClient.lastRequestURL);
    XCTAssertEqualObjects(self.mockClient.lastRequestURL.absoluteString,
                          @"https://challenges.cloudflare.com/turnstile/v0/siteverify",
                          @"Turnstile provider must route to the Turnstile siteverify URL");
}

- (void)testCaptchaGateDefaultProviderRoutesToTurnstileURL {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:nil
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;

    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.statusCode = 200;
    mock.bodyJSON = @{@"success": @YES};
    self.mockClient.mockResponse = mock;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"token"}
                                      configuration:nil
                                              error:&error];
    XCTAssertTrue(result);
    XCTAssertEqualObjects(self.mockClient.lastRequestURL.absoluteString,
                          @"https://challenges.cloudflare.com/turnstile/v0/siteverify",
                          @"Nil provider defaults to Turnstile");
}

#pragma mark - remoteAddress Parameter

- (void)testCaptchaGatePassesRemoteAddressInSiteverifyBody {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;

    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.statusCode = 200;
    mock.bodyJSON = @{@"success": @YES};
    self.mockClient.mockResponse = mock;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"token"}
                                      configuration:nil
                                      remoteAddress:@"203.0.113.42"
                                              error:&error];
    XCTAssertTrue(result);
    XCTAssertNotNil(self.mockClient.lastRequestBodyString);
    XCTAssertTrue([self.mockClient.lastRequestBodyString containsString:@"remoteip=203.0.113.42"],
                  @"remoteAddress must be included in the siteverify body as remoteip");
    XCTAssertTrue([self.mockClient.lastRequestBodyString containsString:@"secret=secret-key"],
                  @"secret key must be in the siteverify body");
    XCTAssertTrue([self.mockClient.lastRequestBodyString containsString:@"response=token"],
                  @"token must be in the siteverify body as response");
}

- (void)testCaptchaGateOmitsRemoteAddressWhenNil {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;

    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.statusCode = 200;
    mock.bodyJSON = @{@"success": @YES};
    self.mockClient.mockResponse = mock;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"token"}
                                      configuration:nil
                                      remoteAddress:nil
                                              error:&error];
    XCTAssertTrue(result);
    XCTAssertNotNil(self.mockClient.lastRequestBodyString);
    XCTAssertFalse([self.mockClient.lastRequestBodyString containsString:@"remoteip"],
                   @"remoteip field should be omitted when remoteAddress is nil");
}

#pragma mark - Form Encoding

- (void)testCaptchaGatePercentEncodesFormBodyValues {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret with spaces"];
    gate.safeHTTPClient = self.mockClient;

    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.statusCode = 200;
    mock.bodyJSON = @{@"success": @YES};
    self.mockClient.mockResponse = mock;

    NSError *error = nil;
    [gate validateRegistrationRequest:@{@"captchaToken": @"tok+en/with=special"}
                       configuration:nil
                               error:&error];

    XCTAssertNotNil(self.mockClient.lastRequestBodyString);
    XCTAssertTrue([self.mockClient.lastRequestBodyString containsString:@"secret=secret%20with%20spaces"],
                  @"Secret key with spaces must be percent-encoded");
    XCTAssertTrue([self.mockClient.lastRequestBodyString containsString:@"response=tok%2Ben%2Fwith%3Dspecial"],
                  @"Token with special chars must be percent-encoded");
}

#pragma mark - percentEncode nil guard (phase-25 slice 1 follow-up)

- (void)testCaptchaGateRejectsTokenWithUnpairedSurrogateInsteadOfEmittingNull {
    // stringByAddingPercentEncodingWithAllowedCharacters: returns nil for
    // strings containing unpaired surrogates. A lone high surrogate (no
    // matching low surrogate) is invalid UTF-16 and triggers that path.
    unichar loneSurrogate = 0xD800;
    NSString *tokenWithLoneSurrogate = [NSString stringWithCharacters:&loneSurrogate length:1];

    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": tokenWithLoneSurrogate}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result, @"A token that cannot be percent-encoded must be rejected");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInvalidCaptcha);
    XCTAssertNil(self.mockClient.lastRequestBodyString,
                 @"No HTTP request should be sent when the body cannot be encoded");
}

#pragma mark - Timeout budget (phase-25 slice 1 follow-up)

- (void)testCaptchaGateDefaultTimeoutIsTightened {
    // Phase-25 slice 1 follow-up: reduced from 12s to ~5s.
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    XCTAssertEqualWithAccuracy(gate.siteverifyTimeout, 5.0, 0.001);
}

- (void)testCaptchaGateLateCompletionAfterTimeoutDoesNotCrashOrHang {
    // A completion that fires after the gate has already given up (simulated
    // here by a delay well past siteverifyTimeout) must be a safe no-op:
    // the gate already returned, and the late completion must not touch
    // state or resignal a semaphore that nothing is waiting on.
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:@"site-key"
                                                   secretKey:@"secret-key"];
    gate.safeHTTPClient = self.mockClient;
    gate.siteverifyTimeout = 0.2;

    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.artificialDelay = 1.0;
    mock.statusCode = 200;
    mock.bodyJSON = @{@"success": @YES};
    self.mockClient.mockResponse = mock;

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"some-token"}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result, @"Timeout must not accept the token");
    XCTAssertEqualObjects([error.userInfo objectForKey:@"httpStatus"], @(503));

    // Give the delayed mock completion time to fire after the gate has
    // already returned, proving the late callback doesn't crash the test run.
    XCTestExpectation *settle = [self expectationWithDescription:@"late completion settles"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{
        [settle fulfill];
    });
    [self waitForExpectationsWithTimeout:3.0 handler:nil];
}

#pragma mark - Composite AND acceptance matrix (phase-25 slice 6)

- (nullable PDSServiceDatabases *)createTestServiceDatabases {
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *serviceDir = [tmpDir stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"captcha_gate_test_%@", NSUUID.UUID.UUIDString]];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:serviceDir withIntermediateDirectories:YES attributes:nil error:nil];

    PDSServiceDatabases *db = [[PDSServiceDatabases alloc] initWithDirectory:serviceDir
                                                             serviceMaxSize:10
                                                           didCacheMaxSize:10
                                                         sequencerMaxSize:10];
    if (!db) return nil;

    [self addTeardownBlock:^{
        [db closeAll];
        [fm removeItemAtPath:serviceDir error:nil];
    }];

    return db;
}

- (PDSCompositeRegistrationGate *)compositeWithInviteDatabase:(PDSServiceDatabases *)db
                                                    captchaGate:(PDSCaptchaRegistrationGate *)captchaGate {
    PDSCompositeRegistrationGate *composite = [[PDSCompositeRegistrationGate alloc] init];
    [composite addGate:[[PDSInviteCodeRegistrationGate alloc] initWithServiceDatabases:db]];
    [composite addGate:captchaGate];
    return composite;
}

- (void)testAcceptanceMatrixInvitePassCaptchaPassAdmits {
    PDSServiceDatabases *db = [self createTestServiceDatabases];
    if (!db) return;
    NSString *code = @"MATRIX-PASS-PASS-1";
    [db createInviteCode:code forAccount:@"did:plc:system" maxUses:1 error:nil];

    PDSCaptchaRegistrationGate *captchaGate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile" siteKey:@"k" secretKey:@"s"];
    captchaGate.safeHTTPClient = self.mockClient;
    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.statusCode = 200;
    mock.bodyJSON = @{@"success": @YES};
    self.mockClient.mockResponse = mock;

    PDSCompositeRegistrationGate *composite = [self compositeWithInviteDatabase:db captchaGate:captchaGate];

    NSError *error = nil;
    BOOL result = [composite validateRegistrationRequest:@{@"inviteCode": code, @"captchaToken": @"tok"}
                                          configuration:nil
                                                  error:&error];
    XCTAssertTrue(result, @"invite pass + captcha pass must admit");
}

- (void)testAcceptanceMatrixInvitePassCaptchaFailRejects {
    // This is the headline bug being fixed: previously OR semantics let a
    // valid invite code bypass CAPTCHA entirely.
    PDSServiceDatabases *db = [self createTestServiceDatabases];
    if (!db) return;
    NSString *code = @"MATRIX-PASS-FAIL-1";
    [db createInviteCode:code forAccount:@"did:plc:system" maxUses:1 error:nil];

    PDSCaptchaRegistrationGate *captchaGate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile" siteKey:@"k" secretKey:@"s"];
    captchaGate.safeHTTPClient = self.mockClient;
    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.statusCode = 200;
    mock.bodyJSON = @{@"success": @NO, @"error-codes": @[@"invalid-input-response"]};
    self.mockClient.mockResponse = mock;

    PDSCompositeRegistrationGate *composite = [self compositeWithInviteDatabase:db captchaGate:captchaGate];

    NSError *error = nil;
    BOOL result = [composite validateRegistrationRequest:@{@"inviteCode": code, @"captchaToken": @"tok"}
                                          configuration:nil
                                                  error:&error];
    XCTAssertFalse(result, @"invite pass + captcha fail must reject under AND semantics");
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInvalidCaptcha);
}

- (void)testAcceptanceMatrixInviteFailCaptchaPassRejects {
    PDSServiceDatabases *db = [self createTestServiceDatabases];
    if (!db) return;

    PDSCaptchaRegistrationGate *captchaGate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile" siteKey:@"k" secretKey:@"s"];
    captchaGate.safeHTTPClient = self.mockClient;
    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.statusCode = 200;
    mock.bodyJSON = @{@"success": @YES};
    self.mockClient.mockResponse = mock;

    PDSCompositeRegistrationGate *composite = [self compositeWithInviteDatabase:db captchaGate:captchaGate];

    NSError *error = nil;
    BOOL result = [composite validateRegistrationRequest:@{@"captchaToken": @"tok"}
                                          configuration:nil
                                                  error:&error];
    XCTAssertFalse(result, @"invite fail + captcha pass must reject");
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInviteCodeRequired);
}

- (void)testAcceptanceMatrixInviteFailCaptchaFailReportsFirstGatesError {
    PDSServiceDatabases *db = [self createTestServiceDatabases];
    if (!db) return;

    PDSCaptchaRegistrationGate *captchaGate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile" siteKey:@"k" secretKey:@"s"];
    captchaGate.safeHTTPClient = self.mockClient;

    PDSCompositeRegistrationGate *composite = [self compositeWithInviteDatabase:db captchaGate:captchaGate];

    NSError *error = nil;
    BOOL result = [composite validateRegistrationRequest:@{}
                                          configuration:nil
                                                  error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInviteCodeRequired,
                  @"invite fail + captcha fail must report the FIRST (invite) gate's error");
    XCTAssertNil(self.mockClient.lastRequestBodyString,
                 @"Short-circuit: the invite gate rejects first, so siteverify must never be called");
}

- (void)testAcceptanceMatrix503FromCaptchaSurfacesEvenWithInvitePassing {
    // Proves the 503 path is no longer absorbed: with invite passing, the
    // composite must still invoke CAPTCHA and surface its 503.
    PDSServiceDatabases *db = [self createTestServiceDatabases];
    if (!db) return;
    NSString *code = @"MATRIX-503-1";
    [db createInviteCode:code forAccount:@"did:plc:system" maxUses:1 error:nil];

    PDSCaptchaRegistrationGate *captchaGate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile" siteKey:@"k" secretKey:@"s"];
    captchaGate.safeHTTPClient = self.mockClient;
    MockSiteverifyResponse *mock = [[MockSiteverifyResponse alloc] init];
    mock.error = [NSError errorWithDomain:@"TestNetworkError"
                                     code:NSURLErrorNotConnectedToInternet
                                 userInfo:@{NSLocalizedDescriptionKey: @"No internet connection"}];
    self.mockClient.mockResponse = mock;

    PDSCompositeRegistrationGate *composite = [self compositeWithInviteDatabase:db captchaGate:captchaGate];

    NSError *error = nil;
    BOOL result = [composite validateRegistrationRequest:@{@"inviteCode": code, @"captchaToken": @"tok"}
                                          configuration:nil
                                                  error:&error];
    XCTAssertFalse(result);
    XCTAssertEqualObjects([error.userInfo objectForKey:@"httpStatus"], @(503),
                          @"CAPTCHA 503 must surface even though invite (an earlier gate) passed");
}

@end
