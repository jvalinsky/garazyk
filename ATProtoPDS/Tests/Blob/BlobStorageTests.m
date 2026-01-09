#import <XCTest/XCTest.h>
#import "Blob/BlobStorage.h"
#import "Database/PDSDatabase.h"
#import "Database/Schema.h"
#import "Core/CID.h"

@interface BlobStorageTests : XCTestCase

@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) BlobStorage *blobStorage;
@property (nonatomic, strong) NSURL *testDBURL;
@property (nonatomic, strong) NSURL *testStorageURL;
@property (nonatomic, strong) NSData *testData;
@property (nonatomic, strong) CID *uploadedCID;
@property (nonatomic, copy) NSString *testDID;

@end

@implementation BlobStorageTests

- (void)setUp {
    [super setUp];

    self.testDBURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"test_blob_storage.db"]];
    self.testStorageURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"test_blob_storage"]];

    [[NSFileManager defaultManager] removeItemAtURL:self.testDBURL error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:self.testStorageURL error:nil];

    NSError *error = nil;
    self.database = [PDSDatabase databaseAtURL:self.testDBURL];
    XCTAssertTrue([self.database openWithError:&error], @"Failed to open test database: %@", error);

    self.blobStorage = [[BlobStorage alloc] initWithDatabase:self.database storageDirectory:self.testStorageURL];

    NSString *testString = @"Hello, World! This is test blob data.";
    self.testData = [testString dataUsingEncoding:NSUTF8StringEncoding];
    self.testDID = @"did:web:test.example.com";
}

- (void)tearDown {
    [self.database close];
    [[NSFileManager defaultManager] removeItemAtURL:self.testDBURL error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:self.testStorageURL error:nil];
    [super tearDown];
}

- (void)testBlobStorageInitialization {
    XCTAssertNotNil(self.blobStorage, @"BlobStorage should be initialized");
    XCTAssertEqualObjects(self.blobStorage.storageDirectory, self.testStorageURL, @"Storage directory should match");
    XCTAssertEqual(self.blobStorage.database, self.database, @"Database should be set");
}

- (void)testDataSetup {
    XCTAssertNotNil(self.testData, @"Test data should be created");
    XCTAssertGreaterThan(self.testData.length, 0, @"Test data should have content");
}

- (void)testBlobValidationValidImage {
    NSError *error = nil;
    NSData *validImageData = [@"fake-image-data" dataUsingEncoding:NSUTF8StringEncoding];
    BOOL isValid = [self.blobStorage validateBlob:validImageData mimeType:@"image/jpeg" error:&error];

    XCTAssertTrue(isValid, @"Valid image should pass validation");
    XCTAssertNil(error, @"No error should occur for valid blob");
}

- (void)testBlobValidationInvalidMimeType {
    NSError *error = nil;
    NSData *validImageData = [@"fake-image-data" dataUsingEncoding:NSUTF8StringEncoding];
    BOOL isInvalid = ![self.blobStorage validateBlob:validImageData mimeType:@"invalid/type" error:&error];

    XCTAssertTrue(isInvalid, @"Invalid MIME type should fail validation");
    XCTAssertNotNil(error, @"Error should be set for invalid MIME type");
}

- (void)testBlobValidationTooLarge {
    NSError *error = nil;
    NSMutableData *largeData = [NSMutableData dataWithLength:6 * 1024 * 1024];
    BOOL isTooLarge = ![self.blobStorage validateBlob:largeData mimeType:@"image/jpeg" error:&error];

    XCTAssertTrue(isTooLarge, @"Blob exceeding size limit should fail validation");
    XCTAssertNotNil(error, @"Error should be set for oversized blob");
}

- (void)testBlobUpload {
    NSError *error = nil;
    self.uploadedCID = [self.blobStorage uploadBlob:self.testData mimeType:@"text/plain" did:self.testDID error:&error];

    XCTAssertNotNil(self.uploadedCID, @"Uploaded CID should not be nil");
    XCTAssertNotNil(self.uploadedCID.stringValue, @"CID string value should not be nil");
    XCTAssertNil(error, @"No error should occur during upload");
}

- (void)testBlobUploadDuplicate {
    XCTAssertNotNil(self.uploadedCID, @"Upload should succeed first");

    NSError *error = nil;
    CID *duplicateCID = [self.blobStorage uploadBlob:self.testData mimeType:@"text/plain" did:self.testDID error:&error];

    XCTAssertNotNil(duplicateCID, @"Duplicate CID should not be nil");
    XCTAssertEqualObjects(duplicateCID.stringValue, self.uploadedCID.stringValue, @"Duplicate should return same CID");
}

