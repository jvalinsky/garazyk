// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/Relay/RelayIngressConfiguration.h"

@interface RelayIngressConfigurationTests : XCTestCase
@end

@implementation RelayIngressConfigurationTests

- (void)setUp {
    [super setUp];
    unsetenv("RELAY_LEGACY_INGRESS");
    unsetenv("RELAY_INGRESS_MAX_EVENTS");
    unsetenv("RELAY_INGRESS_MAX_BYTES");
    unsetenv("RELAY_INGRESS_LOW_EVENTS");
    unsetenv("RELAY_INGRESS_LOW_BYTES");
    unsetenv("RELAY_INGRESS_HIGH_EVENTS");
    unsetenv("RELAY_INGRESS_HIGH_BYTES");
    unsetenv("RELAY_INGRESS_SHARDS");
}

- (void)tearDown {
    unsetenv("RELAY_LEGACY_INGRESS");
    unsetenv("RELAY_INGRESS_MAX_EVENTS");
    unsetenv("RELAY_INGRESS_MAX_BYTES");
    unsetenv("RELAY_INGRESS_LOW_EVENTS");
    unsetenv("RELAY_INGRESS_LOW_BYTES");
    unsetenv("RELAY_INGRESS_HIGH_EVENTS");
    unsetenv("RELAY_INGRESS_HIGH_BYTES");
    unsetenv("RELAY_INGRESS_SHARDS");
    [super tearDown];
}

// MARK: - configurationFromEnvironment: parsing edge cases (F8)

- (void)testConfigurationFromEnvironment_OverflowingValue_ReturnsNilWithError {
    setenv("RELAY_INGRESS_MAX_EVENTS", "99999999999999999999999999", 1);

    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationFromEnvironment:&error];

    XCTAssertNil(config);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, RelayIngressConfigurationErrorDomain);
    XCTAssertEqual(error.code, RelayIngressConfigurationErrorCodeOverflow);
}

- (void)testConfigurationFromEnvironment_ZeroValue_ReturnsNilWithPositiveIntegerMessage {
    setenv("RELAY_INGRESS_MAX_EVENTS", "0", 1);

    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationFromEnvironment:&error];

    XCTAssertNil(config);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, RelayIngressConfigurationErrorCodeOverflow);
    XCTAssertFalse([error.localizedDescription containsString:@"overflow"],
                    @"zero is not an overflow: %@", error.localizedDescription);
}

- (void)testConfigurationFromEnvironment_NonDigitValue_ReturnsNilWithError {
    setenv("RELAY_INGRESS_MAX_EVENTS", "not-a-number", 1);

    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationFromEnvironment:&error];

    XCTAssertNil(config);
    XCTAssertNotNil(error);
}

- (void)testConfigurationFromEnvironment_ValidValues_ReturnsConfig {
    setenv("RELAY_INGRESS_MAX_EVENTS", "4096", 1);
    setenv("RELAY_INGRESS_MAX_BYTES", "1048576", 1);
    setenv("RELAY_INGRESS_LOW_EVENTS", "1024", 1);
    setenv("RELAY_INGRESS_LOW_BYTES", "524288", 1);
    setenv("RELAY_INGRESS_SHARDS", "8", 1);

    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationFromEnvironment:&error];

    XCTAssertNotNil(config);
    XCTAssertNil(error);
    XCTAssertEqual(config.maxEventCount, (NSUInteger)4096);
    XCTAssertEqual(config.maxByteCount, (uint64_t)1048576);
    XCTAssertEqual(config.lowEventWatermark, (NSUInteger)1024);
    XCTAssertEqual(config.lowByteWatermark, (uint64_t)524288);
    XCTAssertEqual(config.shardCount, (NSUInteger)8);
}

- (void)testConfigurationFromEnvironment_NoOverrides_UsesDefaults {
    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationFromEnvironment:&error];

    XCTAssertNotNil(config);
    XCTAssertNil(error);
    XCTAssertEqual(config.maxEventCount, (NSUInteger)2048);
    XCTAssertEqual(config.shardCount, (NSUInteger)4);
    XCTAssertTrue(config.boundedIngressEnabled);
}

// MARK: - shardCount ceiling (F9)

- (void)testConfigurationWithMaxEventCount_ShardCountAboveCeiling_ReturnsNilWithInvalidLimitsError {
    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:2048
                                                            maxByteCount:64ULL * 1024ULL * 1024ULL
                                                      lowEventWatermark:1024
                                                        lowByteWatermark:32ULL * 1024ULL * 1024ULL
                                                       highEventWatermark:1792
                                                         highByteWatermark:56ULL * 1024ULL * 1024ULL
                                                              shardCount:257
                                                   boundedIngressEnabled:YES
                                                                   error:&error];

    XCTAssertNil(config);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, RelayIngressConfigurationErrorDomain);
    XCTAssertEqual(error.code, RelayIngressConfigurationErrorCodeInvalidLimits);
}

- (void)testConfigurationWithMaxEventCount_ShardCountAtCeiling_Succeeds {
    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:2048
                                                            maxByteCount:64ULL * 1024ULL * 1024ULL
                                                      lowEventWatermark:1024
                                                        lowByteWatermark:32ULL * 1024ULL * 1024ULL
                                                       highEventWatermark:1792
                                                         highByteWatermark:56ULL * 1024ULL * 1024ULL
                                                              shardCount:256
                                                   boundedIngressEnabled:YES
                                                                   error:&error];

    XCTAssertNotNil(config);
    XCTAssertNil(error);
    XCTAssertEqual(config.shardCount, (NSUInteger)256);
}

// MARK: - high watermark bounds (F3)

