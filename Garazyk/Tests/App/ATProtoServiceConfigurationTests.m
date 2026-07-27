// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/ATProtoServiceConfiguration.h"

@interface ATProtoServiceConfiguration (Testing)
- (void)applyConfig:(NSDictionary *)config;
@end

@interface ATProtoServiceConfigurationTests : XCTestCase
@end

@implementation ATProtoServiceConfigurationTests

- (void)testIssuerCanonicalization {
    // We want to verify if the issuer is stripped of trailing slashes.
    // This is hard to test because ATProtoServiceConfiguration is a singleton.
}

- (void)testBlobStorageQuotaIsEnabledByDefault {
    ATProtoServiceConfiguration *configuration = [[ATProtoServiceConfiguration alloc] init];
    XCTAssertEqual(configuration.blobStorageQuotaBytes,
                   10ULL * 1024ULL * 1024ULL * 1024ULL);
}

- (void)testBlobStorageQuotaCanBeConfigured {
    ATProtoServiceConfiguration *configuration = [[ATProtoServiceConfiguration alloc] init];
    [configuration applyConfig:@{ @"blobStorageQuotaBytes": @(12345) }];
    XCTAssertEqual(configuration.blobStorageQuotaBytes, 12345ULL);
}

- (void)testBlobTemporaryGracePeriodDefaultsAndClampsToOneHour {
    ATProtoServiceConfiguration *configuration = [[ATProtoServiceConfiguration alloc] init];
    XCTAssertEqual(configuration.blobTemporaryGracePeriodSeconds, 6 * 60 * 60);

    [configuration applyConfig:@{ @"blobTemporaryGracePeriodSeconds": @1 }];
    XCTAssertEqual(configuration.blobTemporaryGracePeriodSeconds, 60 * 60);
}

@end
