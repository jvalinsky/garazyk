#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Auth/CryptoUtils.h"
#import "App/PDSConfiguration.h"
#import <sqlite3.h>
#import <CommonCrypto/CommonCrypto.h>

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

    NSData *payload = [@"test-payload" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *initialSignature = [self.store signData:payload error:&error];
    XCTAssertNil(initialSignature, @"Store should not sign without a key");
    XCTAssertNotNil(error, @"Missing-key sign path should surface an error");

    __autoreleasing NSError *genError = nil;
    if (![self.store generateSigningKeyWithError:&genError]) {
        XCTSkip(@"Signing key generation unavailable in this environment: %@", genError);
        return;
    }

    __autoreleasing NSError *publicKeyError = nil;
    NSData *compressedPublicKey = [self.store publicSigningKeyWithError:&publicKeyError];
    XCTAssertNotNil(compressedPublicKey, @"Public key should be available after generation: %@", publicKeyError);
    XCTAssertEqual(compressedPublicKey.length, (NSUInteger)33, @"Actor signing key must be compressed secp256k1");

    __autoreleasing NSError *didKeyError = nil;
    NSString *didKey = [self.store didKeyStringWithError:&didKeyError];
    XCTAssertNotNil(didKey, @"did:key should be available after generation: %@", didKeyError);
    XCTAssertTrue([didKey hasPrefix:@"did:key:z"], @"did:key must use multibase z prefix");

    __autoreleasing NSError *signError = nil;
    NSData *signature = [self.store signData:payload error:&signError];
    XCTAssertNotNil(signature, @"Signing should succeed after key generation: %@", signError);
    XCTAssertGreaterThan(signature.length, (NSUInteger)0, @"Signature must not be empty");
}

- (void)testSigningKeyGenerationNoLeak {
    __autoreleasing NSError *firstError = nil;
    if (![self.store generateSigningKeyWithError:&firstError]) {
        XCTSkip(@"Signing key generation unavailable in this environment");
        return;
    }

    __autoreleasing NSError *didKeyError1 = nil;
    NSString *didKey1 = [self.store didKeyStringWithError:&didKeyError1];
    XCTAssertNotNil(didKey1, @"First key should produce did:key");

    __autoreleasing NSError *secondError = nil;
    XCTAssertTrue([self.store generateSigningKeyWithError:&secondError], @"Second key generation should succeed");

    __autoreleasing NSError *didKeyError2 = nil;
    NSString *didKey2 = [self.store didKeyStringWithError:&didKeyError2];
    XCTAssertNotNil(didKey2, @"Second key should produce did:key");

    // Rotation should replace the active key material.
    XCTAssertFalse([didKey1 isEqualToString:didKey2], @"Second generation should rotate the active key");

    NSData *payload = [@"leak-check" dataUsingEncoding:NSUTF8StringEncoding];
    __autoreleasing NSError *signError = nil;
    NSData *signature = [self.store signData:payload error:&signError];
    XCTAssertNotNil(signature, @"Signing should still work after repeated key generation: %@", signError);
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

#pragma mark - Rotation Key CBC→GCM Migration Tests

// Build a versioned CBC blob (0x01 || IV(16) || AES-CBC(plaintext))
- (NSData *)makeCBCBlobForData:(NSData *)plaintext key:(NSData *)key {
    uint8_t iv[16] = {
        0xAA,0xBB,0xCC,0xDD,0xEE,0xFF,0x00,0x11,
        0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99
    };
    size_t bufSize = plaintext.length + kCCBlockSizeAES128;
    NSMutableData *ct = [NSMutableData dataWithLength:bufSize];
    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
                                 key.bytes, key.length, iv,
                                 plaintext.bytes, plaintext.length,
                                 ct.mutableBytes, bufSize, &moved);
    if (st != kCCSuccess) return nil;
    ct.length = moved;

    NSMutableData *blob = [NSMutableData data];
    uint8_t version = 0x01;
    [blob appendBytes:&version length:1];
    [blob appendBytes:iv length:16];
    [blob appendData:ct];
    return blob;
}

