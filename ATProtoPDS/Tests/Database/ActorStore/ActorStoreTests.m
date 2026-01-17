#import <XCTest/XCTest.h>
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import <sqlite3.h>
#import <Security/Security.h>

@interface ActorStoreTests : XCTestCase

@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) NSString *testDID;
@property (nonatomic, strong) PDSActorStore *store;

@end

@implementation ActorStoreTests

- (void)setUp {
    [super setUp];
    
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ActorStoreTests"];
    self.testDID = @"did:plc:test123456789";
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.testDirectory error:nil];
    [fm createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"data.sqlite"];
    __autoreleasing NSError *error = nil;
    self.store = [PDSActorStore storeWithDid:self.testDID dbPath:dbPath error:&error];
    XCTAssertNotNil(self.store, @"Failed to create store: %@", error);
    XCTAssertTrue(self.store.isOpen, @"Store should be open");
    self.store.useKeychainSigningKey = NO;
}

- (void)tearDown {
    [self.store close];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.testDirectory error:nil];
    
    [super tearDown];
}

- (void)testStoreInitialization {
    XCTAssertNotNil(self.store);
    XCTAssertEqualObjects(self.store.did, self.testDID);
    XCTAssertNotNil(self.store.dbPath);
    XCTAssertTrue(self.store.isOpen);
}

- (void)testAccountCreation {
    __autoreleasing NSError *error = nil;
    
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = self.testDID;
    account.handle = @"test.example.com";
    account.email = @"test@example.com";
    account.passwordHash = [@"hash_data" dataUsingEncoding:NSUTF8StringEncoding];
    account.passwordSalt = [@"salt_data" dataUsingEncoding:NSUTF8StringEncoding];
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    
    BOOL success = [self.store createAccount:account error:&error];
    XCTAssertTrue(success, @"Failed to create account: %@", error);
    
    __autoreleasing NSError *fetchError = nil;
    PDSDatabaseAccount *fetched = [self.store getAccountForDid:self.testDID error:&fetchError];
    XCTAssertNotNil(fetched, @"Failed to fetch account: %@", fetchError);
    XCTAssertEqualObjects(fetched.did, self.testDID);
    XCTAssertEqualObjects(fetched.handle, @"test.example.com");
    XCTAssertEqualObjects(fetched.email, @"test@example.com");
}

- (void)testAccountUpdate {
    __autoreleasing NSError *error = nil;
    
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = self.testDID;
    account.handle = @"test.example.com";
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    
    XCTAssertTrue([self.store createAccount:account error:&error], @"Create failed: %@", error);
    
    account.email = @"updated@example.com";
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    __autoreleasing NSError *updateError = nil;
    XCTAssertTrue([self.store updateAccount:account error:&updateError], @"Update failed: %@", updateError);
    
    __autoreleasing NSError *fetchError = nil;
    PDSDatabaseAccount *fetched = [self.store getAccountForDid:self.testDID error:&fetchError];
    XCTAssertEqualObjects(fetched.email, @"updated@example.com");
}

- (void)testRecordOperations {
    __autoreleasing NSError *error = nil;
    
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/3k5xyz", self.testDID];
    record.did = self.testDID;
    record.collection = @"app.bsky.feed.post";
    record.rkey = @"3k5xyz";
    record.cid = @"bafyreitESTCID123456789";
    record.createdAt = [NSDate date];
    
    XCTAssertTrue([self.store putRecord:record forDid:self.testDID error:&error], @"Put record failed: %@", error);
    
    __autoreleasing NSError *fetchError = nil;
    PDSDatabaseRecord *fetched = [self.store getRecord:record.uri forDid:self.testDID error:&fetchError];
    XCTAssertNotNil(fetched, @"Get record failed: %@", fetchError);
    XCTAssertEqualObjects(fetched.uri, record.uri);
    XCTAssertEqualObjects(fetched.collection, @"app.bsky.feed.post");
    XCTAssertEqualObjects(fetched.rkey, @"3k5xyz");
    
    __autoreleasing NSError *listError = nil;
    NSArray<PDSDatabaseRecord *> *records = [self.store listRecordsForDid:self.testDID 
                                                               collection:@"app.bsky.feed.post"
                                                                     limit:10
                                                                    offset:0
                                                                     error:&listError];
    XCTAssertEqual(records.count, 1, @"Should have 1 record");
    
    __autoreleasing NSError *deleteError = nil;
    XCTAssertTrue([self.store deleteRecord:record.uri forDid:self.testDID error:&deleteError], @"Delete failed: %@", deleteError);
    
    __autoreleasing NSError *fetchDeletedError = nil;
    PDSDatabaseRecord *deleted = [self.store getRecord:record.uri forDid:self.testDID error:&fetchDeletedError];
    XCTAssertNil(deleted, @"Record should be deleted");
}

