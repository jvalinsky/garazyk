/*!
 @file PDSRegistrationGateTests.m

 @abstract Tests for the registration gate system: protocol, composite, factory,
           invite code gate, and open gate.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "Registration/PDSRegistrationGate.h"
#import "Registration/PDSInviteCodeRegistrationGate.h"
#import "Registration/PDSPhoneOTPRegistrationGate.h"
#import "Registration/PDSCaptchaRegistrationGate.h"
#import "Registration/PDSOAuthOnlyRegistrationGate.h"
#import "App/PDSConfiguration.h"
#import "Database/Service/ServiceDatabases.h"

#pragma mark - Stub Gate (always fails)

@interface PDSStubFailingGate : NSObject <PDSRegistrationGate>
@end

@implementation PDSStubFailingGate

- (NSString *)gateIdentifier {
    return @"stub_failing";
}

- (BOOL)validateRegistrationRequest:(NSDictionary *)body
                       configuration:(PDSConfiguration *)configuration
                               error:(NSError **)error {
    if (error) {
        *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                     code:PDSRegistrationGateErrorNoGatePassed
                                 userInfo:@{
                                     NSLocalizedDescriptionKey: @"Stub gate always fails"
                                 }];
    }
    return NO;
}

@end

#pragma mark - Stub Gate (always passes)

@interface PDSStubPassingGate : NSObject <PDSRegistrationGate>
@end

@implementation PDSStubPassingGate

- (NSString *)gateIdentifier {
    return @"stub_passing";
}

- (BOOL)validateRegistrationRequest:(NSDictionary *)body
                       configuration:(PDSConfiguration *)configuration
                               error:(NSError **)error {
    return YES;
}

@end

#pragma mark - Tests

@interface PDSRegistrationGateTests : XCTestCase
@end

@implementation PDSRegistrationGateTests

#pragma mark - Open Gate

- (void)testOpenGateAlwaysPasses {
    PDSOpenRegistrationGate *gate = [[PDSOpenRegistrationGate alloc] init];
    XCTAssertEqualObjects(gate.gateIdentifier, @"open");

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{}
                                      configuration:nil
                                              error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testOpenGatePassesWithAnyBody {
    PDSOpenRegistrationGate *gate = [[PDSOpenRegistrationGate alloc] init];
    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"inviteCode": @"test"}
                                      configuration:nil
                                              error:&error];
    XCTAssertTrue(result);
}

#pragma mark - Composite Gate

- (void)testCompositeGateWithNoGatesAlwaysPasses {
    PDSCompositeRegistrationGate *composite = [[PDSCompositeRegistrationGate alloc] init];
    XCTAssertEqualObjects(composite.gateIdentifier, @"composite");
    XCTAssertEqual(composite.gates.count, 0);

    NSError *error = nil;
    BOOL result = [composite validateRegistrationRequest:@{}
                                          configuration:nil
                                                  error:&error];
    XCTAssertTrue(result);
}

- (void)testCompositeGateORLogicPassesIfAnyGatePasses {
    PDSCompositeRegistrationGate *composite = [[PDSCompositeRegistrationGate alloc] init];
    [composite addGate:[[PDSStubFailingGate alloc] init]];
    [composite addGate:[[PDSStubPassingGate alloc] init]];

    XCTAssertEqual(composite.gates.count, 2);

    NSError *error = nil;
    BOOL result = [composite validateRegistrationRequest:@{}
                                          configuration:nil
                                                  error:&error];
    XCTAssertTrue(result);
}

- (void)testCompositeGateORLogicFailsIfAllGatesFail {
    PDSCompositeRegistrationGate *composite = [[PDSCompositeRegistrationGate alloc] init];
    [composite addGate:[[PDSStubFailingGate alloc] init]];
    [composite addGate:[[PDSStubFailingGate alloc] init]];

    NSError *error = nil;
    BOOL result = [composite validateRegistrationRequest:@{}
                                          configuration:nil
                                                  error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PDSRegistrationGateErrorDomain);
}

- (void)testCompositeGateContainsGateWithIdentifier {
    PDSCompositeRegistrationGate *composite = [[PDSCompositeRegistrationGate alloc] init];
    [composite addGate:[[PDSOpenRegistrationGate alloc] init]];

    XCTAssertTrue([composite containsGateWithIdentifier:@"open"]);
    XCTAssertFalse([composite containsGateWithIdentifier:@"invite_code"]);
}

- (void)testCompositeGateSingleGatePasses {
    PDSCompositeRegistrationGate *composite = [[PDSCompositeRegistrationGate alloc] init];
    [composite addGate:[[PDSStubPassingGate alloc] init]];

    NSError *error = nil;
    BOOL result = [composite validateRegistrationRequest:@{}
                                          configuration:nil
                                                  error:&error];
    XCTAssertTrue(result);
}

#pragma mark - Invite Code Gate

- (void)testInviteCodeGateIdentifier {
    PDSInviteCodeRegistrationGate *gate =
        [[PDSInviteCodeRegistrationGate alloc] initWithServiceDatabases:nil];
    XCTAssertEqualObjects(gate.gateIdentifier, @"invite_code");
}

- (void)testInviteCodeGateRejectsMissingCode {
    PDSInviteCodeRegistrationGate *gate =
        [[PDSInviteCodeRegistrationGate alloc] initWithServiceDatabases:nil];

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PDSRegistrationGateErrorDomain);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInviteCodeRequired);
}

- (void)testInviteCodeGateRejectsEmptyCode {
    PDSInviteCodeRegistrationGate *gate =
        [[PDSInviteCodeRegistrationGate alloc] initWithServiceDatabases:nil];

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"inviteCode": @""}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInviteCodeRequired);
}

- (void)testInviteCodeGateRejectsInvalidCodeWithNilDatabase {
    // With nil ServiceDatabases, useInviteCode returns NO
    PDSInviteCodeRegistrationGate *gate =
        [[PDSInviteCodeRegistrationGate alloc] initWithServiceDatabases:nil];

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"inviteCode": @"INVALID-CODE"}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorInvalidInviteCode);
}

- (void)testInviteCodeGateAcceptsValidCode {
    PDSServiceDatabases *db = [self createTestServiceDatabases];
    if (!db) return;

    // Create a valid invite code
    NSString *code = @"TEST1-TEST2-TEST3-TEST4";
    NSError *createError = nil;
    [db createInviteCode:code forAccount:@"did:plc:system" maxUses:1 error:&createError];

    PDSInviteCodeRegistrationGate *gate =
        [[PDSInviteCodeRegistrationGate alloc] initWithServiceDatabases:db];

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"inviteCode": code}
                                      configuration:nil
                                              error:&error];
    XCTAssertTrue(result);
}

#pragma mark - Factory

- (void)testFactoryReturnsOpenGateWhenNoGatesEnabled {
    PDSConfiguration *config = [[PDSConfiguration alloc] init];
    // Default config has inviteCodeRequired = NO

    NSError *error = nil;
    id<PDSRegistrationGate> gate = [PDSRegistrationGateFactory gateFromConfiguration:config
                                                                   serviceDatabases:nil
                                                                              error:&error];
    XCTAssertNotNil(gate);
    XCTAssertEqualObjects(gate.gateIdentifier, @"open");
}

- (void)testFactoryReturnsInviteCodeGateWhenEnabled {
    PDSConfiguration *config = [[PDSConfiguration alloc] init];
    // Enable invite code required via KVC
    [config setValue:@YES forKey:@"inviteCodeRequired"];

    NSError *error = nil;
    id<PDSRegistrationGate> gate = [PDSRegistrationGateFactory gateFromConfiguration:config
                                                                   serviceDatabases:nil
                                                                              error:&error];
    XCTAssertNotNil(gate);
    XCTAssertEqualObjects(gate.gateIdentifier, @"invite_code");
}

- (void)testFactoryCustomGateRegistration {
    [PDSRegistrationGateFactory registerGateClass:[PDSStubPassingGate class]
                                    forIdentifier:@"stub_passing"];

    // Verify the factory doesn't crash with custom gates registered
    PDSConfiguration *config = [[PDSConfiguration alloc] init];
    NSError *error = nil;
    id<PDSRegistrationGate> gate = [PDSRegistrationGateFactory gateFromConfiguration:config
                                                                   serviceDatabases:nil
                                                                              error:&error];
    XCTAssertNotNil(gate);

    [PDSRegistrationGateFactory unregisterGateForIdentifier:@"stub_passing"];
    [PDSRegistrationGateFactory resetCustomGates];
}

#pragma mark - Phone OTP Gate

- (void)testPhoneOTPGateIdentifier {
    PDSPhoneOTPRegistrationGate *gate =
        [[PDSPhoneOTPRegistrationGate alloc] initWithPhoneVerificationProvider:nil];
    XCTAssertEqualObjects(gate.gateIdentifier, @"phone_otp");
}

- (void)testPhoneOTPGateRejectsMissingCode {
    PDSPhoneOTPRegistrationGate *gate =
        [[PDSPhoneOTPRegistrationGate alloc] initWithPhoneVerificationProvider:nil];

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorPhoneVerificationRequired);
}

- (void)testPhoneOTPGateRejectsEmptyCode {
    PDSPhoneOTPRegistrationGate *gate =
        [[PDSPhoneOTPRegistrationGate alloc] initWithPhoneVerificationProvider:nil];

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"phoneVerificationCode": @""}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorPhoneVerificationRequired);
}

- (void)testPhoneOTPGateAcceptsNonEmptyCode {
    PDSPhoneOTPRegistrationGate *gate =
        [[PDSPhoneOTPRegistrationGate alloc] initWithPhoneVerificationProvider:nil];

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"phoneVerificationCode": @"123456",
                                                       @"phoneNumber": @"+1234567890"}
                                      configuration:nil
                                              error:&error];
    XCTAssertTrue(result);
}

#pragma mark - CAPTCHA Gate

- (void)testCaptchaGateIdentifier {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:nil
                                                   secretKey:nil];
    XCTAssertEqualObjects(gate.gateIdentifier, @"captcha");
}

- (void)testCaptchaGateRejectsMissingToken {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:nil
                                                   secretKey:nil];

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorCaptchaRequired);
}

- (void)testCaptchaGateRejectsEmptyToken {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:nil
                                                   secretKey:nil];

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @""}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorCaptchaRequired);
}

- (void)testCaptchaGateAcceptsNonEmptyToken {
    PDSCaptchaRegistrationGate *gate =
        [[PDSCaptchaRegistrationGate alloc] initWithProvider:@"turnstile"
                                                     siteKey:nil
                                                   secretKey:nil];

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"captchaToken": @"test-token-abc"}
                                      configuration:nil
                                              error:&error];
    XCTAssertTrue(result);
}

#pragma mark - OAuth-Only Gate

- (void)testOAuthOnlyGateIdentifier {
    PDSOAuthOnlyRegistrationGate *gate = [[PDSOAuthOnlyRegistrationGate alloc] init];
    XCTAssertEqualObjects(gate.gateIdentifier, @"oauth_only");
}

- (void)testOAuthOnlyGateAlwaysRejects {
    PDSOAuthOnlyRegistrationGate *gate = [[PDSOAuthOnlyRegistrationGate alloc] init];

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result);
    XCTAssertEqual(error.code, PDSRegistrationGateErrorOAuthOnlyRegistration);
}

- (void)testOAuthOnlyGateRejectsEvenWithBody {
    PDSOAuthOnlyRegistrationGate *gate = [[PDSOAuthOnlyRegistrationGate alloc] init];

    NSError *error = nil;
    BOOL result = [gate validateRegistrationRequest:@{@"email": @"test@example.com"}
                                      configuration:nil
                                              error:&error];
    XCTAssertFalse(result);
}

#pragma mark - Composite with Multiple Gates

- (void)testCompositeWithInviteAndPhoneOTPPassesWithInviteCode {
    PDSServiceDatabases *db = [self createTestServiceDatabases];
    if (!db) return;

    NSString *code = @"INVITE-TEST-CODE-1";
    [db createInviteCode:code forAccount:@"did:plc:system" maxUses:1 error:nil];

    PDSCompositeRegistrationGate *composite = [[PDSCompositeRegistrationGate alloc] init];
    [composite addGate:[[PDSInviteCodeRegistrationGate alloc] initWithServiceDatabases:db]];
    [composite addGate:[[PDSPhoneOTPRegistrationGate alloc] initWithPhoneVerificationProvider:nil]];

    // Provide invite code but not phone OTP — should pass (OR logic)
    NSError *error = nil;
    BOOL result = [composite validateRegistrationRequest:@{@"inviteCode": code}
                                          configuration:nil
                                                  error:&error];
    XCTAssertTrue(result);
}

- (void)testCompositeWithInviteAndPhoneOTPPassesWithPhoneCode {
    PDSServiceDatabases *db = [self createTestServiceDatabases];
    if (!db) return;

    PDSCompositeRegistrationGate *composite = [[PDSCompositeRegistrationGate alloc] init];
    [composite addGate:[[PDSInviteCodeRegistrationGate alloc] initWithServiceDatabases:db]];
    [composite addGate:[[PDSPhoneOTPRegistrationGate alloc] initWithPhoneVerificationProvider:nil]];

    // Provide phone OTP but not invite code — should pass (OR logic)
    NSError *error = nil;
    BOOL result = [composite validateRegistrationRequest:@{@"phoneVerificationCode": @"123456",
                                                            @"phoneNumber": @"+1234567890"}
                                          configuration:nil
                                                  error:&error];
    XCTAssertTrue(result);
}

#pragma mark - Error Domain

- (void)testErrorDomainExists {
    XCTAssertEqualObjects(PDSRegistrationGateErrorDomain, @"com.atproto.pds.registrationgate");
}

- (void)testErrorCodesAreDistinct {
    XCTAssertNotEqual(PDSRegistrationGateErrorInviteCodeRequired,
                       PDSRegistrationGateErrorInvalidInviteCode);
    XCTAssertNotEqual(PDSRegistrationGateErrorPhoneVerificationRequired,
                       PDSRegistrationGateErrorCaptchaRequired);
    XCTAssertNotEqual(PDSRegistrationGateErrorOAuthOnlyRegistration,
                       PDSRegistrationGateErrorNoGatePassed);
}

#pragma mark - Helpers

- (nullable PDSServiceDatabases *)createTestServiceDatabases {
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *serviceDir = [tmpDir stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"gate_test_%@", NSUUID.UUID.UUIDString]];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:serviceDir withIntermediateDirectories:YES attributes:nil error:nil];

    PDSServiceDatabases *db = [[PDSServiceDatabases alloc] initWithDirectory:serviceDir
                                                             serviceMaxSize:10
                                                           didCacheMaxSize:10
                                                         sequencerMaxSize:10];
    if (!db) return nil;

    [self addTeardownBlock:^{
        [fm removeItemAtPath:serviceDir error:nil];
    }];

    return db;
}

@end
