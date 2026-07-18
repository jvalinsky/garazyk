// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/PDSSecondFactorService.h"
#import "Auth/Base32Utils.h"
#import "Auth/TOTPService.h"
#import "Auth/TOTPGenerator.h"

#pragma mark - Test Account Stub

@interface TestSecondFactorAccount : NSObject
@property (nonatomic, assign) BOOL tfaEnabled;
@property (nonatomic, assign) BOOL webauthnEnabled;
@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy) NSData *tfaSecret;
@end

@implementation TestSecondFactorAccount
@end

#pragma mark - Tests

@interface PDSSecondFactorServiceTests : XCTestCase
@end

@implementation PDSSecondFactorServiceTests

#pragma mark - Error Domain and Codes

- (void)testErrorDomainConstant {
    XCTAssertEqualObjects(PDSSecondFactorErrorDomain, @"com.atproto.pds.second_factor");
}

- (void)testATProtoErrorKeyConstant {
    XCTAssertEqualObjects(PDSSecondFactorATProtoErrorKey, @"atproto.error");
}

#pragma mark - Account Requirement Check

- (void)testAccountRequiresSecondFactorTFADisabledWebAuthnDisabled {
    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.tfaEnabled = NO;
    account.webauthnEnabled = NO;

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    XCTAssertFalse([service accountRequiresSecondFactor:(id)account]);
}

- (void)testAccountRequiresSecondFactorTFAEnabled {
    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.tfaEnabled = YES;
    account.webauthnEnabled = NO;

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    XCTAssertTrue([service accountRequiresSecondFactor:(id)account]);
}

- (void)testAccountRequiresSecondFactorWebAuthnEnabled {
    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.tfaEnabled = NO;
    account.webauthnEnabled = YES;

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    XCTAssertTrue([service accountRequiresSecondFactor:(id)account]);
}

- (void)testAccountRequiresSecondFactorBothEnabled {
    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.tfaEnabled = YES;
    account.webauthnEnabled = YES;

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    XCTAssertTrue([service accountRequiresSecondFactor:(id)account]);
}

#pragma mark - Auth Factor Token Verification

- (void)testVerifyAuthFactorTokenNo2FARequired {
    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.tfaEnabled = NO;
    account.webauthnEnabled = NO;
    account.did = @"did:plc:test";

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [service verifyAuthFactorToken:nil forAccount:(id)account error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testVerifyAuthFactorTokenEmptyTokenRequired {
    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.tfaEnabled = YES;
    account.webauthnEnabled = NO;
    account.did = @"did:plc:test";

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [service verifyAuthFactorToken:@"" forAccount:(id)account error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PDSSecondFactorErrorDomain);
    XCTAssertEqual(error.code, PDSSecondFactorErrorRequired);
}

- (void)testVerifyAuthFactorTokenNilTokenRequired {
    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.tfaEnabled = YES;
    account.webauthnEnabled = NO;
    account.did = @"did:plc:test";

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [service verifyAuthFactorToken:nil forAccount:(id)account error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSSecondFactorErrorRequired);
}

- (void)testVerifyAuthFactorTokenInvalidToken {
    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.tfaEnabled = YES;
    account.webauthnEnabled = NO;
    account.did = @"did:plc:test";

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [service verifyAuthFactorToken:@"invalid-token" forAccount:(id)account error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PDSSecondFactorErrorDomain);
}

#pragma mark - TOTP Verification

- (void)testVerifyAuthFactorTokenTOTPValidCode {
    NSString *base32Secret = @"JBSWY3DPEHPK3PXP";
    NSData *secretData = [Base32Utils dataFromBase32String:base32Secret];

    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.tfaEnabled = YES;
    account.webauthnEnabled = NO;
    account.did = @"did:plc:test";
    account.tfaSecret = secretData;

    TOTPGenerator *gen = [[TOTPGenerator alloc] initWithSecret:secretData];
    NSString *validCode = [gen generateOTP];

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [service verifyAuthFactorToken:validCode forAccount:(id)account error:&error];
    XCTAssertTrue(result, @"Valid TOTP code should pass verification");
}

- (void)testVerifyAuthFactorTokenTOTPInvalidCode {
    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.tfaEnabled = YES;
    account.webauthnEnabled = NO;
    account.did = @"did:plc:test";
    account.tfaSecret = [Base32Utils dataFromBase32String:@"JBSWY3DPEHPK3PXP"];

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    NSError *error = nil;
    BOOL result = [service verifyAuthFactorToken:@"000000" forAccount:(id)account error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testVerifyAuthFactorTokenTOTPWrongLength {
    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.tfaEnabled = YES;
    account.webauthnEnabled = NO;
    account.did = @"did:plc:test";
    account.tfaSecret = [Base32Utils dataFromBase32String:@"JBSWY3DPEHPK3PXP"];

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    NSError *error = nil;
    // Not 6 digits — should not match TOTP path
    BOOL result = [service verifyAuthFactorToken:@"123" forAccount:(id)account error:&error];
    XCTAssertFalse(result);
}

#pragma mark - WebAuthn Unavailable Without Credentials

- (void)testBeginWebAuthnLoginWebAuthnDisabled {
    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.webauthnEnabled = NO;

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    NSError *error = nil;
    NSDictionary *result = [service beginWebAuthnLoginForAccount:(id)account error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PDSSecondFactorErrorDomain);
    XCTAssertEqual(error.code, PDSSecondFactorErrorUnavailable);
    XCTAssertTrue([error.userInfo[NSLocalizedDescriptionKey] containsString:@"not enabled"]);
}

- (void)testCompleteWebAuthnLoginWebAuthnDisabled {
    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.webauthnEnabled = NO;

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    NSError *error = nil;
    NSString *result = [service completeWebAuthnLoginWithSessionID:@"session" assertion:@{} forAccount:(id)account error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSSecondFactorErrorUnavailable);
}

#pragma mark - Error Constructors

- (void)testErrorUserInfoContainsATProtoKey {
    TestSecondFactorAccount *account = [[TestSecondFactorAccount alloc] init];
    account.tfaEnabled = YES;
    account.webauthnEnabled = NO;
    account.did = @"did:plc:test";

    PDSSecondFactorService *service = [[PDSSecondFactorService alloc] initWithServiceDatabases:nil origin:@"https://example.com"];
    NSError *error = nil;
    [service verifyAuthFactorToken:@"" forAccount:(id)account error:&error];
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.userInfo[PDSSecondFactorATProtoErrorKey], @"AuthFactorTokenRequired");
}

@end
