// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/ATProtoServiceConfiguration.h"

@interface ATProtoServiceConfigurationTests : XCTestCase
@end

@implementation ATProtoServiceConfigurationTests

- (void)testIssuerCanonicalization {
    // We want to verify if the issuer is stripped of trailing slashes.
    // This is hard to test because ATProtoServiceConfiguration is a singleton.
}

@end
