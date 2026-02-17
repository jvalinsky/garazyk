#import <XCTest/XCTest.h>
#import "Email/PDSResendEmailProvider.h"
#import "Email/PDSSecretsProvider.h"

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

@end
