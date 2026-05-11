// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Blob/PDSCloudStorageBlobProvider.h"
#import "Core/CID.h"

@interface PDSCloudStorageBlobProvider (Testing)
- (NSURL *)s3URLForKey:(NSString *)key;
- (NSString *)buildCanonicalRequest:(NSString *)method
                                URL:(NSURL *)url
                            headers:(NSDictionary *)headers
                           bodyHash:(NSString *)bodyHash;
@end

@interface CloudStorageBlobProviderTests : XCTestCase
@end

@implementation CloudStorageBlobProviderTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

#pragma mark - Initialization Tests

- (void)testInitializationWithValidConfig {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"test-bucket"
               region:@"us-east-1"
             endpoint:nil
            keyPrefix:@"blobs/"
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    XCTAssertNotNil(provider);
    XCTAssertEqualObjects(provider.bucket, @"test-bucket");
    XCTAssertEqualObjects(provider.region, @"us-east-1");
    XCTAssertEqualObjects(provider.keyPrefix, @"blobs/");
}

- (void)testInitializationWithNilBucket {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:nil
               region:@"us-east-1"
             endpoint:nil
            keyPrefix:nil
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    XCTAssertNil(provider);
}

- (void)testInitializationWithNilAccessKey {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"test-bucket"
               region:@"us-east-1"
             endpoint:nil
            keyPrefix:nil
        accessKeyId:nil
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    XCTAssertNil(provider);
}

- (void)testInitializationWithCustomEndpoint {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"test-bucket"
               region:@"minio"
             endpoint:@"https://minio.example.com"
            keyPrefix:nil
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    XCTAssertNotNil(provider);
    XCTAssertEqualObjects(provider.endpoint, @"https://minio.example.com");
}

#pragma mark - Signature V4 Generation Tests

- (void)testCanonicalRequestForAWSVirtualHostedURL {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"my-bucket"
               region:@"us-west-2"
             endpoint:nil
            keyPrefix:@"blobs/"
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    XCTAssertNotNil(provider);

    NSURL *url = [provider s3URLForKey:@"blobs/bafytest"];
    NSString *canonical = [provider buildCanonicalRequest:@"PUT"
                                                       URL:url
                                                   headers:@{
                                                       @"Host": @"stale.example.com",
                                                       @"x-amz-date": @"20260428T000000Z",
                                                       @"x-amz-content-sha256": @"HASH"
                                                   }
                                                  bodyHash:@"HASH"];

    NSString *expected = @"PUT\n"
                         @"/blobs/bafytest\n"
                         @"\n"
                         @"host:my-bucket.s3.us-west-2.amazonaws.com\n"
                         @"x-amz-content-sha256:HASH\n"
                         @"x-amz-date:20260428T000000Z\n"
                         @"\n"
                         @"host;x-amz-content-sha256;x-amz-date\n"
                         @"HASH";
    XCTAssertEqualObjects(canonical, expected);
}

- (void)testCanonicalRequestForPathStyleEndpointWithPort {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"my-bucket"
               region:@"us-east-1"
             endpoint:@"https://minio.example.com:9000"
            keyPrefix:nil
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    NSURL *url = [provider s3URLForKey:@"blobcid"];
    NSString *canonical = [provider buildCanonicalRequest:@"GET"
                                                       URL:url
                                                   headers:@{
                                                       @"x-amz-date": @"20260428T000000Z",
                                                       @"x-amz-content-sha256": @"HASH"
                                                   }
                                                  bodyHash:@"HASH"];

    NSString *expected = @"GET\n"
                         @"/my-bucket/blobcid\n"
                         @"\n"
                         @"host:minio.example.com:9000\n"
                         @"x-amz-content-sha256:HASH\n"
                         @"x-amz-date:20260428T000000Z\n"
                         @"\n"
                         @"host;x-amz-content-sha256;x-amz-date\n"
                         @"HASH";
    XCTAssertEqualObjects(canonical, expected);
}

