// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Email/PDSEmailProviderFactory.h"
#import "Email/PDSEmailProvider.h"
#import "Email/PDSMockEmailProvider.h"
#import "Email/PDSResendEmailProvider.h"
#import "App/ATProtoServiceConfiguration.h"

@interface PDSEmailProviderFactoryTests : XCTestCase
@property (nonatomic, strong) ATProtoServiceConfiguration *config;
@end

@implementation PDSEmailProviderFactoryTests

- (void)setUp {
    [super setUp];
    [PDSEmailProviderFactory resetCustomProviders];
    self.config = [[ATProtoServiceConfiguration alloc] init];
    [self.config setValue:@"noreply@example.com" forKey:@"resendFromAddress"];
    [self.config setValue:@"https://api.resend.com" forKey:@"resendAPIEndpoint"];
    [self.config setValue:@"env" forKey:@"resendAPIKeySource"];
}

- (void)tearDown {
    [PDSEmailProviderFactory resetCustomProviders];
    [super tearDown];
}

#pragma mark - Mock provider

- (void)testProviderWithName_MockExact_ReturnsMockProvider {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"mock"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNotNil(provider);
    XCTAssertTrue([provider isKindOfClass:[PDSMockEmailProvider class]]);
    XCTAssertNil(error);
}

- (void)testProviderWithName_MockCaseInsensitive_ReturnsMockProvider {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"MOCK"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertTrue([provider isKindOfClass:[PDSMockEmailProvider class]]);
}

- (void)testProviderWithName_MockMixedCase_ReturnsMockProvider {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"Mock"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertTrue([provider isKindOfClass:[PDSMockEmailProvider class]]);
}

- (void)testProviderWithName_MockWhitespace_TrimsAndReturnsMock {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"  mock  "
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertTrue([provider isKindOfClass:[PDSMockEmailProvider class]]);
}

#pragma mark - SMTP rejection

- (void)testProviderWithName_Smtp_ReturnsNilUnsupportedError {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"smtp"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"com.atproto.pds.emailproviderfactory");
}

- (void)testProviderWithName_SmtpCaseInsensitive_ReturnsNilError {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"SMTP"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

#pragma mark - Resend provider

- (void)testProviderWithName_ResendWithConfig_ReturnsResendProvider {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"resend"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNotNil(provider);
    XCTAssertTrue([provider isKindOfClass:[PDSResendEmailProvider class]]);
    XCTAssertNil(error);
}

- (void)testProviderWithName_ResendNoFromAddress_ReturnsNilNotConfiguredError {
    [self.config setValue:nil forKey:@"resendFromAddress"];
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"resend"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"com.atproto.pds.emailproviderfactory");
}

- (void)testProviderWithName_ResendEmptyFromAddress_ReturnsNilNotConfiguredError {
    [self.config setValue:@"" forKey:@"resendFromAddress"];
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"resend"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

- (void)testProviderWithName_ResendCaseInsensitive_ReturnsResendProvider {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"Resend"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertTrue([provider isKindOfClass:[PDSResendEmailProvider class]]);
}

#pragma mark - Edge cases (nil, empty, whitespace, none)

- (void)testProviderWithName_Nil_ReturnsNilNotConfiguredError {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:nil
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 1); // PDSEmailProviderFactoryErrorNotConfigured
}

- (void)testProviderWithName_EmptyString_ReturnsNilNotConfiguredError {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@""
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

- (void)testProviderWithName_WhitespaceOnly_ReturnsNilNotConfiguredError {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"   "
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

- (void)testProviderWithName_None_ReturnsNilNotConfiguredError {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"none"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

- (void)testProviderWithName_NoneCaseInsensitive_ReturnsNilError {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"None"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

- (void)testProviderWithName_UnsupportedProvider_ReturnsNilUnsupportedError {
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"nonexistent-provider"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"com.atproto.pds.emailproviderfactory");
}

- (void)testProviderWithName_NullErrorPointer_Safe {
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"nonexistent"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:NULL];
    XCTAssertNil(provider);
}

#pragma mark - Custom provider registration

- (void)testRegisterProviderClass_Valid_ReturnsCustomProvider {
    [PDSEmailProviderFactory registerProviderClass:[PDSMockEmailProvider class] forName:@"custom-mock"];
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"custom-mock"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNotNil(provider);
    XCTAssertTrue([provider isKindOfClass:[PDSMockEmailProvider class]]);
    XCTAssertNil(error);
}

- (void)testUnregisterProvider_RemovesRegistration {
    [PDSEmailProviderFactory registerProviderClass:[PDSMockEmailProvider class] forName:@"temp-provider"];
    [PDSEmailProviderFactory unregisterProviderWithName:@"temp-provider"];
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"temp-provider"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

- (void)testResetCustomProviders_ClearsAll {
    [PDSEmailProviderFactory registerProviderClass:[PDSMockEmailProvider class] forName:@"provider-a"];
    [PDSEmailProviderFactory registerProviderClass:[PDSMockEmailProvider class] forName:@"provider-b"];
    [PDSEmailProviderFactory resetCustomProviders];
    NSError *error = nil;
    id<PDSEmailProvider> providerA = [PDSEmailProviderFactory providerWithName:@"provider-a"
                                                                 configuration:self.config
                                                                secretsProvider:nil
                                                                          error:&error];
    XCTAssertNil(providerA);
}

- (void)testRegisterProviderClass_NilName_DoesNotRegister {
    [PDSEmailProviderFactory registerProviderClass:[PDSMockEmailProvider class] forName:nil];
    // Should not crash and custom registries should remain empty
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@""
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNil(provider);
}

- (void)testRegisterProviderClass_EmptyName_DoesNotRegister {
    [PDSEmailProviderFactory registerProviderClass:[PDSMockEmailProvider class] forName:@""];
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@""
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertNil(provider);
}

- (void)testRegisterProviderClass_BuiltinName_DoesNotOverride {
    [PDSEmailProviderFactory registerProviderClass:[PDSResendEmailProvider class] forName:@"mock"];
    // Should still create PDSMockEmailProvider for "mock"
    NSError *error = nil;
    id<PDSEmailProvider> provider = [PDSEmailProviderFactory providerWithName:@"mock"
                                                                configuration:self.config
                                                               secretsProvider:nil
                                                                         error:&error];
    XCTAssertTrue([provider isKindOfClass:[PDSMockEmailProvider class]]);
}

#pragma mark - Supported identifiers

- (void)testSupportedIdentifiers_ContainsBuiltinProviders {
    NSArray<NSString *> *identifiers = [PDSEmailProviderFactory supportedIdentifiers];
    XCTAssertTrue([identifiers containsObject:@"mock"]);
    XCTAssertTrue([identifiers containsObject:@"resend"]);
    XCTAssertFalse([identifiers containsObject:@"smtp"]);
}

@end
