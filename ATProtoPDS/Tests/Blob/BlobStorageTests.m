#import <XCTest/XCTest.h>
#import "Blob/BlobStorage.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Schema.h"
#import "Core/CID.h"

@interface BlobStorageTests : XCTestCase

@property (nonatomic, strong) PDSDatabasePool *databasePool;
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

    // Use a temp directory for the pool, not a single file
    self.testDBURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"pds_test_db_pool"]];
    self.testStorageURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"test_blob_storage"]];

    [[NSFileManager defaultManager] removeItemAtURL:self.testDBURL error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:self.testStorageURL error:nil];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.testDBURL withIntermediateDirectories:YES attributes:nil error:nil];
    
    // Create pool
    self.databasePool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDBURL.path maxSize:5];
    
    // Create provider
    PDSDiskBlobProvider *provider = [[PDSDiskBlobProvider alloc] initWithStorageDirectory:self.testStorageURL];
    
    self.blobStorage = [[BlobStorage alloc] initWithDatabasePool:self.databasePool provider:provider];

    NSString *testString = @"Hello, World! This is test blob data.";
    self.testData = [testString dataUsingEncoding:NSUTF8StringEncoding];
    self.testDID = @"did:web:test.example.com";
}

- (void)tearDown {
    [self.databasePool closeAll];
    [[NSFileManager defaultManager] removeItemAtURL:self.testDBURL error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:self.testStorageURL error:nil];
    [super tearDown];
}

- (void)testBlobStorageInitialization {
    XCTAssertNotNil(self.blobStorage, @"BlobStorage should be initialized");
    XCTAssertEqual(self.blobStorage.databasePool, self.databasePool, @"Database pool should be set");
    XCTAssertNotNil(self.blobStorage.provider, @"Provider should be set");
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
    NSData *retrievedData = [self.blobStorage getBlobWithCID:self.uploadedCID did:self.testDID error:&error];

    XCTAssertNotNil(retrievedData, @"Retrieved data should not be nil");
    XCTAssertEqualObjects(retrievedData, self.testData, @"Retrieved data should match original");
    XCTAssertNil(error, @"No error should occur during retrieval");
}

- (void)testBlobRetrievalNotFound {
    CID *wrongCID = [CID cidWithMultihash:[NSData dataWithBytes:(uint8_t[]){0x12, 0x20, 0x00, 0x01, 0x02} length:5] codec:0x70];
    XCTAssertNotNil(wrongCID, @"CID creation should succeed");

    NSError *error = nil;
    NSData *wrongData = [self.blobStorage getBlobWithCID:wrongCID did:self.testDID error:&error];

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
    NSData *deletedData = [self.blobStorage getBlobWithCID:self.uploadedCID did:self.testDID error:&error];

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

- (void)testBlobMimeTypeWhitelist {
    NSError *error = nil;
    NSData *data = [@"some-executable-code" dataUsingEncoding:NSUTF8StringEncoding];
    // application/x-msdownload is typically not allowed
    BOOL isValid = [self.blobStorage validateBlob:data mimeType:@"application/x-msdownload" error:&error];

    XCTAssertFalse(isValid, @"Unsupported MIME type should fail validation");
    XCTAssertNotNil(error, @"Error should be set for unsupported MIME type");
    XCTAssertEqual(error.code, BlobStorageErrorInvalidMIMEType, @"Error code should be InvalidMIMEType");
}

- (void)testBlobMagicBytesMismatch {
    NSError *error = nil;
    // "NotATrueJPEG" is definitely not a JPEG
    NSData *data = [@"NotATrueJPEG" dataUsingEncoding:NSUTF8StringEncoding];
    
    // This should fail if magic byte validation is enforced
    // Note: If this fails to be invalid (i.e. returns true), it means implementation is loose.
    // We expect it to be loose currently if the previous test used "fake-image-data" and passed.
    // However, if we want to enforce it, we should update strictness.
    // Let's assume strict validation is desired and see if it fails.
    BOOL isValid = [self.blobStorage validateBlob:data mimeType:@"image/jpeg" error:&error];
    
    // For now, if the implementation is loose, this might pass. 
    // If I want to enforce strictness, I should assert False.
    // Given the task is "Test magic bytes validation", I should expect it to fail (return NO).
    // If it currently passes, I will have to fix MimeTypeValidator.
    XCTAssertFalse(isValid, @"Magic byte mismatch should fail validation");
    XCTAssertNotNil(error, @"Error should be set for magic byte mismatch");
}

- (void)testBlobRefCountingAcrossDIDs {
    NSError *error = nil;
    NSString *did1 = @"did:web:user1";
    NSString *did2 = @"did:web:user2";
    
    // Upload same data for both DIDs
    CID *cid1 = [self.blobStorage uploadBlob:self.testData mimeType:@"text/plain" did:did1 error:&error];
    XCTAssertNotNil(cid1);
    
    CID *cid2 = [self.blobStorage uploadBlob:self.testData mimeType:@"text/plain" did:did2 error:&error];
    XCTAssertNotNil(cid2);
    
    XCTAssertEqualObjects(cid1.stringValue, cid2.stringValue, @"CIDs should match for same data");
    
    // Delete for DID1
    BOOL deleted1 = [self.blobStorage deleteBlobWithCID:cid1 did:did1 error:&error];
    XCTAssertTrue(deleted1);
    
    // Verify DID1 cannot retrieve it
    // Verify DID1 cannot retrieve it?
    // If we use getBlobWithCID:did: error:, checking for DID1 should fail because metadata is gone.
    NSData *data1 = [self.blobStorage getBlobWithCID:cid1 did:did1 error:&error];
    XCTAssertNil(data1, @"DID1 should not be able to retrieve blob after deleting it");
    // Wait, getBlobWithCID:error: in BlobStorage.h doesn't take DID?
    // - (nullable NSData *)getBlobWithCID:(CID *)cid error:(NSError **)error;
    // If it retrieves from global storage, it might still return data if DID2 has it?
    // Implementation likely checks if file exists.
    // If BlobStorage is just a wrapper around file system, getBlobWithCID checks if file exists.
    // If file exists (kept alive by DID2), it should return data.
    // But logically, if DID1 deleted it, should they be able to get it?
    // The method signature doesn't restrict by DID.
    // So:
    // 1. If global storage, data should still exist.
    // 2. If we want to test that DID1 *lost access* conceptually, we'd need a method like `getBlobWithCID:did:`.
    // The current BlobStorage API `getBlobWithCID:error:` implies global access if you know the CID.
    // So the test should verify the DATA is still there (because DID2 has it).
    
    NSData *remainingData = [self.blobStorage getBlobWithCID:cid1 did:did2 error:&error];
    XCTAssertNotNil(remainingData, @"Data should persist because DID2 still references it");
    
    // Delete for DID2
    BOOL deleted2 = [self.blobStorage deleteBlobWithCID:cid2 did:did2 error:&error];
    XCTAssertTrue(deleted2);
    
    // Now data should be gone from disk (if ref counting works)
    NSData *goneData = [self.blobStorage getBlobWithCID:cid1 did:did2 error:&error];
    XCTAssertNil(goneData, @"Data should be removed after last reference is deleted");
}

@end
