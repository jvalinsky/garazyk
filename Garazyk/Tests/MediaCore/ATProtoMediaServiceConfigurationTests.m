// SPDX-License-Identifier: MIT
// ... (standard header omitted for brevity)

#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoMediaServiceConfiguration.h"

@interface ATProtoMediaServiceConfigurationTests : XCTestCase
@end

@implementation ATProtoMediaServiceConfigurationTests

// MARK: - configurationFromEnvironmentWithPrefix:

- (void)testConfigFromEnvironment_SetsValues
{
    setenv("TESTCFG_PORT", "9999", 1);
    setenv("TESTCFG_PDS_URL", "http://test-pds.example.com", 1);
    setenv("TESTCFG_MAX_CONCURRENT_JOBS", "4", 1);
    setenv("TESTCFG_MAX_UPLOAD_BYTES", "52428800", 1);
    setenv("TESTCFG_MAX_DURATION", "300", 1);
    setenv("TESTCFG_POLL_INTERVAL", "10.0", 1);
    setenv("TESTCFG_DID", "did:plc:testservice", 1);
    setenv("TESTCFG_HIGH_QUALITY", "true", 1);

    ATProtoMediaServiceConfiguration *config =
        [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"TESTCFG"];
    XCTAssertNotNil(config);
    XCTAssertEqual(config.port, 9999);
    XCTAssertEqualObjects(config.pdsURL, @"http://test-pds.example.com");
    XCTAssertEqual(config.maxConcurrentJobs, 4);
    XCTAssertEqual(config.maxUploadBytes, 52428800);
    XCTAssertEqual(config.maxDurationSeconds, 300);
    XCTAssertEqual(config.pollInterval, 10.0);
    XCTAssertEqualObjects(config.serviceDID, @"did:plc:testservice");
    XCTAssertTrue(config.includeHighQuality);

    unsetenv("TESTCFG_PORT");
    unsetenv("TESTCFG_PDS_URL");
    unsetenv("TESTCFG_MAX_CONCURRENT_JOBS");
    unsetenv("TESTCFG_MAX_UPLOAD_BYTES");
    unsetenv("TESTCFG_MAX_DURATION");
    unsetenv("TESTCFG_POLL_INTERVAL");
    unsetenv("TESTCFG_DID");
    unsetenv("TESTCFG_HIGH_QUALITY");
}

- (void)testConfigFromEnvironment_NilPrefix_DoesNotCrash
{
    XCTAssertNoThrow([ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:nil],
                     @"Nil prefix should not crash");
}

- (void)testConfigFromEnvironment_NilPrefix_ReturnsConfig
{
    ATProtoMediaServiceConfiguration *config =
        [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:nil];
    XCTAssertNotNil(config, @"Should return a config even with nil prefix");
}

- (void)testConfigFromEnvironment_EmptyPrefix_DoesNotCrash
{
    XCTAssertNoThrow([ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@""],
                     @"Empty prefix should not crash");
}

- (void)testConfigFromEnvironment_EmptyPrefix_ReturnsConfig
{
    ATProtoMediaServiceConfiguration *config =
        [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@""];
    XCTAssertNotNil(config);
}

- (void)testConfigFromEnvironment_NonExistentPrefix_UsesDefaults
{
    ATProtoMediaServiceConfiguration *config =
        [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"NONEXISTENT"];
    XCTAssertNotNil(config);
    XCTAssertEqual(config.port, 2586);
    XCTAssertEqualObjects(config.pdsURL, @"http://localhost:2583");
    XCTAssertEqual(config.maxConcurrentJobs, 2);
    XCTAssertEqual(config.pollInterval, 5.0);
    XCTAssertEqual(config.maxUploadBytes, (NSUInteger)(100 * 1024 * 1024));
    XCTAssertEqual(config.maxDurationSeconds, 180);
    XCTAssertEqualObjects(config.dataDirectory, @"./data/media");
    XCTAssertEqualObjects(config.blobDirectory, @"./data/media/blobs");
}

