// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "Database/PDSDatabase.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/Pool/DatabasePool.h"
#import "Services/PDS/PDSRecordService.h"
#import "Core/Repositories/PDSRecordRepository.h"
#import "Core/ATProtoError.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Core/CID.h"
#import "Core/ATProtoDagCBOR.h"

@interface IPLDBlockIntegrityTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSController *controller;
@end

@implementation IPLDBlockIntegrityTests

- (void)setUp {
    [super setUp];
    NSString *name = [@"IPLDBlockIntegrityTests_" stringByAppendingString:NSUUID.UUID.UUIDString];
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    self.controller = [[PDSController alloc] initWithDirectory:self.testDirectory
                                                serviceMaxSize:10
                                              userDatabaseSize:20];
}

- (void)tearDown {
    [self.controller stopServer];
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (void)testCharacterization_RecordCreationPopulatesIpldBlocks {
    NSString *did = @"did:plc:abcdefghijklmnopqrstuvwx";
    NSString *collection = @"app.bsky.feed.post";
    NSString *rkey = @"test-post";
    NSDictionary *value = @{
        @"$type": collection,
        @"text": @"Hello, IPLD!",
        @"createdAt": [NSDateFormatter atproto_stringFromDate:[NSDate date]]
    };
    
    // First create the account so the DID exists
    NSError *error = nil;
    [self.controller createAccountForEmail:@"test@example.com"
                                  password:@"password123"
                                    handle:@"test.example.com"
                                       did:did
                                      error:&error];
    XCTAssertNil(error, @"Account creation failed: %@", error);

    // We use the record service to create the record, as a real PDS would.
    BOOL result = [self.controller putRecord:collection
                                        rkey:rkey
                                       value:value
                                      forDid:did
                               validationMode:PDSValidationModeOptimistic
                                       error:&error];
    
    XCTAssertTrue(result, @"Record creation failed: %@", error);
    
    // Now check if the record exists
    NSDictionary *recordDict = [self.controller getRecord:[NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey] forDid:did error:&error];
    XCTAssertNotNil(recordDict, @"Record not found in database");
    NSString *cidString = recordDict[@"cid"];
    XCTAssertNotNil(cidString, @"Record missing CID");
    
    // Open actor store to check blocks
    PDSActorStore *store = [self.controller.userDatabasePool storeForDid:did error:&error];
    XCTAssertNotNil(store, @"Failed to get actor store");
    
    NSArray<PDSDatabaseBlock *> *blocks = [store listBlocksForDid:did limit:100 offset:0 error:&error];
    
    BOOL found = NO;
    for (PDSDatabaseBlock *block in blocks) {
        // block.cid is NSData* - it should be the raw CID bytes
        CID *blockCID = [CID cidFromBytes:block.cid];
        if ([blockCID.stringValue isEqualToString:cidString]) {
            found = YES;
            break;
        }
    }
    
    // Check if we found the record block
    XCTAssertTrue(found, @"Record block for CID %@ NOT found in ipld_blocks table!", cidString);
    
    // Check if we found other blocks (commit, MST nodes)
    XCTAssertGreaterThan(blocks.count, 1, @"Only one block (or zero) found? Expected commit + MST nodes + record block.");
}

- (void)testCharacterization_ApplyWritesPopulatesIpldBlocks {
    NSString *did = @"did:plc:bcdefghijklmnopqrstuvwxy";
    
    // First create the account
    NSError *error = nil;
    [self.controller createAccountForEmail:@"test2@example.com"
                                  password:@"password123"
                                    handle:@"test2.example.com"
                                       did:did
                                      error:&error];
    XCTAssertNil(error);

    NSDictionary *post1 = @{@"$type": @"app.bsky.feed.post", @"text": @"Post 1", @"createdAt": [NSDateFormatter atproto_stringFromDate:[NSDate date]]};
    NSDictionary *post2 = @{@"$type": @"app.bsky.feed.post", @"text": @"Post 2", @"createdAt": [NSDateFormatter atproto_stringFromDate:[NSDate date]]};
    
    NSArray *writes = @[
        @{@"action": @"create", @"collection": @"app.bsky.feed.post", @"value": post1},
        @{@"action": @"create", @"collection": @"app.bsky.feed.post", @"value": post2}
    ];
    
    NSDictionary *result = [self.controller.recordService applyWrites:writes forDid:did actorDid:did validationMode:PDSValidationModeOptimistic swapCommit:nil error:&error];
    XCTAssertNotNil(result, @"ApplyWrites failed: %@", error);
    
    // Check if both blocks exist
    PDSActorStore *store = [self.controller.userDatabasePool storeForDid:did error:&error];
    NSArray<PDSDatabaseBlock *> *blocks = [store listBlocksForDid:did limit:100 offset:0 error:&error];
    
    // We expect at least: 1 commit block, some MST blocks, and 2 record blocks.
    XCTAssertGreaterThanOrEqual(blocks.count, 4, @"Not enough blocks found");
    
    // Find record blocks specifically
    NSInteger recordBlocksFound = 0;
    for (PDSDatabaseBlock *block in blocks) {
        NSError *decodeError = nil;
        id obj = [ATProtoDagCBOR decodeData:block.blockData error:&decodeError];
        if (decodeError) {
            continue;
        }
        if ([obj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)obj;
            if ([dict[@"text"] hasPrefix:@"Post "]) {
                recordBlocksFound++;
            }
        }
    }
    
    XCTAssertEqual(recordBlocksFound, 2, @"Should have found 2 record blocks in ipld_blocks");
}

@end