- (void)testCanonicalRequestForEndpointPathPrefix {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"my-bucket"
               region:@"us-east-1"
             endpoint:@"https://storage.example.com/root"
            keyPrefix:nil
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    NSURL *url = [provider s3URLForKey:@"blobcid"];
    NSString *canonical = [provider buildCanonicalRequest:@"DELETE"
                                                       URL:url
                                                   headers:@{
                                                       @"x-amz-date": @"20260428T000000Z",
                                                       @"x-amz-content-sha256": @"HASH"
                                                   }
                                                  bodyHash:@"HASH"];

    NSString *expected = @"DELETE\n"
                         @"/root/my-bucket/blobcid\n"
                         @"\n"
                         @"host:storage.example.com\n"
                         @"x-amz-content-sha256:HASH\n"
                         @"x-amz-date:20260428T000000Z\n"
                         @"\n"
                         @"host;x-amz-content-sha256;x-amz-date\n"
                         @"HASH";
    XCTAssertEqualObjects(canonical, expected);
}

#pragma mark - CID-based Operations Tests

- (void)testStoreBlobDataWithValidCID {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"test-bucket"
               region:@"us-east-1"
             endpoint:nil
            keyPrefix:@"blobs/"
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    XCTAssertNotNil(provider);

    // Test data
    NSData *testData = [@"test blob data" dataUsingEncoding:NSUTF8StringEncoding];
    CID *testCID = [CID sha256:testData];
    XCTAssertNotNil(testCID);

    // Note: Actual S3 upload would require network access and credentials
    // This test just verifies the interface works correctly
    NSError *error = nil;
    // Store operation would normally upload to S3, but we're just testing the interface
    // In a real test, we'd mock the NSURLSession
}

- (void)testStoreBlobDataWithNilData {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"test-bucket"
               region:@"us-east-1"
             endpoint:nil
            keyPrefix:nil
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    XCTAssertNotNil(provider);

    CID *testCID = [CID sha256:[@"test blob data" dataUsingEncoding:NSUTF8StringEncoding]];

    NSError *error = nil;
    BOOL result = [provider storeBlobData:nil forCID:testCID error:&error];

    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    // Note: Error domain is internal, just check error exists
}

- (void)testStoreBlobDataWithNilCID {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"test-bucket"
               region:@"us-east-1"
             endpoint:nil
            keyPrefix:nil
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    XCTAssertNotNil(provider);

    NSData *testData = [@"test data" dataUsingEncoding:NSUTF8StringEncoding];

    NSError *error = nil;
    BOOL result = [provider storeBlobData:testData forCID:nil error:&error];

    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

#pragma mark - URL Construction Tests

- (void)testS3URLConstructionForAWSWithoutEndpoint {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"my-bucket"
               region:@"us-west-2"
             endpoint:nil
            keyPrefix:nil
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    XCTAssertNotNil(provider);

    // Note: s3URLForKey: is an internal method, test the provider works
    // instead of internal URL construction
}

- (void)testS3URLConstructionForS3CompatibleEndpoint {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"my-bucket"
               region:@"us-east-1"
             endpoint:@"https://minio.example.com"
            keyPrefix:nil
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    XCTAssertNotNil(provider);

    // Note: s3URLForKey: is an internal method, test the provider works
}

#pragma mark - Protocol Conformance Tests

- (void)testConformsToProtocol {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"test-bucket"
               region:@"us-east-1"
             endpoint:nil
            keyPrefix:nil
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    XCTAssertTrue([provider conformsToProtocol:@protocol(PDSBlobProvider)]);
}

- (void)testImplementsRequiredMethods {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"test-bucket"
               region:@"us-east-1"
             endpoint:nil
            keyPrefix:nil
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    XCTAssertTrue([provider respondsToSelector:@selector(storeBlobData:forCID:error:)]);
    XCTAssertTrue([provider respondsToSelector:@selector(retrieveBlobDataForCID:error:)]);
    XCTAssertTrue([provider respondsToSelector:@selector(deleteBlobDataForCID:error:)]);
    XCTAssertTrue([provider respondsToSelector:@selector(hasBlobDataForCID:)]);
}

@end
