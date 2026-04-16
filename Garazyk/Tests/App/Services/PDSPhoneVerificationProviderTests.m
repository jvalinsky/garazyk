#import <XCTest/XCTest.h>
#import "Services/Core/PDSPhoneVerificationProvider.h"

@interface PDSCustomPhoneVerificationProvider : NSObject <PDSPhoneVerificationProvider>
@end

@implementation PDSCustomPhoneVerificationProvider

- (BOOL)requestVerificationForPhoneNumber:(NSString *)phoneNumber error:(NSError **)error {
    (void)phoneNumber;
    (void)error;
    return YES;
}

@end

@interface PDSInvalidPhoneVerificationProvider : NSObject
@end

@implementation PDSInvalidPhoneVerificationProvider
@end

@interface PDSPhoneVerificationProviderTests : XCTestCase
@end

@implementation PDSPhoneVerificationProviderTests

- (void)setUp {
    [super setUp];
    [PDSPhoneVerificationProviderFactory resetCustomProviders];
}

- (void)tearDown {
    [PDSPhoneVerificationProviderFactory resetCustomProviders];
    [super tearDown];
}

- (void)testProviderWithNameReturnsNotConfiguredForNone {
    NSError *error = nil;
    id<PDSPhoneVerificationProvider> provider = [PDSPhoneVerificationProviderFactory providerWithName:@"none"
                                                                                                  error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PDSPhoneVerificationProviderErrorDomain);
    XCTAssertEqual(error.code, PDSPhoneVerificationProviderErrorNotConfigured);
}

- (void)testProviderWithNameReturnsMockProvider {
    NSError *error = nil;
    id<PDSPhoneVerificationProvider> provider = [PDSPhoneVerificationProviderFactory providerWithName:@"mock"
                                                                                                  error:&error];
    XCTAssertNotNil(provider);
    XCTAssertNil(error);
}

- (void)testCustomProviderRegistrationAndLookup {
    [PDSPhoneVerificationProviderFactory registerProviderClass:[PDSCustomPhoneVerificationProvider class]
                                                       forName:@"custom-test"];

    NSError *error = nil;
    id<PDSPhoneVerificationProvider> provider = [PDSPhoneVerificationProviderFactory providerWithName:@" custom-test "
                                                                                                  error:&error];
    XCTAssertNotNil(provider);
    XCTAssertTrue([provider isKindOfClass:[PDSCustomPhoneVerificationProvider class]]);
    XCTAssertNil(error);
}

- (void)testUnregisterProviderRemovesCustomProvider {
    [PDSPhoneVerificationProviderFactory registerProviderClass:[PDSCustomPhoneVerificationProvider class]
                                                       forName:@"custom-test"];
    [PDSPhoneVerificationProviderFactory unregisterProviderWithName:@"custom-test"];

    NSError *error = nil;
    id<PDSPhoneVerificationProvider> provider = [PDSPhoneVerificationProviderFactory providerWithName:@"custom-test"
                                                                                                  error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PDSPhoneVerificationProviderErrorDomain);
    XCTAssertEqual(error.code, PDSPhoneVerificationProviderErrorUnsupportedProvider);
}

- (void)testRegisterIgnoresInvalidProviderClass {
    [PDSPhoneVerificationProviderFactory registerProviderClass:[PDSInvalidPhoneVerificationProvider class]
                                                       forName:@"bad-provider"];

    NSError *error = nil;
    id<PDSPhoneVerificationProvider> provider = [PDSPhoneVerificationProviderFactory providerWithName:@"bad-provider"
                                                                                                  error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PDSPhoneVerificationProviderErrorDomain);
    XCTAssertEqual(error.code, PDSPhoneVerificationProviderErrorUnsupportedProvider);
}

@end
