// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Email/PDSResendEmailProvider.h"
#import "Email/PDSSecretsProvider.h"
#import "Email/PDSEmailHTTPClient.h"

// Expose private property for testing
@interface PDSResendEmailProvider (Testing)
@property (nonatomic, strong) PDSEmailHTTPClient *httpClient;
@end

// Mock HTTP Client
@interface MockEmailHTTPClient : PDSEmailHTTPClient
@property (nonatomic, copy) NSDictionary *mockResponse;
@property (nonatomic, strong) NSError *mockError;
@property (nonatomic, copy) NSString *lastPath;
@property (nonatomic, copy) NSDictionary *lastBody;
@end

@implementation MockEmailHTTPClient

- (instancetype)init {
    // Call super init with dummy values to satisfy designated initializer
    return [super initWithBaseURL:[NSURL URLWithString:@"http://mock.com"] apiKey:@"mock-key"];
}

- (nullable NSDictionary *)postPath:(NSString *)path
                               body:(NSDictionary *)body
                              error:(NSError * _Nullable *)error {
    self.lastPath = path;
    self.lastBody = body;
    
    if (self.mockError) {
        if (error) {
            *error = self.mockError;
        }
        return nil;
    }
    
    return self.mockResponse;
}

@end

// Simple mock for PDSSecretsProvider
@interface MockSecretsProvider : NSObject <PDSSecretsProvider>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *secrets;
@end

@implementation MockSecretsProvider
- (instancetype)init {
    self = [super init];
    if (self) {
        _secrets = [NSMutableDictionary dictionary];
    }
    return self;
}
- (nullable NSString *)secretForKey:(NSString *)key error:(NSError **)error {
    return self.secrets[key];
}
@end

@interface PDSResendEmailProviderTests : XCTestCase
@property (nonatomic, strong) MockSecretsProvider *mockSecrets;
@property (nonatomic, strong) PDSResendEmailProvider *provider;
@end

@implementation PDSResendEmailProviderTests

- (void)setUp {
    [super setUp];
    self.mockSecrets = [[MockSecretsProvider alloc] init];
    // Default setup
    self.provider = [[PDSResendEmailProvider alloc] initWithSecretsProvider:self.mockSecrets
                                                                fromAddress:@"test@example.com"];
}

- (void)tearDown {
    self.provider = nil;
    self.mockSecrets = nil;
    [super tearDown];
}

- (void)testInitWithSecretsProvider {
    XCTAssertNotNil(self.provider);
    XCTAssertEqualObjects(self.provider.fromAddress, @"test@example.com");
    XCTAssertEqualObjects(self.provider.apiEndpoint, @"https://api.resend.com"); // Default
    XCTAssertEqualObjects(self.provider.secretsProvider, self.mockSecrets);
}

- (void)testInitWithCustomEndpoint {
    PDSResendEmailProvider *customProvider = [[PDSResendEmailProvider alloc] initWithSecretsProvider:self.mockSecrets
                                                                                         fromAddress:@"custom@example.com"
                                                                                         apiEndpoint:@"https://custom.api.endpoint"];
    
    XCTAssertNotNil(customProvider);
    XCTAssertEqualObjects(customProvider.fromAddress, @"custom@example.com");
    XCTAssertEqualObjects(customProvider.apiEndpoint, @"https://custom.api.endpoint");
}

- (void)testProperties {
    // Verify readonly properties are accessible
    XCTAssertTrue([self.provider respondsToSelector:@selector(fromAddress)]);
    XCTAssertTrue([self.provider respondsToSelector:@selector(apiEndpoint)]);
    XCTAssertTrue([self.provider respondsToSelector:@selector(secretsProvider)]);
}

- (void)testSendEmailWithMissingAPIKey {
    // Ensure mock secrets does not have the key
    [self.mockSecrets.secrets removeObjectForKey:@"RESEND_API_KEY"];
    
    NSError *error = nil;
    BOOL success = [self.provider sendEmailTo:@"recipient@example.com"
                                      subject:@"Test Subject"
                                         body:@"Test Body"
                                        error:&error];
    
    XCTAssertFalse(success, @"Should fail when API key is missing");
    XCTAssertNotNil(error, @"Error should be populated");
    XCTAssertEqualObjects(error.domain, @"PDSResendEmailProviderErrorDomain");
    XCTAssertEqual(error.code, 1); // We used code 1 for missing API key
}

- (void)testSendEmailSuccess {
    MockEmailHTTPClient *mockClient = [[MockEmailHTTPClient alloc] init];
    mockClient.mockResponse = @{@"id": @"email_123"};
    
    self.provider.httpClient = mockClient;
    
    NSError *error = nil;
    BOOL success = [self.provider sendEmailTo:@"recipient@example.com"
                                      subject:@"Test Subject"
                                         body:@"Test Body"
                                        error:&error];
    
    XCTAssertTrue(success);
    XCTAssertNil(error);
    XCTAssertEqualObjects(mockClient.lastPath, @"/emails");
    
    NSDictionary *expectedBody = @{
        @"from": @"test@example.com",
        @"to": @[@"recipient@example.com"],
        @"subject": @"Test Subject",
        @"text": @"Test Body"
    };
    XCTAssertEqualObjects(mockClient.lastBody, expectedBody);
}

- (void)testSendEmailFailure {
    MockEmailHTTPClient *mockClient = [[MockEmailHTTPClient alloc] init];
    mockClient.mockError = [NSError errorWithDomain:@"TestDomain" code:123 userInfo:nil];
    
    self.provider.httpClient = mockClient;
    
    NSError *error = nil;
    BOOL success = [self.provider sendEmailTo:@"recipient@example.com"
                                      subject:@"Test Subject"
                                         body:@"Test Body"
                                        error:&error];
    
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"TestDomain");
    XCTAssertEqual(error.code, 123);
}

- (void)testSendHtmlEmailSuccess {
    MockEmailHTTPClient *mockClient = [[MockEmailHTTPClient alloc] init];
    mockClient.mockResponse = @{@"id": @"email_456"};
    
    self.provider.httpClient = mockClient;
    
    NSError *error = nil;
    BOOL success = [self.provider sendHtmlEmailTo:@"recipient@example.com"
                                          subject:@"HTML Subject"
                                         htmlBody:@"<p>HTML Body</p>"
                                         textBody:@"Text Body"
                                            error:&error];
    
    XCTAssertTrue(success);
    XCTAssertNil(error);
    
    NSDictionary *expectedBody = @{
        @"from": @"test@example.com",
        @"to": @[@"recipient@example.com"],
        @"subject": @"HTML Subject",
        @"html": @"<p>HTML Body</p>",
        @"text": @"Text Body"
    };
    XCTAssertEqualObjects(mockClient.lastBody, expectedBody);
}

@end
