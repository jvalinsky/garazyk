// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"
#import "Database/PDSBlock.h"

@interface PDSDatabaseBlocksTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSDatabaseBlocksTests

- (void)setUp {
    [super setUp];
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"blocks_test_%@", [[NSUUID UUID] UUIDString]]]];
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

- (PDSDatabaseBlock *)testBlockWithCid:(NSData *)cid repoDid:(NSString *)repoDid {
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = cid;
    block.repoDid = repoDid;
    block.blockData = [@"test block data" dataUsingEncoding:NSUTF8StringEncoding];
    block.contentType = @"application/json";
    block.size = (NSInteger)block.blockData.length;
    block.createdAt = [NSDate date];
    return block;
}

#pragma mark - Create

- (void)testSaveBlock {
    NSData *cid = [@"bafyreitestcid1" dataUsingEncoding:NSUTF8StringEncoding];
    PDSDatabaseBlock *block = [self testBlockWithCid:cid repoDid:@"did:plc:blockowner1"];

    NSError *error = nil;
    BOOL saved = [self.database saveBlock:block error:&error];
    XCTAssertTrue(saved, @"saveBlock should succeed");
    XCTAssertNil(error);
}

- (void)testSaveBlocksBatch {
    NSData *cid1 = [@"bafyreibatchcid1" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *cid2 = [@"bafyreibatchcid2" dataUsingEncoding:NSUTF8StringEncoding];
    PDSDatabaseBlock *block1 = [self testBlockWithCid:cid1 repoDid:@"did:plc:batchowner"];
    PDSDatabaseBlock *block2 = [self testBlockWithCid:cid2 repoDid:@"did:plc:batchowner"];

    NSError *error = nil;
    BOOL saved = [self.database saveBlocks:@[block1, block2] error:&error];
    XCTAssertTrue(saved, @"saveBlocks should succeed for batch");
    XCTAssertNil(error);
}

#pragma mark - Read

- (void)testGetBlockWithCid {
    NSData *cid = [@"bafyreigetcid1" dataUsingEncoding:NSUTF8StringEncoding];
    PDSDatabaseBlock *block = [self testBlockWithCid:cid repoDid:@"did:plc:getowner"];
    [self.database saveBlock:block error:nil];

    NSError *error = nil;
    PDSDatabaseBlock *found = [self.database getBlockWithCid:cid repoDid:@"did:plc:getowner" error:&error];
    XCTAssertNotNil(found, @"Should find block by CID");
    XCTAssertNil(error);
    XCTAssertEqualObjects(found.cid, cid);
    XCTAssertEqualObjects(found.repoDid, @"did:plc:getowner");
}

- (void)testGetBlockWithCidNotFound {
    NSData *fakeCid = [@"bafyreinonexistent" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    PDSDatabaseBlock *found = [self.database getBlockWithCid:fakeCid repoDid:@"did:plc:nobody" error:&error];
    XCTAssertNil(found, @"Should return nil for nonexistent block");
    XCTAssertNil(error);
}

- (void)testGetBlocksForRepoWithPagination {
    NSString *repoDid = @"did:plc:paginated";
    for (int i = 0; i < 5; i++) {
        NSString *cidStr = [NSString stringWithFormat:@"bafyreipagecid%d", i];
        NSData *cid = [cidStr dataUsingEncoding:NSUTF8StringEncoding];
        PDSDatabaseBlock *block = [self testBlockWithCid:cid repoDid:repoDid];
        [self.database saveBlock:block error:nil];
    }

    NSError *error = nil;
    NSArray<PDSDatabaseBlock *> *page1 = [self.database getBlocksForRepo:repoDid limit:3 offset:0 error:&error];
    XCTAssertNil(error);
    XCTAssertLessThanOrEqual(page1.count, 3);
    XCTAssertGreaterThanOrEqual(page1.count, 1);

    NSArray<PDSDatabaseBlock *> *page2 = [self.database getBlocksForRepo:repoDid limit:3 offset:3 error:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(page2.count, 1);
}

- (void)testGetBlockCountForRepo {
    NSString *repoDid = @"did:plc:countowner";
    for (int i = 0; i < 3; i++) {
        NSString *cidStr = [NSString stringWithFormat:@"bafyreicountcid%d", i];
        NSData *cid = [cidStr dataUsingEncoding:NSUTF8StringEncoding];
        PDSDatabaseBlock *block = [self testBlockWithCid:cid repoDid:repoDid];
        [self.database saveBlock:block error:nil];
    }

    NSError *error = nil;
    NSInteger count = [self.database getBlockCountForRepo:repoDid error:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(count, 3);
}

#pragma mark - Delete

- (void)testDeleteBlock {
    NSData *cid = [@"bafyreideletecid1" dataUsingEncoding:NSUTF8StringEncoding];
    PDSDatabaseBlock *block = [self testBlockWithCid:cid repoDid:@"did:plc:deleteowner"];
    [self.database saveBlock:block error:nil];

    NSError *error = nil;
    BOOL deleted = [self.database deleteBlock:cid repoDid:@"did:plc:deleteowner" error:&error];
    XCTAssertTrue(deleted);
    XCTAssertNil(error);

    PDSDatabaseBlock *found = [self.database getBlockWithCid:cid repoDid:@"did:plc:deleteowner" error:nil];
    XCTAssertNil(found, @"Block should be gone after deletion");
}

@end
