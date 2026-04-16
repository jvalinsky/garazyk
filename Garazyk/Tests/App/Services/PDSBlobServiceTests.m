#import <XCTest/XCTest.h>
#import "Services/PDS/PDSBlobService.h"
#import "Blob/BlobStorage.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Schema.h"
#import "Core/CID.h"

@interface PDSBlobServiceTests : XCTestCase
@property (nonatomic, strong) NSURL *testDBURL;
@property (nonatomic, strong) NSURL *testStorageURL;
@property (nonatomic, strong) PDSDatabasePool *databasePool;
@property (nonatomic, strong) BlobStorage *blobStorage;
@property (nonatomic, strong) PDSBlobService *blobService;
@property (nonatomic, strong) NSData *testData;
@property (nonatomic, copy) NSString *testDID;
@end

@implementation PDSBlobServiceTests

- (void)setUp {
    [super setUp];
    
    self.testDBURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"pds_blob_service_test"]];
    self.testStorageURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"pds_blob_service_storage"]];
    
    [[NSFileManager defaultManager] removeItemAtURL:self.testDBURL error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:self.testStorageURL error:nil];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.testDBURL withIntermediateDirectories:YES attributes:nil error:nil];
    
    self.databasePool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDBURL.path maxSize:5];
    
    PDSDiskBlobProvider *provider = [[PDSDiskBlobProvider alloc] initWithStorageDirectory:self.testStorageURL];
    self.blobStorage = [[BlobStorage alloc] initWithDatabasePool:self.databasePool provider:provider];
    
    self.blobService = [[PDSBlobService alloc] initWithDatabasePool:self.databasePool storage:self.blobStorage];
    
    NSString *testString = @"Hello, Blob Service World!";
    self.testData = [testString dataUsingEncoding:NSUTF8StringEncoding];
    self.testDID = @"did:web:test.blob-service.example.com";
}

- (void)tearDown {
    [self.databasePool closeAll];
    [[NSFileManager defaultManager] removeItemAtURL:self.testDBURL error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:self.testStorageURL error:nil];
    [super tearDown];
}

- (void)testServiceInitialization {
    XCTAssertNotNil(self.blobService);
    XCTAssertEqual(self.blobService.databasePool, self.databasePool);
    XCTAssertEqual(self.blobService.blobStorage, self.blobStorage);
}

