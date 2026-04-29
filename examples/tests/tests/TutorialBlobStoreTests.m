#import <XCTest/XCTest.h>
#import "TutorialBlobStore.h"

@interface TutorialBlobStoreTests : XCTestCase
@property (nonatomic, strong) NSString *dataDir;
@property (nonatomic, strong) TutorialBlobStore *store;
@end

@implementation TutorialBlobStoreTests

- (void)setUp {
    [super setUp];
    self.dataDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"blob_test_%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.dataDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.store = [[TutorialBlobStore alloc] initWithDataDirectory:self.dataDir];
    self.store.maxBlobSize = 1024;  // Small limit for testing
}

- (void)tearDown {
    self.store = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.dataDir error:nil];
    [super tearDown];
}

- (void)testUploadBlob {
    NSError *error = nil;
    NSData *data = [@"Hello blob storage" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid = [self.store putBlob:data forDID:@"did:web:localhost:~alice" mimeType:@"text/plain" error:&error];
    XCTAssertNotNil(cid, @"Should upload blob successfully");
    XCTAssertNil(error);
    XCTAssertTrue([cid hasPrefix:@"bafyrei"], @"CID should start with bafyrei");
}

- (void)testRetrieveBlob {
    NSError *error = nil;
    NSData *original = [@"Test content for retrieval" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid = [self.store putBlob:original forDID:@"did:web:localhost:~alice" mimeType:@"text/plain" error:nil];

    NSString *mimeType = nil;
    NSUInteger size = 0;
    NSData *retrieved = [self.store getBlob:cid forDID:@"did:web:localhost:~alice"
                                outMimeType:&mimeType outSize:&size error:&error];
    XCTAssertNotNil(retrieved, @"Should retrieve blob");
    XCTAssertEqualObjects(retrieved, original, @"Retrieved data should match original");
    XCTAssertEqualObjects(mimeType, @"text/plain", @"MIME type should match");
    XCTAssertEqual(size, original.length, @"Size should match");
}

- (void)testContentAddressedDeduplication {
    NSData *data = [@"Same content" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid1 = [self.store putBlob:data forDID:@"did:web:localhost:~alice" mimeType:@"text/plain" error:nil];
    NSString *cid2 = [self.store putBlob:data forDID:@"did:web:localhost:~bob" mimeType:@"text/plain" error:nil];
    XCTAssertEqualObjects(cid1, cid2, @"Same content should produce same CID (content-addressed)");
}

- (void)testRangeRequest {
    NSData *original = [@"Hello, World! This is a test." dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid = [self.store putBlob:original forDID:@"did:web:localhost:~alice" mimeType:@"text/plain" error:nil];

    NSString *mimeType = nil;
    NSUInteger size = 0;
    NSData *partial = [self.store getBlob:cid forDID:@"did:web:localhost:~alice"
                                     range:NSMakeRange(0, 5)
                                outMimeType:&mimeType outSize:&size error:nil];
    XCTAssertNotNil(partial);
    XCTAssertEqual(partial.length, 5, @"Should return 5 bytes");
    NSString *partialStr = [[NSString alloc] initWithData:partial encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(partialStr, @"Hello", @"Should return first 5 bytes");
}

- (void)testOversizedBlobRejected {
    NSError *error = nil;
    NSMutableData *bigData = [NSMutableData dataWithLength:2048]; // Exceeds 1024 limit
    NSString *cid = [self.store putBlob:bigData forDID:@"did:web:localhost:~alice" mimeType:@"application/octet-stream" error:&error];
    XCTAssertNil(cid, @"Should reject oversized blob");
    XCTAssertNotNil(error, @"Should return error for oversized blob");
}

- (void)testListBlobs {
    [self.store putBlob:[@"blob1" dataUsingEncoding:NSUTF8StringEncoding] forDID:@"did:web:localhost:~alice" mimeType:@"text/plain" error:nil];
    [self.store putBlob:[@"blob2" dataUsingEncoding:NSUTF8StringEncoding] forDID:@"did:web:localhost:~alice" mimeType:@"text/plain" error:nil];
    [self.store putBlob:[@"blob3" dataUsingEncoding:NSUTF8StringEncoding] forDID:@"did:web:localhost:~bob" mimeType:@"text/plain" error:nil];

    NSError *error = nil;
    NSArray *aliceBlobs = [self.store listBlobsForDID:@"did:web:localhost:~alice" limit:50 cursor:nil error:&error];
    XCTAssertNotNil(aliceBlobs);
    XCTAssertEqual(aliceBlobs.count, 2, @"Alice should have 2 blobs");

    NSArray *bobBlobs = [self.store listBlobsForDID:@"did:web:localhost:~bob" limit:50 cursor:nil error:nil];
    XCTAssertEqual(bobBlobs.count, 1, @"Bob should have 1 blob");
}

- (void)testDeleteBlob {
    NSData *data = [@"to be deleted" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid = [self.store putBlob:data forDID:@"did:web:localhost:~alice" mimeType:@"text/plain" error:nil];

    BOOL deleted = [self.store deleteBlob:cid forDID:@"did:web:localhost:~alice" error:nil];
    XCTAssertTrue(deleted, @"Delete should succeed");

    NSData *retrieved = [self.store getBlob:cid forDID:@"did:web:localhost:~alice"
                                outMimeType:nil outSize:nil error:nil];
    XCTAssertNil(retrieved, @"Blob should be gone after deletion");
}

- (void)testCrossDIDIsolation {
    NSData *data = [@"private data" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid = [self.store putBlob:data forDID:@"did:web:localhost:~alice" mimeType:@"text/plain" error:nil];

    // Bob should not be able to access Alice's blob
    NSData *retrieved = [self.store getBlob:cid forDID:@"did:web:localhost:~bob"
                                outMimeType:nil outSize:nil error:nil];
    XCTAssertNil(retrieved, @"Cross-DID access should be denied");
}

@end