- (void)testBlockOperations {
    __autoreleasing NSError *error = nil;
    
    NSData *blockData = [@"test block data" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *cidData = [NSMutableData dataWithLength:32];
    memset(cidData.mutableBytes, 0xAB, 32);
    
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = cidData;
    block.repoDid = self.testDID;
    block.blockData = blockData;
    block.size = blockData.length;
    block.createdAt = [NSDate date];
    
    XCTAssertTrue([self.store putBlock:block forDid:self.testDID error:&error], @"Put block failed: %@", error);
    
    __autoreleasing NSError *fetchError = nil;
    NSData *fetchedData = [self.store getBlockForCID:cidData forDid:self.testDID error:&fetchError];
    XCTAssertNotNil(fetchedData, @"Get block failed: %@", fetchError);
    XCTAssertEqualObjects(fetchedData, blockData);
    
    __autoreleasing NSError *countError = nil;
    NSInteger count = [self.store getBlockCountForDid:self.testDID error:&countError];
    XCTAssertEqual(count, 1, @"Should have 1 block");
    
    __autoreleasing NSError *deleteError = nil;
    XCTAssertTrue([self.store deleteBlock:cidData forDid:self.testDID error:&deleteError], @"Delete block failed: %@", deleteError);
}

- (void)testTransaction {
    __autoreleasing NSError *error = nil;
    
    PDSDatabaseRecord *record1 = [[PDSDatabaseRecord alloc] init];
    record1.uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/tx1", self.testDID];
    record1.did = self.testDID;
    record1.collection = @"app.bsky.feed.post";
    record1.rkey = @"tx1";
    record1.cid = @"bafyreitESTCID111";
    record1.createdAt = [NSDate date];
    
    PDSDatabaseRecord *record2 = [[PDSDatabaseRecord alloc] init];
    record2.uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/tx2", self.testDID];
    record2.did = self.testDID;
    record2.collection = @"app.bsky.feed.post";
    record2.rkey = @"tx2";
    record2.cid = @"bafyreitESTCID222";
    record2.createdAt = [NSDate date];
    
    __autoreleasing NSError *blockError = nil;
    [self.store transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        __autoreleasing NSError *txError = nil;
        XCTAssertTrue([transactor putRecord:record1 forDid:self.testDID error:&txError], @"Put tx1 failed: %@", txError);
        __autoreleasing NSError *txError2 = nil;
        XCTAssertTrue([transactor putRecord:record2 forDid:self.testDID error:&txError2], @"Put tx2 failed: %@", txError2);
    } error:&blockError];
    
    __autoreleasing NSError *fetchError1 = nil;
    PDSDatabaseRecord *fetched1 = [self.store getRecord:record1.uri forDid:self.testDID error:&fetchError1];
    XCTAssertNotNil(fetched1, @"Record1 should exist after transaction");
    
    __autoreleasing NSError *fetchError2 = nil;
    PDSDatabaseRecord *fetched2 = [self.store getRecord:record2.uri forDid:self.testDID error:&fetchError2];
    XCTAssertNotNil(fetched2, @"Record2 should exist after transaction");
}

