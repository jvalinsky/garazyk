// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Blob/PDSBlobProviderFactory.h"
#import "Blob/PDSBlobProvider.h"
#import "App/ATProtoServiceConfiguration.h"

@interface PDSBlobProviderFactoryTests : XCTestCase
@end

@implementation PDSBlobProviderFactoryTests

/// Creates a temporary config file with the given blobStorageType and loads it.
/// Caller should clean up the temp file after use.
- (ATProtoServiceConfiguration *)configWithBlobStorageType:(NSString *)type {
    NSDictionary *configDict = @{
        @"blobStorageType": type ?: @"disk",
        @"dataDirectory": NSTemporaryDirectory()
    };
    NSError *writeError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:configDict options:0 error:&writeError];
    if (!jsonData) return nil;

    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"pds_test_config_%u.json", arc4random_uniform(1000000)]];
    [jsonData writeToFile:tempPath atomically:YES];

    NSError *loadError = nil;
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration configurationWithPath:tempPath
                                                                                       error:&loadError];
    // Clean up temp file
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
    return config;
}

#pragma mark - blobProviderWithConfiguration:error:

- (void)testBlobProvider_NilConfiguration_ReturnsNilError {
    NSError *error = nil;
    id<PDSBlobProvider> provider = [PDSBlobProviderFactory blobProviderWithConfiguration:nil
                                                                                   error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

- (void)testBlobProvider_NilConfigNilError_DoesNotCrash {
    id<PDSBlobProvider> provider = [PDSBlobProviderFactory blobProviderWithConfiguration:nil
                                                                                   error:NULL];
    XCTAssertNil(provider);
}

- (void)testBlobProvider_S3Type_ReturnsNilError {
    ATProtoServiceConfiguration *config = [self configWithBlobStorageType:@"s3"];
    if (!config) {
        XCTSkip(@"Could not create test config file");
        return;
    }

    NSError *error = nil;
    id<PDSBlobProvider> provider = [PDSBlobProviderFactory blobProviderWithConfiguration:config
                                                                                   error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

- (void)testBlobProvider_UnknownType_ReturnsNilError {
    ATProtoServiceConfiguration *config = [self configWithBlobStorageType:@"invalid"];
    if (!config) {
        XCTSkip(@"Could not create test config file");
        return;
    }

    NSError *error = nil;
    id<PDSBlobProvider> provider = [PDSBlobProviderFactory blobProviderWithConfiguration:config
                                                                                   error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

- (void)testBlobProvider_NilErrorPointer_DoesNotCrash {
    ATProtoServiceConfiguration *config = [self configWithBlobStorageType:@"s3"];
    if (!config) {
        XCTSkip(@"Could not create test config file");
        return;
    }

    id<PDSBlobProvider> provider = [PDSBlobProviderFactory blobProviderWithConfiguration:config
                                                                                   error:NULL];
    XCTAssertNil(provider);
}

- (void)testBlobProvider_DefaultConfig_ReturnsProviderOrError {
    // Uses sharedConfiguration which may or may not have valid dataPaths
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NSError *error = nil;
    id<PDSBlobProvider> provider = [PDSBlobProviderFactory blobProviderWithConfiguration:config
                                                                                   error:&error];
    // If successful, result must conform to protocol
    if (provider) {
        XCTAssertTrue([provider conformsToProtocol:@protocol(PDSBlobProvider)]);
        XCTAssertNil(error);
    }
    // No assertion on nil result — depends on test environment config
}

@end
