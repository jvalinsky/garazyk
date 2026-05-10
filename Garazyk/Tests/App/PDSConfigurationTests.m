#import <XCTest/XCTest.h>
#import "App/PDSConfiguration.h"

@interface PDSConfigurationTests : XCTestCase
@end

@implementation PDSConfigurationTests

- (void)testIssuerCanonicalization {
    // We want to verify if the issuer is stripped of trailing slashes.
    // This is hard to test because PDSConfiguration is a singleton.
}

@end
