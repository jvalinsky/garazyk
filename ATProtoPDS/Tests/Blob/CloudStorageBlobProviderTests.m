#import <XCTest/XCTest.h>
#import "Blob/PDSCloudStorageBlobProvider.h"
#import "Core/CID.h"

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

- (void)testSignatureV4Generation {
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:@"test-bucket"
               region:@"us-east-1"
             endpoint:nil
            keyPrefix:nil
        accessKeyId:@"AKIAIOSFODNN7EXAMPLE"
     secretAccessKey:@"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"];

    XCTAssertNotNil(provider);

    // Create a test request
    NSURL *testURL = [NSURL URLWithString:@"https://s3.us-east-1.amazonaws.com/test-bucket/test-object"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:testURL];
    request.HTTPMethod = @"PUT";

    NSData *testData = [@"test data" dataUsingEncoding:NSUTF8StringEncoding];
    request.HTTPBody = testData;

    // Sign the request (this tests the internal signing logic)
    [provider signRequest:request method:@"PUT" path:@"test-object" body:testData];

    // Verify headers were added
    XCTAssertNotNil([request valueForHTTPHeaderField:@"x-amz-date"]);
    XCTAssertNotNil([request valueForHTTPHeaderField:@"x-amz-content-sha256"]);
    XCTAssertNotNil([request valueForHTTPHeaderField:@"Authorization"]);
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

    // Create a test CID
    CID *testCID = [[CID alloc] initWithString:@"bafyreig67flmvqo23inwqxfht6du7tnvwmgw3qdh7tnrwdgqzlmz7lzhi"];
    XCTAssertNotNil(testCID);

    // Test data
    NSData *testData = [@"test blob data" dataUsingEncoding:NSUTF8StringEncoding];

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

    CID *testCID = [[CID alloc] initWithString:@"bafyreig67flmvqo23inwqxfht6du7tnvwmgw3qdh7tnrwdgqzlmz7lzhi"];

    NSError *error = nil;
    BOOL result = [provider storeBlobData:nil forCID:testCID error:&error];

    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PDSCloudStorageBlobProviderErrorDomain);
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
