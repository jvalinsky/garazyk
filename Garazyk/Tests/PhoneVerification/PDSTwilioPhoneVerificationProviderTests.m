/*!
 @file PDSTwilioPhoneVerificationProviderTests.m

 @abstract Tests for the Twilio Verify phone verification provider.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "PhoneVerification/PDSTwilioPhoneVerificationProvider.h"
#import "Services/Core/PDSPhoneVerificationProvider.h"
#import "Email/PDSSecretsProvider.h"

#pragma mark - Mock Secrets Provider

@interface PDSMockTwilioSecretsProvider : NSObject <PDSSecretsProvider>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *secrets;
@end

@implementation PDSMockTwilioSecretsProvider

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
        *error = [NSError errorWithDomain:@"PDSMockTwilioSecretsProviderErrorDomain"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"Secret not found: %@", key]}];
    }
    return value;
}

@end

#pragma mark - Tests

@interface PDSTwilioPhoneVerificationProviderTests : XCTestCase
@end

@implementation PDSTwilioPhoneVerificationProviderTests

- (void)testInitWithMissingAccountSID {
    PDSMockTwilioSecretsProvider *secrets = [[PDSMockTwilioSecretsProvider alloc] init];
    secrets.secrets[@"TWILIO_AUTH_TOKEN"] = @"test-token";
    secrets.secrets[@"TWILIO_VERIFY_SERVICE_SID"] = @"VAxxx";

    PDSTwilioPhoneVerificationProvider *provider =
        [[PDSTwilioPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider requestVerificationForPhoneNumber:@"+1234567890" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSTwilioProviderErrorMissingAccountSID);
}

- (void)testInitWithMissingAuthToken {
    PDSMockTwilioSecretsProvider *secrets = [[PDSMockTwilioSecretsProvider alloc] init];
    secrets.secrets[@"TWILIO_ACCOUNT_SID"] = @"ACxxx";
    secrets.secrets[@"TWILIO_VERIFY_SERVICE_SID"] = @"VAxxx";

    PDSTwilioPhoneVerificationProvider *provider =
        [[PDSTwilioPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider requestVerificationForPhoneNumber:@"+1234567890" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSTwilioProviderErrorMissingAuthToken);
}

- (void)testInitWithMissingServiceSID {
    PDSMockTwilioSecretsProvider *secrets = [[PDSMockTwilioSecretsProvider alloc] init];
    secrets.secrets[@"TWILIO_ACCOUNT_SID"] = @"ACxxx";
    secrets.secrets[@"TWILIO_AUTH_TOKEN"] = @"test-token";

    PDSTwilioPhoneVerificationProvider *provider =
        [[PDSTwilioPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider requestVerificationForPhoneNumber:@"+1234567890" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSTwilioProviderErrorMissingServiceSID);
}

- (void)testRequestVerificationWithEmptyPhoneNumber {
    PDSMockTwilioSecretsProvider *secrets = [[PDSMockTwilioSecretsProvider alloc] init];
    secrets.secrets[@"TWILIO_ACCOUNT_SID"] = @"ACxxx";
    secrets.secrets[@"TWILIO_AUTH_TOKEN"] = @"test-token";
    secrets.secrets[@"TWILIO_VERIFY_SERVICE_SID"] = @"VAxxx";

    PDSTwilioPhoneVerificationProvider *provider =
        [[PDSTwilioPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider requestVerificationForPhoneNumber:@"" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSTwilioProviderErrorInvalidPhoneNumber);
}

- (void)testRequestVerificationWithNilPhoneNumber {
    PDSMockTwilioSecretsProvider *secrets = [[PDSMockTwilioSecretsProvider alloc] init];
    secrets.secrets[@"TWILIO_ACCOUNT_SID"] = @"ACxxx";
    secrets.secrets[@"TWILIO_AUTH_TOKEN"] = @"test-token";
    secrets.secrets[@"TWILIO_VERIFY_SERVICE_SID"] = @"VAxxx";

    PDSTwilioPhoneVerificationProvider *provider =
        [[PDSTwilioPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider requestVerificationForPhoneNumber:nil error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSTwilioProviderErrorInvalidPhoneNumber);
}

- (void)testVerifyCodeWithEmptyCode {
    PDSMockTwilioSecretsProvider *secrets = [[PDSMockTwilioSecretsProvider alloc] init];
    secrets.secrets[@"TWILIO_ACCOUNT_SID"] = @"ACxxx";
    secrets.secrets[@"TWILIO_AUTH_TOKEN"] = @"test-token";
    secrets.secrets[@"TWILIO_VERIFY_SERVICE_SID"] = @"VAxxx";

    PDSTwilioPhoneVerificationProvider *provider =
        [[PDSTwilioPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"" forPhoneNumber:@"+1234567890" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSTwilioProviderErrorVerificationFailed);
}

- (void)testVerifyCodeWithEmptyPhoneNumber {
    PDSMockTwilioSecretsProvider *secrets = [[PDSMockTwilioSecretsProvider alloc] init];
    secrets.secrets[@"TWILIO_ACCOUNT_SID"] = @"ACxxx";
    secrets.secrets[@"TWILIO_AUTH_TOKEN"] = @"test-token";
    secrets.secrets[@"TWILIO_VERIFY_SERVICE_SID"] = @"VAxxx";

    PDSTwilioPhoneVerificationProvider *provider =
        [[PDSTwilioPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    NSError *error = nil;
    BOOL result = [provider verifyCode:@"123456" forPhoneNumber:@"" error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSTwilioProviderErrorInvalidPhoneNumber);
}

- (void)testProviderConformsToPhoneVerificationProtocol {
    PDSMockTwilioSecretsProvider *secrets = [[PDSMockTwilioSecretsProvider alloc] init];
    PDSTwilioPhoneVerificationProvider *provider =
        [[PDSTwilioPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    XCTAssertTrue([provider conformsToProtocol:@protocol(PDSPhoneVerificationProvider)]);
}

- (void)testProviderSupportsVerifyCodeMethod {
    PDSMockTwilioSecretsProvider *secrets = [[PDSMockTwilioSecretsProvider alloc] init];
    PDSTwilioPhoneVerificationProvider *provider =
        [[PDSTwilioPhoneVerificationProvider alloc] initWithSecretsProvider:secrets
                                                             configuration:@{}];

    XCTAssertTrue([provider respondsToSelector:@selector(verifyCode:forPhoneNumber:error:)]);
}

@end
