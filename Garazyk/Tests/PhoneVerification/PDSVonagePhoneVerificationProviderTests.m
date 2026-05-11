// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSVonagePhoneVerificationProviderTests.m

 @abstract Tests for the Vonage Verify phone verification provider.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "PhoneVerification/PDSVonagePhoneVerificationProvider.h"
#import "Services/Core/PDSPhoneVerificationProvider.h"
#import "Email/PDSSecretsProvider.h"

#pragma mark - Mock Secrets Provider

@interface PDSMockVonageSecretsProvider : NSObject <PDSSecretsProvider>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *secrets;
@end

@implementation PDSMockVonageSecretsProvider

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
        *error = [NSError errorWithDomain:@"PDSMockVonageSecretsProviderErrorDomain"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"Secret not found: %@", key]}];
    }
    return value;
}

@end

#pragma mark - Tests

@interface PDSVonagePhoneVerificationProviderTests : XCTestCase
@end

@implementation PDSVonagePhoneVerificationProviderTests

- (void)testInitWithMissingAPIKey {
    PDSMockVonageSecretsProvider *secrets = [[PDSMockVonageSecretsProvider alloc] init];
    secrets.secrets[@"VONAGE_API_SECRET"] = @"test-secret";

    PDSVonagePhoneVerificationProvider *provider =
        [[PDSVonagePhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    NSString *sessionID = [provider requestVerificationForPhoneNumber:@"+1234567890" error:&error];
    XCTAssertNil(sessionID);
    XCTAssertEqual(error.code, PDSVonageProviderErrorMissingAPIKey);
}

- (void)testInitWithMissingAPISecret {
    PDSMockVonageSecretsProvider *secrets = [[PDSMockVonageSecretsProvider alloc] init];
    secrets.secrets[@"VONAGE_API_KEY"] = @"test-key";

    PDSVonagePhoneVerificationProvider *provider =
        [[PDSVonagePhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    NSString *sessionID = [provider requestVerificationForPhoneNumber:@"+1234567890" error:&error];
    XCTAssertNil(sessionID);
    XCTAssertEqual(error.code, PDSVonageProviderErrorMissingAPISecret);
}

- (void)testRequestVerificationWithEmptyPhoneNumber {
    PDSMockVonageSecretsProvider *secrets = [[PDSMockVonageSecretsProvider alloc] init];
    secrets.secrets[@"VONAGE_API_KEY"] = @"test-key";
    secrets.secrets[@"VONAGE_API_SECRET"] = @"test-secret";

    PDSVonagePhoneVerificationProvider *provider =
        [[PDSVonagePhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    NSString *sessionID = [provider requestVerificationForPhoneNumber:@"" error:&error];
    XCTAssertNil(sessionID);
    XCTAssertEqual(error.code, PDSVonageProviderErrorInvalidPhoneNumber);
}

- (void)testRequestVerificationWithNilPhoneNumber {
    PDSMockVonageSecretsProvider *secrets = [[PDSMockVonageSecretsProvider alloc] init];
    secrets.secrets[@"VONAGE_API_KEY"] = @"test-key";
    secrets.secrets[@"VONAGE_API_SECRET"] = @"test-secret";

    PDSVonagePhoneVerificationProvider *provider =
        [[PDSVonagePhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    NSString *sessionID = [provider requestVerificationForPhoneNumber:nil error:&error];
    XCTAssertNil(sessionID);
    XCTAssertEqual(error.code, PDSVonageProviderErrorInvalidPhoneNumber);
}

- (void)testVerifyCodeWithEmptyCode {
    PDSMockVonageSecretsProvider *secrets = [[PDSMockVonageSecretsProvider alloc] init];
    secrets.secrets[@"VONAGE_API_KEY"] = @"test-key";
    secrets.secrets[@"VONAGE_API_SECRET"] = @"test-secret";

    PDSVonagePhoneVerificationProvider *provider =
        [[PDSVonagePhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"" forPhoneNumber:@"+1234567890" sessionID:@"req-123" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSVonageProviderErrorVerificationFailed);
}

- (void)testVerifyCodeWithEmptyPhoneNumber {
    PDSMockVonageSecretsProvider *secrets = [[PDSMockVonageSecretsProvider alloc] init];
    secrets.secrets[@"VONAGE_API_KEY"] = @"test-key";
    secrets.secrets[@"VONAGE_API_SECRET"] = @"test-secret";

    PDSVonagePhoneVerificationProvider *provider =
        [[PDSVonagePhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"123456" forPhoneNumber:@"" sessionID:@"req-123" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSVonageProviderErrorInvalidPhoneNumber);
}

- (void)testVerifyCodeWithNilSessionID {
    PDSMockVonageSecretsProvider *secrets = [[PDSMockVonageSecretsProvider alloc] init];
    secrets.secrets[@"VONAGE_API_KEY"] = @"test-key";
    secrets.secrets[@"VONAGE_API_SECRET"] = @"test-secret";

    PDSVonagePhoneVerificationProvider *provider =
        [[PDSVonagePhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"123456" forPhoneNumber:@"+1234567890" sessionID:nil error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSVonageProviderErrorVerificationFailed);
}

- (void)testVerifyCodeWithEmptySessionID {
    PDSMockVonageSecretsProvider *secrets = [[PDSMockVonageSecretsProvider alloc] init];
    secrets.secrets[@"VONAGE_API_KEY"] = @"test-key";
    secrets.secrets[@"VONAGE_API_SECRET"] = @"test-secret";

    PDSVonagePhoneVerificationProvider *provider =
        [[PDSVonagePhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"123456" forPhoneNumber:@"+1234567890" sessionID:@"" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSVonageProviderErrorVerificationFailed);
}

- (void)testProviderConformsToPhoneVerificationProtocol {
    PDSMockVonageSecretsProvider *secrets = [[PDSMockVonageSecretsProvider alloc] init];
    PDSVonagePhoneVerificationProvider *provider =
        [[PDSVonagePhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    XCTAssertTrue([provider conformsToProtocol:@protocol(PDSPhoneVerificationProvider)]);
}

- (void)testProviderSupportsVerifyCodeWithSessionIDMethod {
    PDSMockVonageSecretsProvider *secrets = [[PDSMockVonageSecretsProvider alloc] init];
    PDSVonagePhoneVerificationProvider *provider =
        [[PDSVonagePhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    XCTAssertTrue([provider respondsToSelector:@selector(verifyCode:forPhoneNumber:sessionID:error:)]);
}

@end
