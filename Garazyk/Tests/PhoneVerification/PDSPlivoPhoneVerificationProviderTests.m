// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSPlivoPhoneVerificationProviderTests.m

 @abstract Tests for the Plivo Verify phone verification provider.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "PhoneVerification/PDSPlivoPhoneVerificationProvider.h"
#import "Services/Core/PDSPhoneVerificationProvider.h"
#import "Email/PDSSecretsProvider.h"

#pragma mark - Mock Secrets Provider

@interface PDSMockPlivoSecretsProvider : NSObject <PDSSecretsProvider>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *secrets;
@end

@implementation PDSMockPlivoSecretsProvider

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
        *error = [NSError errorWithDomain:@"PDSMockPlivoSecretsProviderErrorDomain"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"Secret not found: %@", key]}];
    }
    return value;
}

@end

#pragma mark - Tests

@interface PDSPlivoPhoneVerificationProviderTests : XCTestCase
@end

@implementation PDSPlivoPhoneVerificationProviderTests

- (void)testInitWithMissingAuthID {
    PDSMockPlivoSecretsProvider *secrets = [[PDSMockPlivoSecretsProvider alloc] init];
    secrets.secrets[@"PLIVO_AUTH_TOKEN"] = @"test-token";

    PDSPlivoPhoneVerificationProvider *provider =
        [[PDSPlivoPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                           configuration:@{}];

    NSError *error = nil;
    NSString *sessionID = [provider requestVerificationForPhoneNumber:@"+1234567890" error:&error];
    XCTAssertNil(sessionID);
    XCTAssertEqual(error.code, PDSPlivoProviderErrorMissingAuthID);
}

- (void)testInitWithMissingAuthToken {
    PDSMockPlivoSecretsProvider *secrets = [[PDSMockPlivoSecretsProvider alloc] init];
    secrets.secrets[@"PLIVO_AUTH_ID"] = @"test-id";

    PDSPlivoPhoneVerificationProvider *provider =
        [[PDSPlivoPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                           configuration:@{}];

    NSError *error = nil;
    NSString *sessionID = [provider requestVerificationForPhoneNumber:@"+1234567890" error:&error];
    XCTAssertNil(sessionID);
    XCTAssertEqual(error.code, PDSPlivoProviderErrorMissingAuthToken);
}

- (void)testRequestVerificationWithEmptyPhoneNumber {
    PDSMockPlivoSecretsProvider *secrets = [[PDSMockPlivoSecretsProvider alloc] init];
    secrets.secrets[@"PLIVO_AUTH_ID"] = @"test-id";
    secrets.secrets[@"PLIVO_AUTH_TOKEN"] = @"test-token";

    PDSPlivoPhoneVerificationProvider *provider =
        [[PDSPlivoPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                           configuration:@{}];

    NSError *error = nil;
    NSString *sessionID = [provider requestVerificationForPhoneNumber:@"" error:&error];
    XCTAssertNil(sessionID);
    XCTAssertEqual(error.code, PDSPlivoProviderErrorInvalidPhoneNumber);
}

- (void)testRequestVerificationWithNilPhoneNumber {
    PDSMockPlivoSecretsProvider *secrets = [[PDSMockPlivoSecretsProvider alloc] init];
    secrets.secrets[@"PLIVO_AUTH_ID"] = @"test-id";
    secrets.secrets[@"PLIVO_AUTH_TOKEN"] = @"test-token";

    PDSPlivoPhoneVerificationProvider *provider =
        [[PDSPlivoPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                           configuration:@{}];

    NSError *error = nil;
    NSString *sessionID = [provider requestVerificationForPhoneNumber:nil error:&error];
    XCTAssertNil(sessionID);
    XCTAssertEqual(error.code, PDSPlivoProviderErrorInvalidPhoneNumber);
}

- (void)testVerifyCodeWithEmptyCode {
    PDSMockPlivoSecretsProvider *secrets = [[PDSMockPlivoSecretsProvider alloc] init];
    secrets.secrets[@"PLIVO_AUTH_ID"] = @"test-id";
    secrets.secrets[@"PLIVO_AUTH_TOKEN"] = @"test-token";

    PDSPlivoPhoneVerificationProvider *provider =
        [[PDSPlivoPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                           configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"" forPhoneNumber:@"+1234567890" sessionID:@"sess-123" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSPlivoProviderErrorVerificationFailed);
}

- (void)testVerifyCodeWithEmptyPhoneNumber {
    PDSMockPlivoSecretsProvider *secrets = [[PDSMockPlivoSecretsProvider alloc] init];
    secrets.secrets[@"PLIVO_AUTH_ID"] = @"test-id";
    secrets.secrets[@"PLIVO_AUTH_TOKEN"] = @"test-token";

    PDSPlivoPhoneVerificationProvider *provider =
        [[PDSPlivoPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                           configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"123456" forPhoneNumber:@"" sessionID:@"sess-123" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSPlivoProviderErrorInvalidPhoneNumber);
}

- (void)testVerifyCodeWithNilSessionID {
    PDSMockPlivoSecretsProvider *secrets = [[PDSMockPlivoSecretsProvider alloc] init];
    secrets.secrets[@"PLIVO_AUTH_ID"] = @"test-id";
    secrets.secrets[@"PLIVO_AUTH_TOKEN"] = @"test-token";

    PDSPlivoPhoneVerificationProvider *provider =
        [[PDSPlivoPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                           configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"123456" forPhoneNumber:@"+1234567890" sessionID:nil error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSPlivoProviderErrorVerificationFailed);
}

- (void)testVerifyCodeWithEmptySessionID {
    PDSMockPlivoSecretsProvider *secrets = [[PDSMockPlivoSecretsProvider alloc] init];
    secrets.secrets[@"PLIVO_AUTH_ID"] = @"test-id";
    secrets.secrets[@"PLIVO_AUTH_TOKEN"] = @"test-token";

    PDSPlivoPhoneVerificationProvider *provider =
        [[PDSPlivoPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                           configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"123456" forPhoneNumber:@"+1234567890" sessionID:@"" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSPlivoProviderErrorVerificationFailed);
}

- (void)testProviderConformsToPhoneVerificationProtocol {
    PDSMockPlivoSecretsProvider *secrets = [[PDSMockPlivoSecretsProvider alloc] init];
    PDSPlivoPhoneVerificationProvider *provider =
        [[PDSPlivoPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                           configuration:@{}];

    XCTAssertTrue([provider conformsToProtocol:@protocol(PDSPhoneVerificationProvider)]);
}

- (void)testProviderSupportsVerifyCodeWithSessionIDMethod {
    PDSMockPlivoSecretsProvider *secrets = [[PDSMockPlivoSecretsProvider alloc] init];
    PDSPlivoPhoneVerificationProvider *provider =
        [[PDSPlivoPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                           configuration:@{}];

    XCTAssertTrue([provider respondsToSelector:@selector(verifyCode:forPhoneNumber:sessionID:error:)]);
}

@end
