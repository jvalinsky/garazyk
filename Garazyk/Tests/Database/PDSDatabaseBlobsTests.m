// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"

@interface PDSDatabaseBlobsTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSDatabaseBlobsTests

- (void)setUp {
    [super setUp];
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"blobs_test_%@", [[NSUUID UUID] UUIDString]]]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempDirURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    NSURL *dbURL = [self.tempDirURL URLByAppendingPathComponent:@"test.db"];
    self.database = [PDSDatabase databaseAtURL:dbURL];
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Failed to open database: %@", error);
    XCTAssertNil(error);
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempDirURL error:nil];
    [super tearDown];
}

#pragma mark - Helper

- (PDSDatabaseBlob *)testBlobWithCid:(NSData *)cid did:(NSString *)did {
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    blob.cid = cid;
    blob.did = did;
    blob.mimeType = @"image/png";
    blob.size = 4096;
    blob.createdAt = [NSDate date];
    return blob;
}

#pragma mark - Create

- (void)testSaveBlob {
    NSData *cid = [@"bafyreiblobcid1" dataUsingEncoding:NSUTF8StringEncoding];
    PDSDatabaseBlob *blob = [self testBlobWithCid:cid did:@"did:plc:blobowner1"];

    NSError *error = nil;
    BOOL saved = [self.database saveBlob:blob error:&error];
    XCTAssertTrue(saved, @"saveBlob should succeed");
    XCTAssertNil(error);
}

#pragma mark - Read

- (void)testGetBlobWithCid {
    NSData *cid = [@"bafyreigetblobcid1" dataUsingEncoding:NSUTF8StringEncoding];
    PDSDatabaseBlob *blob = [self testBlobWithCid:cid did:@"did:plc:blobowner2"];
    [self.database saveBlob:blob error:nil];

    NSError *error = nil;
    PDSDatabaseBlob *found = [self.database getBlobWithCid:cid error:&error];
    XCTAssertNotNil(found, @"Should find blob by CID");
    XCTAssertNil(error);
    XCTAssertEqualObjects(found.cid, cid);
    XCTAssertEqualObjects(found.did, @"did:plc:blobowner2");
    XCTAssertEqualObjects(found.mimeType, @"image/png");
    XCTAssertEqual(found.size, 4096);
}

- (void)testGetBlobWithCidNotFound {
    NSData *fakeCid = [@"bafyreinonexistentblob" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    PDSDatabaseBlob *found = [self.database getBlobWithCid:fakeCid error:&error];
    XCTAssertNil(found, @"Should return nil for nonexistent blob");
    XCTAssertNil(error);
}

- (void)testGetBlobsForDid {
    NSString *did = @"did:plc:bloblistowner";
    for (int i = 0; i < 3; i++) {
        NSString *cidStr = [NSString stringWithFormat:@"bafyreilistcid%d", i];
        NSData *cid = [cidStr dataUsingEncoding:NSUTF8StringEncoding];
        PDSDatabaseBlob *blob = [self testBlobWithCid:cid did:did];
        [self.database saveBlob:blob error:nil];
    }

    NSError *error = nil;
    NSArray<PDSDatabaseBlob *> *blobs = [self.database getBlobsForDid:did limit:10 offset:0 error:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(blobs.count, 3);
}

- (void)testGetBlobsForDidWithPagination {
    NSString *did = @"did:plc:blobpageowner";
    for (int i = 0; i < 5; i++) {
        NSString *cidStr = [NSString stringWithFormat:@"bafyreipageblob%d", i];
        NSData *cid = [cidStr dataUsingEncoding:NSUTF8StringEncoding];
        PDSDatabaseBlob *blob = [self testBlobWithCid:cid did:did];
        [self.database saveBlob:blob error:nil];
    }

    NSError *error = nil;
    NSArray<PDSDatabaseBlob *> *page1 = [self.database getBlobsForDid:did limit:3 offset:0 error:&error];
    XCTAssertNil(error);
    XCTAssertLessThanOrEqual(page1.count, 3);
    XCTAssertGreaterThanOrEqual(page1.count, 1);

    NSArray<PDSDatabaseBlob *> *page2 = [self.database getBlobsForDid:did limit:3 offset:3 error:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(page2.count, 1);
}

- (void)testGetBlobCountForDid {
    NSString *did = @"did:plc:blobcountowner";
    for (int i = 0; i < 4; i++) {
        NSString *cidStr = [NSString stringWithFormat:@"bafyreicountblob%d", i];
        NSData *cid = [cidStr dataUsingEncoding:NSUTF8StringEncoding];
        PDSDatabaseBlob *blob = [self testBlobWithCid:cid did:did];
        [self.database saveBlob:blob error:nil];
    }

    NSError *error = nil;
    NSInteger count = [self.database getBlobCountForDid:did error:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(count, 4);
}

#pragma mark - Delete

- (void)testDeleteBlob {
    NSData *cid = [@"bafyreideleteblob1" dataUsingEncoding:NSUTF8StringEncoding];
    PDSDatabaseBlob *blob = [self testBlobWithCid:cid did:@"did:plc:blobdeleteowner"];
    [self.database saveBlob:blob error:nil];

    NSError *error = nil;
    BOOL deleted = [self.database deleteBlob:cid error:&error];
    XCTAssertTrue(deleted);
    XCTAssertNil(error);

    PDSDatabaseBlob *found = [self.database getBlobWithCid:cid error:nil];
    XCTAssertNil(found, @"Blob should be gone after deletion");
}

@end