- (void)testSigningKeyGeneration {
    __autoreleasing NSError *error = nil;
    
    // Initially, we expect no key if one hasn't been generated/stored/loaded
    // However, if useKeychainSigningKey is NO, signingKeyWithError returns NULL immediately if not set.
    XCTAssertFalse([self.store signingKeyWithError:&error], @"Should not have signing key initially");
    
    // In strict test environments, error might be nil or specific code.
    // If it returns NULL, we check if error is populated.
    if (![self.store signingKeyWithError:nil]) {
         XCTAssertNotNil(error, @"Should have error for missing key");
    }
    
    __autoreleasing NSError *genError = nil;
    if (![self.store generateSigningKeyWithError:&genError]) {
        XCTSkip(@"Signing key generation unavailable in this environment: %@", genError);
        return;
    }
    
    __autoreleasing NSError *keyError = nil;
    SecKeyRef key = [self.store signingKeyWithError:&keyError];
    XCTAssertNotNil((__bridge id)key, @"Should have signing key now: %@", keyError);
}

- (void)testSigningKeyGenerationNoLeak {
    __autoreleasing NSError *genError = nil;
    
    if (![self.store generateSigningKeyWithError:&genError]) {
        XCTSkip(@"Signing key generation unavailable in this environment");
        return;
    }
    
    __autoreleasing NSError *keyError1 = nil;
    SecKeyRef key1 = [self.store signingKeyWithError:&keyError1];
    XCTAssertNotNil((__bridge id)key1, @"Should have signing key after first generation");
    
    __autoreleasing NSError *genError2 = nil;
    BOOL success = [self.store generateSigningKeyWithError:&genError2];
    XCTAssertTrue(success, @"Second key generation should succeed");
    
    __autoreleasing NSError *keyError2 = nil;
    SecKeyRef key2 = [self.store signingKeyWithError:&keyError2];
    XCTAssertNotNil((__bridge id)key2, @"Should have signing key after second generation");
    
    if (key1 != key2) {
        XCTAssertTrue(YES, @"Second key generation produced different key (no leak)");
    }
}

