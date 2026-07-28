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
#import "Network/ATProtoSafeHTTPClient.h"

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
                        dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
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

@end