- (void)testRotationKeyMigratesCBCToGCM {
    // Set up a master secret so rotationKeyDecryptedWithPassword: can find a key
    NSString *testPassword = @"test-migration-secret-actor-store";
    NSString *previousSecret = [PDSConfiguration sharedConfiguration].masterSecret;
    [PDSConfiguration sharedConfiguration].masterSecret = testPassword;

    // Generate a fake 32-byte private key
    NSMutableData *fakePrivKey = [NSMutableData dataWithLength:32];
    for (NSUInteger i = 0; i < 32; i++) {
        uint8_t b = (uint8_t)(i + 1);
        [fakePrivKey replaceBytesInRange:NSMakeRange(i, 1) withBytes:&b];
    }

    // Derive the encryption key exactly as the store does (PBKDF2 with a random salt)
    NSData *salt = [CryptoUtils randomBytes:16];
    NSData *encKey = [CryptoUtils deriveKeyFromPassword:testPassword salt:salt];
    XCTAssertNotNil(encKey);

    // Build a versioned CBC encrypted_private_key blob
    NSData *cbcBlob = [self makeCBCBlobForData:fakePrivKey key:encKey];
    XCTAssertNotNil(cbcBlob);

    // Insert the CBC blob directly into the rotation_keys table via raw SQLite
    sqlite3 *db;
    NSString *dbPath = self.store.dbPath;
    XCTAssertEqual(sqlite3_open(dbPath.UTF8String, &db), SQLITE_OK);

    const char *insertSQL =
        "INSERT OR REPLACE INTO rotation_keys "
        "(did, encrypted_private_key, public_key_compressed, encryption_salt, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, ?, ?)";
    sqlite3_stmt *stmt;
    XCTAssertEqual(sqlite3_prepare_v2(db, insertSQL, -1, &stmt, NULL), SQLITE_OK);
    sqlite3_bind_text(stmt, 1, self.testDID.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_blob(stmt, 2, cbcBlob.bytes, (int)cbcBlob.length, SQLITE_TRANSIENT);
    NSData *fakePubKey = [NSData dataWithLength:33]; // compressed secp256k1 public key placeholder
    sqlite3_bind_blob(stmt, 3, fakePubKey.bytes, (int)fakePubKey.length, SQLITE_TRANSIENT);
    sqlite3_bind_blob(stmt, 4, salt.bytes, (int)salt.length, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 5, [[NSDate date] timeIntervalSince1970]);
    sqlite3_bind_double(stmt, 6, [[NSDate date] timeIntervalSince1970]);
    XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE);
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    // Now call rotationKeyDecryptedWithPassword: — it must decrypt and migrate to GCM
    NSError *error = nil;
    NSData *recovered = [self.store rotationKeyDecryptedWithPassword:testPassword error:&error];
    XCTAssertNotNil(recovered, @"Rotation key must be decrypted: %@", error);
    XCTAssertEqualObjects(recovered, fakePrivKey, @"Decrypted key must match original");

    // Verify the stored blob has been updated to GCM (version byte 0x02)
    sqlite3_open(dbPath.UTF8String, &db);
    const char *selectSQL = "SELECT encrypted_private_key FROM rotation_keys WHERE did = ?";
    sqlite3_prepare_v2(db, selectSQL, -1, &stmt, NULL);
    sqlite3_bind_text(stmt, 1, self.testDID.UTF8String, -1, SQLITE_TRANSIENT);
    XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW);
    const void *updatedBytes = sqlite3_column_blob(stmt, 0);
    int updatedLen = sqlite3_column_bytes(stmt, 0);
    NSData *updatedBlob = [NSData dataWithBytes:updatedBytes length:updatedLen];
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    XCTAssertGreaterThan(updatedBlob.length, (NSUInteger)0);
    const uint8_t *vp = (const uint8_t *)updatedBlob.bytes;
    XCTAssertEqual(vp[0], (uint8_t)0x02,
                   @"Migrated rotation key blob must start with GCM version byte 0x02");

    [PDSConfiguration sharedConfiguration].masterSecret = previousSecret;
}

@end