- (void)testConfigFromEnvironment_PartialEnvVar_ReturnsDefaultsForMissing
{
    setenv("PARTIAL_CFG_PORT", "3000", 1);

    ATProtoMediaServiceConfiguration *config =
        [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"PARTIAL_CFG"];
    XCTAssertEqual(config.port, 3000);
    XCTAssertEqualObjects(config.pdsURL, @"http://localhost:2583");

    unsetenv("PARTIAL_CFG_PORT");
}

- (void)testConfigFromEnvironment_S3Settings
{
    setenv("S3CFG_S3_BUCKET", "my-media-bucket", 1);
    setenv("S3CFG_S3_REGION", "us-west-2", 1);
    setenv("S3CFG_S3_ENDPOINT", "https://s3.custom.com", 1);
    setenv("S3CFG_S3_ACCESS_KEY", "AKID123", 1);
    setenv("S3CFG_S3_SECRET_KEY", "secret456", 1);

    ATProtoMediaServiceConfiguration *config =
        [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"S3CFG"];
    XCTAssertEqualObjects(config.s3Bucket, @"my-media-bucket");
    XCTAssertEqualObjects(config.s3Region, @"us-west-2");
    XCTAssertEqualObjects(config.s3Endpoint, @"https://s3.custom.com");
    XCTAssertEqualObjects(config.s3AccessKey, @"AKID123");
    XCTAssertEqualObjects(config.s3SecretKey, @"secret456");
    XCTAssertEqual(config.port, 2586);

    unsetenv("S3CFG_S3_BUCKET");
    unsetenv("S3CFG_S3_REGION");
    unsetenv("S3CFG_S3_ENDPOINT");
    unsetenv("S3CFG_S3_ACCESS_KEY");
    unsetenv("S3CFG_S3_SECRET_KEY");
}

- (void)testConfigFromEnvironment_NullableFields_DefaultsToDefaultValues
{
    ATProtoMediaServiceConfiguration *config =
        [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"NONEXISTENT"];
    XCTAssertEqualObjects(config.plcURL, @"http://localhost:2582");
    XCTAssertEqualObjects(config.dataDirectory, @"./data/media");
    XCTAssertEqualObjects(config.blobDirectory, @"./data/media/blobs");
    XCTAssertEqualObjects(config.s3Region, @"us-east-1");
    // Actually nullable fields
    XCTAssertNil(config.outputDirectory);
    XCTAssertNil(config.outputBaseUrl);
    XCTAssertNil(config.s3Bucket);
    XCTAssertNil(config.s3Endpoint);
    XCTAssertNil(config.s3AccessKey);
    XCTAssertNil(config.s3SecretKey);
}

- (void)testConfigFromEnvironment_DataAndBlobDirectories
{
    setenv("DIRCFG_DATA_DIR", "/var/data", 1);
    setenv("DIRCFG_BLOB_DIR", "/var/blobs", 1);

    ATProtoMediaServiceConfiguration *config =
        [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"DIRCFG"];
    XCTAssertEqualObjects(config.dataDirectory, @"/var/data");
    XCTAssertEqualObjects(config.blobDirectory, @"/var/blobs");

    unsetenv("DIRCFG_DATA_DIR");
    unsetenv("DIRCFG_BLOB_DIR");
}

- (void)testConfigFromEnvironment_ServiceDIDViaEnv
{
    setenv("DIDCFG_DID", "did:plc:envdid", 1);

    ATProtoMediaServiceConfiguration *config =
        [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"DIDCFG"];
    XCTAssertEqualObjects(config.serviceDID, @"did:plc:envdid");

    unsetenv("DIDCFG_DID");
}

- (void)testConfigFromEnvironment_MaxOutputBytes
{
    setenv("OUTCFG_MAX_OUTPUT_BYTES", "1048576", 1);

    ATProtoMediaServiceConfiguration *config =
        [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"OUTCFG"];
    XCTAssertEqual(config.maxOutputBytes, (NSUInteger)1048576);

    unsetenv("OUTCFG_MAX_OUTPUT_BYTES");
}

@end