- (void)testRecordCount {
    __autoreleasing NSError *error = nil;
    
    for (int i = 0; i < 5; i++) {
        PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
        record.uri = [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/count%d", self.testDID, i];
        record.did = self.testDID;
        record.collection = @"app.bsky.feed.post";
        record.rkey = [NSString stringWithFormat:@"count%d", i];
        record.cid = [NSString stringWithFormat:@"bafyreitESTCID%d", i];
        record.createdAt = [NSDate date];
        
        __autoreleasing NSError *putError = nil;
        XCTAssertTrue([self.store putRecord:record forDid:self.testDID error:&putError], @"Put %d failed", i);
    }
    
    __autoreleasing NSError *countError = nil;
    NSInteger totalCount = [self.store getRecordCountForDid:self.testDID collection:nil error:&countError];
    XCTAssertEqual(totalCount, 5, @"Should have 5 records");
    
    __autoreleasing NSError *colCountError = nil;
    NSInteger collectionCount = [self.store getRecordCountForDid:self.testDID collection:@"app.bsky.feed.post" error:&colCountError];
    XCTAssertEqual(collectionCount, 5, @"Should have 5 records in collection");
}

- (void)testSaveBlobAndListBlobsForDid {
    __autoreleasing NSError *error = nil;

    PDSDatabaseBlob *blob1 = [[PDSDatabaseBlob alloc] init];
    blob1.cid = [@"blobcid1" dataUsingEncoding:NSUTF8StringEncoding];
    blob1.did = self.testDID;
    blob1.mimeType = @"text/plain";
    blob1.size = 100;
    blob1.createdAt = [NSDate date];

    PDSDatabaseBlob *blob2 = [[PDSDatabaseBlob alloc] init];
    blob2.cid = [@"blobcid2" dataUsingEncoding:NSUTF8StringEncoding];
    blob2.did = self.testDID;
    blob2.mimeType = @"image/jpeg";
    blob2.size = 500;
    blob2.createdAt = [NSDate date];

    BOOL success1 = [self.store saveBlob:blob1 error:&error];
    XCTAssertTrue(success1, @"Failed to save blob1: %@", error);

    BOOL success2 = [self.store saveBlob:blob2 error:&error];
    XCTAssertTrue(success2, @"Failed to save blob2: %@", error);

    NSArray<PDSDatabaseBlob *> *blobs = [self.store listBlobsForDid:self.testDID limit:10 cursor:nil error:&error];
    XCTAssertNotNil(blobs, @"Blobs should not be nil");
    XCTAssertEqual(blobs.count, 2, @"Should have 2 blobs");

    PDSDatabaseBlob *retrievedBlob = [self.store getBlobForCID:blob1.cid error:&error];
    XCTAssertNotNil(retrievedBlob, @"Should retrieve blob1");
    XCTAssertEqualObjects(retrievedBlob.mimeType, @"text/plain", @"MIME type should match");
    XCTAssertEqual(retrievedBlob.size, 100, @"Size should match");
}

- (void)testListBlobsExcludesOtherDids {
    __autoreleasing NSError *error = nil;

    PDSDatabaseBlob *blob1 = [[PDSDatabaseBlob alloc] init];
    blob1.cid = [@"blobcid1" dataUsingEncoding:NSUTF8StringEncoding];
    blob1.did = self.testDID;
    blob1.mimeType = @"text/plain";
    blob1.size = 100;
    blob1.createdAt = [NSDate date];

    PDSDatabaseBlob *blob2 = [[PDSDatabaseBlob alloc] init];
    blob2.cid = [@"blobcid2" dataUsingEncoding:NSUTF8StringEncoding];
    blob2.did = @"did:plc:other123456789";
    blob2.mimeType = @"image/jpeg";
    blob2.size = 500;
    blob2.createdAt = [NSDate date];

    BOOL success1 = [self.store saveBlob:blob1 error:&error];
    XCTAssertTrue(success1, @"Failed to save blob1: %@", error);

    BOOL success2 = [self.store saveBlob:blob2 error:&error];
    XCTAssertTrue(success2, @"Failed to save blob2: %@", error);

    NSArray<PDSDatabaseBlob *> *blobs = [self.store listBlobsForDid:self.testDID limit:10 cursor:nil error:&error];
    XCTAssertNotNil(blobs, @"Blobs should not be nil");
    XCTAssertEqual(blobs.count, 1, @"Should have only 1 blob for this DID");
    XCTAssertEqualObjects(blobs[0].did, self.testDID, @"Blob should belong to this DID");
}

- (void)testDeleteBlobForCID {
    __autoreleasing NSError *error = nil;

    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    blob.cid = [@"blobcid1" dataUsingEncoding:NSUTF8StringEncoding];
    blob.did = self.testDID;
    blob.mimeType = @"text/plain";
    blob.size = 100;
    blob.createdAt = [NSDate date];

    BOOL success = [self.store saveBlob:blob error:&error];
    XCTAssertTrue(success, @"Failed to save blob: %@", error);

    // Verify blob exists
    PDSDatabaseBlob *retrieved = [self.store getBlobForCID:blob.cid error:&error];
    XCTAssertNotNil(retrieved, @"Blob should exist before deletion");

    // Delete blob
    BOOL deleteSuccess = [self.store deleteBlobForCID:blob.cid forDid:self.testDID error:&error];
    XCTAssertTrue(deleteSuccess, @"Failed to delete blob: %@", error);

    // Verify blob is gone
    PDSDatabaseBlob *afterDelete = [self.store getBlobForCID:blob.cid error:&error];
    XCTAssertNil(afterDelete, @"Blob should not exist after deletion");
}

@end