- (void)testConfigurationWithMaxEventCount_HighEventWatermarkEqualsLow_ReturnsNilWithInvalidWatermarksError {
    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:2048
                                                            maxByteCount:64ULL * 1024ULL * 1024ULL
                                                      lowEventWatermark:1024
                                                        lowByteWatermark:32ULL * 1024ULL * 1024ULL
                                                       highEventWatermark:1024
                                                         highByteWatermark:56ULL * 1024ULL * 1024ULL
                                                              shardCount:4
                                                   boundedIngressEnabled:YES
                                                                   error:&error];

    XCTAssertNil(config);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, RelayIngressConfigurationErrorDomain);
    XCTAssertEqual(error.code, RelayIngressConfigurationErrorCodeInvalidWatermarks);
}

- (void)testConfigurationWithMaxEventCount_HighByteWatermarkEqualsLow_ReturnsNilWithInvalidWatermarksError {
    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:2048
                                                            maxByteCount:64ULL * 1024ULL * 1024ULL
                                                      lowEventWatermark:1024
                                                        lowByteWatermark:32ULL * 1024ULL * 1024ULL
                                                       highEventWatermark:1792
                                                         highByteWatermark:32ULL * 1024ULL * 1024ULL
                                                              shardCount:4
                                                   boundedIngressEnabled:YES
                                                                   error:&error];

    XCTAssertNil(config);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, RelayIngressConfigurationErrorDomain);
    XCTAssertEqual(error.code, RelayIngressConfigurationErrorCodeInvalidWatermarks);
}

- (void)testConfigurationWithMaxEventCount_HighEventWatermarkEqualsMax_ReturnsNilWithInvalidWatermarksError {
    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:2048
                                                            maxByteCount:64ULL * 1024ULL * 1024ULL
                                                      lowEventWatermark:1024
                                                        lowByteWatermark:32ULL * 1024ULL * 1024ULL
                                                       highEventWatermark:2048
                                                         highByteWatermark:56ULL * 1024ULL * 1024ULL
                                                              shardCount:4
                                                   boundedIngressEnabled:YES
                                                                   error:&error];

    XCTAssertNil(config);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, RelayIngressConfigurationErrorDomain);
    XCTAssertEqual(error.code, RelayIngressConfigurationErrorCodeInvalidWatermarks);
}

- (void)testConfigurationWithMaxEventCount_HighByteWatermarkEqualsMax_ReturnsNilWithInvalidWatermarksError {
    // This is the exact shape of F3: if the high byte watermark could equal maxByteCount, it
    // collapses onto the hard cap and can never fire for events whose size exceeds the residual
    // headroom below max, because admission rejects them first.
    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:2048
                                                            maxByteCount:64ULL * 1024ULL * 1024ULL
                                                      lowEventWatermark:1024
                                                        lowByteWatermark:32ULL * 1024ULL * 1024ULL
                                                       highEventWatermark:1792
                                                         highByteWatermark:64ULL * 1024ULL * 1024ULL
                                                              shardCount:4
                                                   boundedIngressEnabled:YES
                                                                   error:&error];

    XCTAssertNil(config);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, RelayIngressConfigurationErrorDomain);
    XCTAssertEqual(error.code, RelayIngressConfigurationErrorCodeInvalidWatermarks);
}

- (void)testConfigurationWithMaxEventCount_HighWatermarkBetweenLowAndMax_Succeeds {
    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationWithMaxEventCount:2048
                                                            maxByteCount:64ULL * 1024ULL * 1024ULL
                                                      lowEventWatermark:1024
                                                        lowByteWatermark:32ULL * 1024ULL * 1024ULL
                                                       highEventWatermark:1792
                                                         highByteWatermark:56ULL * 1024ULL * 1024ULL
                                                              shardCount:4
                                                   boundedIngressEnabled:YES
                                                                   error:&error];

    XCTAssertNotNil(config);
    XCTAssertNil(error);
    XCTAssertEqual(config.highEventWatermark, (NSUInteger)1792);
    XCTAssertEqual(config.highByteWatermark, (uint64_t)(56ULL * 1024ULL * 1024ULL));
}

// MARK: - configurationFromEnvironment: high watermark overrides

- (void)testConfigurationFromEnvironment_HighWatermarkOverrides_ReturnsConfig {
    setenv("RELAY_INGRESS_MAX_EVENTS", "4096", 1);
    setenv("RELAY_INGRESS_MAX_BYTES", "1048576", 1);
    setenv("RELAY_INGRESS_LOW_EVENTS", "1024", 1);
    setenv("RELAY_INGRESS_LOW_BYTES", "262144", 1);
    setenv("RELAY_INGRESS_HIGH_EVENTS", "3584", 1);
    setenv("RELAY_INGRESS_HIGH_BYTES", "917504", 1);

    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationFromEnvironment:&error];

    XCTAssertNotNil(config);
    XCTAssertNil(error);
    XCTAssertEqual(config.highEventWatermark, (NSUInteger)3584);
    XCTAssertEqual(config.highByteWatermark, (uint64_t)917504);
}

- (void)testConfigurationFromEnvironment_NoHighWatermarkOverrides_UsesDefaultConfigurationValues {
    NSError *error = nil;
    ATProtoRelayIngressConfiguration *config =
        [ATProtoRelayIngressConfiguration configurationFromEnvironment:&error];
    ATProtoRelayIngressConfiguration *defaults = [ATProtoRelayIngressConfiguration defaultConfiguration];

    XCTAssertNotNil(config);
    XCTAssertNil(error);
    XCTAssertEqual(config.highEventWatermark, defaults.highEventWatermark);
    XCTAssertEqual(config.highByteWatermark, defaults.highByteWatermark);
}

@end
