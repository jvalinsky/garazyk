/*!
 @file PDSTelegramGatewayPhoneVerificationProviderTests.m

 @abstract Tests for the Telegram Gateway phone verification provider.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "PhoneVerification/PDSTelegramGatewayPhoneVerificationProvider.h"
#import "Services/Core/PDSPhoneVerificationProvider.h"
#import "Email/PDSSecretsProvider.h"

#pragma mark - Mock Secrets Provider

@interface PDSMockTelegramGatewaySecretsProvider : NSObject <PDSSecretsProvider>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *secrets;
@end

@implementation PDSMockTelegramGatewaySecretsProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        _secrets = [NSMutableDictionary dictionary];
    }
    return self;
}

- (nullable NSString *)secretForKey:(NSString *)key error:(NSError **)error {
    NSString *value = _secrets[key];
    if (!value && error) {
        *error = [NSError errorWithDomain:@"PDSMockTelegramGatewaySecretsProviderErrorDomain"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"Secret not found: %@", key]}];
    }
    return value;
}

@end

#pragma mark - Tests

@interface PDSTelegramGatewayPhoneVerificationProviderTests : XCTestCase
@end

@implementation PDSTelegramGatewayPhoneVerificationProviderTests

- (void)testInitWithMissingToken {
    PDSMockTelegramGatewaySecretsProvider *secrets = [[PDSMockTelegramGatewaySecretsProvider alloc] init];

    PDSTelegramGatewayPhoneVerificationProvider *provider =
        [[PDSTelegramGatewayPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                                     configuration:@{}];

    NSError *error = nil;
    NSString *sessionID = [provider requestVerificationForPhoneNumber:@"+1234567890" error:&error];
    XCTAssertNil(sessionID);
    XCTAssertEqual(error.code, PDSTelegramGatewayProviderErrorMissingToken);
}

- (void)testRequestVerificationWithEmptyPhoneNumber {
    PDSMockTelegramGatewaySecretsProvider *secrets = [[PDSMockTelegramGatewaySecretsProvider alloc] init];
    secrets.secrets[@"TELEGRAM_GATEWAY_TOKEN"] = @"test-token";

    PDSTelegramGatewayPhoneVerificationProvider *provider =
        [[PDSTelegramGatewayPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                                     configuration:@{}];

    NSError *error = nil;
    NSString *sessionID = [provider requestVerificationForPhoneNumber:@"" error:&error];
    XCTAssertNil(sessionID);
    XCTAssertEqual(error.code, PDSTelegramGatewayProviderErrorInvalidPhoneNumber);
}

- (void)testRequestVerificationWithNilPhoneNumber {
    PDSMockTelegramGatewaySecretsProvider *secrets = [[PDSMockTelegramGatewaySecretsProvider alloc] init];
    secrets.secrets[@"TELEGRAM_GATEWAY_TOKEN"] = @"test-token";

    PDSTelegramGatewayPhoneVerificationProvider *provider =
        [[PDSTelegramGatewayPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                                     configuration:@{}];

    NSError *error = nil;
    NSString *sessionID = [provider requestVerificationForPhoneNumber:nil error:&error];
    XCTAssertNil(sessionID);
    XCTAssertEqual(error.code, PDSTelegramGatewayProviderErrorInvalidPhoneNumber);
}

- (void)testVerifyCodeWithEmptyCode {
    PDSMockTelegramGatewaySecretsProvider *secrets = [[PDSMockTelegramGatewaySecretsProvider alloc] init];
    secrets.secrets[@"TELEGRAM_GATEWAY_TOKEN"] = @"test-token";

    PDSTelegramGatewayPhoneVerificationProvider *provider =
        [[PDSTelegramGatewayPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                                     configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"" forPhoneNumber:@"+1234567890" sessionID:@"req-123" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSTelegramGatewayProviderErrorVerificationFailed);
}

- (void)testVerifyCodeWithEmptyPhoneNumber {
    PDSMockTelegramGatewaySecretsProvider *secrets = [[PDSMockTelegramGatewaySecretsProvider alloc] init];
    secrets.secrets[@"TELEGRAM_GATEWAY_TOKEN"] = @"test-token";

    PDSTelegramGatewayPhoneVerificationProvider *provider =
        [[PDSTelegramGatewayPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                                     configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"123456" forPhoneNumber:@"" sessionID:@"req-123" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSTelegramGatewayProviderErrorInvalidPhoneNumber);
}

- (void)testVerifyCodeWithNilSessionID {
    PDSMockTelegramGatewaySecretsProvider *secrets = [[PDSMockTelegramGatewaySecretsProvider alloc] init];
    secrets.secrets[@"TELEGRAM_GATEWAY_TOKEN"] = @"test-token";

    PDSTelegramGatewayPhoneVerificationProvider *provider =
        [[PDSTelegramGatewayPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                                     configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"123456" forPhoneNumber:@"+1234567890" sessionID:nil error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSTelegramGatewayProviderErrorVerificationFailed);
}

- (void)testVerifyCodeWithEmptySessionID {
    PDSMockTelegramGatewaySecretsProvider *secrets = [[PDSMockTelegramGatewaySecretsProvider alloc] init];
    secrets.secrets[@"TELEGRAM_GATEWAY_TOKEN"] = @"test-token";

    PDSTelegramGatewayPhoneVerificationProvider *provider =
        [[PDSTelegramGatewayPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                                     configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"123456" forPhoneNumber:@"+1234567890" sessionID:@"" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSTelegramGatewayProviderErrorVerificationFailed);
}

- (void)testProviderConformsToPhoneVerificationProtocol {
    PDSMockTelegramGatewaySecretsProvider *secrets = [[PDSMockTelegramGatewaySecretsProvider alloc] init];
    PDSTelegramGatewayPhoneVerificationProvider *provider =
        [[PDSTelegramGatewayPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                                     configuration:@{}];

    XCTAssertTrue([provider conformsToProtocol:@protocol(PDSPhoneVerificationProvider)]);
}

- (void)testProviderSupportsVerifyCodeWithSessionIDMethod {
    PDSMockTelegramGatewaySecretsProvider *secrets = [[PDSMockTelegramGatewaySecretsProvider alloc] init];
    PDSTelegramGatewayPhoneVerificationProvider *provider =
        [[PDSTelegramGatewayPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                                     configuration:@{}];

    XCTAssertTrue([provider respondsToSelector:@selector(verifyCode:forPhoneNumber:sessionID:error:)]);
}

- (void)testFactoryResolvesTelegramProvider {
    PDSMockTelegramGatewaySecretsProvider *secrets = [[PDSMockTelegramGatewaySecretsProvider alloc] init];
    secrets.secrets[@"TELEGRAM_GATEWAY_TOKEN"] = @"test-token";

    NSError *error = nil;
    id<PDSPhoneVerificationProvider> provider = [PDSPhoneVerificationProviderFactory
        providerWithName:@"telegram"
        configuration:@{}
        secretsProvider:secrets
        error:&error];

    XCTAssertNotNil(provider);
    XCTAssertNil(error);
    XCTAssertTrue([provider isKindOfClass:[PDSTelegramGatewayPhoneVerificationProvider class]]);
}

@end