- (void)testBlobRetrieval {
    XCTAssertNotNil(self.uploadedCID, @"Upload should succeed first");

    NSError *error = nil;
    NSData *retrievedData = [self.blobStorage getBlobWithCID:self.uploadedCID error:&error];

    XCTAssertNotNil(retrievedData, @"Retrieved data should not be nil");
    XCTAssertEqualObjects(retrievedData, self.testData, @"Retrieved data should match original");
    XCTAssertNil(error, @"No error should occur during retrieval");
}

- (void)testBlobRetrievalNotFound {
    CID *wrongCID = [CID cidWithMultihash:[NSData dataWithBytes:(uint8_t[]){0x12, 0x20, 0x00, 0x01, 0x02} length:5] codec:0x70];
    XCTAssertNotNil(wrongCID, @"CID creation should succeed");

    NSError *error = nil;
    NSData *wrongData = [self.blobStorage getBlobWithCID:wrongCID error:&error];

    XCTAssertNil(wrongData, @"Non-existent blob should return nil data");
}

- (void)testBlobListing {
    XCTAssertNotNil(self.uploadedCID, @"Upload should succeed first");

    NSError *error = nil;
    NSArray *blobList = [self.blobStorage listBlobsForDID:self.testDID limit:10 cursor:nil error:&error];

    XCTAssertNotNil(blobList, @"Blob list should not be nil");
    XCTAssertEqual(blobList.count, 1, @"Should have exactly 1 blob listed");

    NSDictionary *blobInfo = blobList.firstObject;
    XCTAssertEqualObjects(blobInfo[@"cid"], self.uploadedCID.stringValue, @"CID should match");
    XCTAssertEqualObjects(blobInfo[@"mimeType"], @"text/plain", @"MIME type should match");
    XCTAssertEqualObjects(blobInfo[@"size"], @(self.testData.length), @"Size should match");
}

- (void)testBlobListingEmptyDID {
    NSError *error = nil;
    NSArray *emptyList = [self.blobStorage listBlobsForDID:@"did:web:nonexistent.com" limit:10 cursor:nil error:&error];

    XCTAssertNotNil(emptyList, @"Empty list should not be nil");
    XCTAssertEqual(emptyList.count, 0, @"Non-existent DID should have no blobs");
}

- (void)testBlobDeletion {
    XCTAssertNotNil(self.uploadedCID, @"Upload should succeed first");

    NSError *error = nil;
    BOOL deleted = [self.blobStorage deleteBlobWithCID:self.uploadedCID did:self.testDID error:&error];

    XCTAssertTrue(deleted, @"Blob deletion should succeed");
    XCTAssertNil(error, @"No error should occur during deletion");
}

- (void)testBlobDeletionVerification {
    NSError *error = nil;
    NSData *deletedData = [self.blobStorage getBlobWithCID:self.uploadedCID error:&error];

    XCTAssertNil(deletedData, @"Deleted blob should return nil");
}

- (void)testBlobDeletionListingVerification {
    NSError *error = nil;
    NSArray *afterDeleteList = [self.blobStorage listBlobsForDID:self.testDID limit:10 cursor:nil error:&error];

    XCTAssertNotNil(afterDeleteList, @"List should not be nil");
    XCTAssertEqual(afterDeleteList.count, 0, @"After deletion, list should be empty");
}

- (void)testBlobUploadDifferentDID {
    NSError *error = nil;
    NSString *otherDID = @"did:web:other.example.com";
    CID *otherCID = [self.blobStorage uploadBlob:self.testData mimeType:@"text/plain" did:otherDID error:&error];

    XCTAssertNotNil(otherCID, @"Upload with different DID should succeed");
}

- (void)testBlobDIDIsolation {
    NSString *otherDID = @"did:web:other.example.com";

    NSError *error = nil;
    NSArray *testDIDList = [self.blobStorage listBlobsForDID:self.testDID limit:10 cursor:nil error:&error];
    NSArray *otherDIDList = [self.blobStorage listBlobsForDID:otherDID limit:10 cursor:nil error:&error];

    XCTAssertEqual(testDIDList.count, 0, @"Original DID should have no blobs after deletion");
    XCTAssertEqual(otherDIDList.count, 1, @"Other DID should have 1 blob");
}

@end