- (void)testUploadBlob {
    NSError *error = nil;
    NSDictionary *result = [self.blobService uploadBlob:self.testData
                                                forDid:self.testDID
                                               mimeType:@"text/plain"
                                                 error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertNotNil(result[@"blob"]);
    
    NSDictionary *blob = result[@"blob"];
    XCTAssertEqualObjects(blob[@"$type"], @"blob");
    XCTAssertNotNil(blob[@"ref"][@"$link"]);
    XCTAssertEqualObjects(blob[@"mimeType"], @"text/plain");
    XCTAssertEqualObjects(blob[@"size"], @(self.testData.length));
}

- (void)testUploadBlobWithDifferentMimeTypes {
    NSError *error = nil;
    NSArray *mimeTypes = @[@"image/png", @"image/jpeg", @"video/mp4", @"application/octet-stream"];
    
    for (NSString *mimeType in mimeTypes) {
        NSData *data = [@"test data" dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *result = [self.blobService uploadBlob:data
                                                    forDid:self.testDID
                                                   mimeType:mimeType
                                                     error:&error];
        XCTAssertNotNil(result);
        XCTAssertEqualObjects(result[@"blob"][@"mimeType"], mimeType);
    }
}

- (void)testGetBlobWithCID {
    NSError *error = nil;
    NSDictionary *uploadResult = [self.blobService uploadBlob:self.testData
                                                      forDid:self.testDID
                                                     mimeType:@"text/plain"
                                                       error:&error];
    XCTAssertNotNil(uploadResult);
    
    NSString *cidString = uploadResult[@"blob"][@"ref"][@"$link"];
    XCTAssertNotNil(cidString);
    
    NSDictionary *getResult = [self.blobService getBlobWithCID:cidString
                                                         did:self.testDID
                                                      error:&error];
    XCTAssertNotNil(getResult);
    XCTAssertNil(error);
    
    NSData *retrievedData = getResult[@"blob"];
    XCTAssertNotNil(retrievedData);
    XCTAssertEqualObjects(retrievedData, self.testData);
    XCTAssertEqualObjects(getResult[@"mimeType"], @"text/plain");
}

- (void)testGetBlobInvalidCID {
    NSError *error = nil;
    NSDictionary *result = [self.blobService getBlobWithCID:@"invalid-cid"
                                                      did:self.testDID
                                                   error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testGetBlobNotFound {
    NSError *error = nil;
    NSString *fakeCid = @"bafkreinexistentcid12345678901234567890123456789012345678";
    NSDictionary *result = [self.blobService getBlobWithCID:fakeCid
                                                      did:self.testDID
                                                   error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);

}

- (void)testGetBlobWrongDID {
    NSError *error = nil;
    NSDictionary *uploadResult = [self.blobService uploadBlob:self.testData
                                                      forDid:self.testDID
                                                     mimeType:@"text/plain"
                                                       error:&error];
    NSString *cidString = uploadResult[@"blob"][@"ref"][@"$link"];
    
    NSDictionary *getResult = [self.blobService getBlobWithCID:cidString
                                                         did:@"did:web:wrong.example.com"
                                                      error:&error];
    XCTAssertNil(getResult);
}

- (void)testListBlobsForDID {
    NSError *error = nil;
    [self.blobService uploadBlob:self.testData forDid:self.testDID mimeType:@"text/plain" error:&error];
    
    NSArray *blobs = [self.blobService listBlobsForDID:self.testDID limit:10 cursor:nil error:&error];
    
    XCTAssertNotNil(blobs);
    XCTAssertEqual(blobs.count, 1);
    
    NSDictionary *blobInfo = blobs.firstObject;
    XCTAssertNotNil(blobInfo[@"cid"]);
    XCTAssertEqualObjects(blobInfo[@"mimeType"], @"text/plain");
}

- (void)testListBlobsEmptyDID {
    NSError *error = nil;
    NSArray *blobs = [self.blobService listBlobsForDID:@"did:web:nonexistent.com" limit:10 cursor:nil error:&error];
    
    XCTAssertNotNil(blobs);
    XCTAssertEqual(blobs.count, 0);
}

- (void)testListBlobsWithLimit {
    NSError *error = nil;
    for (int i = 0; i < 5; i++) {
        NSData *data = [[NSString stringWithFormat:@"blob %d", i] dataUsingEncoding:NSUTF8StringEncoding];
        [self.blobService uploadBlob:data forDid:self.testDID mimeType:@"text/plain" error:&error];
    }
    
    NSArray *allBlobs = [self.blobService listBlobsForDID:self.testDID limit:10 cursor:nil error:&error];
    XCTAssertEqual(allBlobs.count, 5);
    
    NSArray *limitedBlobs = [self.blobService listBlobsForDID:self.testDID limit:2 cursor:nil error:&error];
    XCTAssertEqual(limitedBlobs.count, 2);
}

- (void)testDeleteBlobSucceeds {
    NSError *error = nil;
    NSDictionary *uploadResult = [self.blobService uploadBlob:self.testData
                                                      forDid:self.testDID
                                                     mimeType:@"text/plain"
                                                       error:&error];
    NSString *cidString = uploadResult[@"blob"][@"ref"][@"$link"];
    
    BOOL deleted = [self.blobService deleteBlobWithCID:cidString did:self.testDID error:&error];
    XCTAssertTrue(deleted);
    XCTAssertNil(error);
}

- (void)testDeleteBlobInvalidCID {
    NSError *error = nil;
    BOOL deleted = [self.blobService deleteBlobWithCID:@"invalid" did:self.testDID error:&error];
    XCTAssertFalse(deleted);
    XCTAssertNotNil(error);
}

- (void)testDeleteBlobNotFound {
    NSError *error = nil;
    NSString *fakeCid = @"bafkreinexistentcid12345678901234567890123456789012345678";
    BOOL deleted = [self.blobService deleteBlobWithCID:fakeCid did:self.testDID error:&error];
    XCTAssertFalse(deleted);
}

- (void)testDeleteBlobVerifiesDataRemoved {
    NSError *error = nil;
    NSDictionary *uploadResult = [self.blobService uploadBlob:self.testData
                                                      forDid:self.testDID
                                                     mimeType:@"text/plain"
                                                       error:&error];
    XCTAssertNotNil(uploadResult);
    NSString *cidString = uploadResult[@"blob"][@"ref"][@"$link"];
    XCTAssertNotNil(cidString);
    
    [self.blobService deleteBlobWithCID:cidString did:self.testDID error:&error];
    XCTAssertNil(error);
    
    NSDictionary *getResult = [self.blobService getBlobWithCID:cidString
                                                         did:self.testDID
                                                      error:&error];
    XCTAssertNil(getResult);
}

- (void)testMultipleBlobsSameDIDReturnsAllBlobs {
    NSError *error = nil;
    NSMutableArray *cidStrings = [NSMutableArray array];
    
    for (int i = 0; i < 3; i++) {
        NSData *data = [[NSString stringWithFormat:@"data %d", i] dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *result = [self.blobService uploadBlob:data forDid:self.testDID mimeType:@"text/plain" error:&error];
        [cidStrings addObject:result[@"blob"][@"ref"][@"$link"]];
    }
    
    NSArray *blobs = [self.blobService listBlobsForDID:self.testDID limit:10 cursor:nil error:&error];
    XCTAssertEqual(blobs.count, 3);
    
    for (NSString *cid in cidStrings) {
        BOOL found = NO;
        for (NSDictionary *blob in blobs) {
            if ([blob[@"cid"] isEqualToString:cid]) {
                found = YES;
                break;
            }
        }
        XCTAssertTrue(found, @"CID %@ should be in list", cid);
    }
}

- (void)testBlobServiceIsolationBetweenDIDs {
    NSError *error = nil;
    NSString *did1 = @"did:web:user1.example.com";
    NSString *did2 = @"did:web:user2.example.com";
    
    NSData *data1 = [@"data for user 1" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *data2 = [@"data for user 2" dataUsingEncoding:NSUTF8StringEncoding];
    
    [self.blobService uploadBlob:data1 forDid:did1 mimeType:@"text/plain" error:&error];
    [self.blobService uploadBlob:data2 forDid:did2 mimeType:@"text/plain" error:&error];
    
    NSArray *did1Blobs = [self.blobService listBlobsForDID:did1 limit:10 cursor:nil error:&error];
    NSArray *did2Blobs = [self.blobService listBlobsForDID:did2 limit:10 cursor:nil error:&error];
    
    XCTAssertEqual(did1Blobs.count, 1);
    XCTAssertEqual(did2Blobs.count, 1);
    XCTAssertNotEqualObjects(did1Blobs.firstObject[@"cid"], did2Blobs.firstObject[@"cid"]);
}

- (void)testUploadLargeBlob {
    NSMutableData *largeData = [NSMutableData dataWithLength:1024 * 500];
    arc4random_buf(largeData.mutableBytes, largeData.length);
    
    NSError *error = nil;
    NSDictionary *result = [self.blobService uploadBlob:largeData
                                                forDid:self.testDID
                                               mimeType:@"application/octet-stream"
                                                 error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertNotNil(result[@"blob"]);
    XCTAssertEqual([result[@"blob"][@"size"] integerValue], 1024 * 500);
}

@end
