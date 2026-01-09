#import <XCTest/XCTest.h>
#import "Database/Integration/PDSDatabaseIntegrationTestUtilities.h"
#import "Database/ActorStore/ActorStore.h"

@interface MultiTenantDatabaseTests : XCTestCase

@property (nonatomic, strong) PDSMultiTenantTestFixture *fixture;

@end

@implementation MultiTenantDatabaseTests

- (void)setUp {
    [super setUp];

    self.fixture = [[PDSMultiTenantTestFixture alloc] initWithTestName:@"MultiTenantDatabaseTests"
                                                              maxPoolSize:5
                                                                testDIDs:@[@"did:plc:alice", @"did:plc:bob", @"did:plc:charlie"]];

    __autoreleasing NSError *error = nil;
    XCTAssertTrue([self.fixture setupTenantsWithError:&error], @"Failed to setup tenants: %@", error);
}

- (void)tearDown {
    __autoreleasing NSError *error = nil;
    [self.fixture teardownPoolWithError:&error];
    self.fixture = nil;
    [super tearDown];
}

- (void)testActorStoreIsolation {
    // Test that data created in one actor store doesn't leak to another
    NSString *aliceDID = @"did:plc:alice";
    NSString *bobDID = @"did:plc:bob";

    __autoreleasing NSError *error = nil;

    // Create test data for Alice
    PDSDatabaseRecord *aliceRecord = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:aliceDID
                                                                                         collection:@"app.bsky.feed.post"
                                                                                              rkey:@"alice-post-1"];
    PDSDatabaseBlock *aliceBlock = [PDSDatabaseIntegrationTestUtilities createTestBlockWithRepoDID:aliceDID];

    // Create Alice's actor store
    NSString *aliceDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"actorstore_%@.db", aliceDID]];
    PDSActorStore *aliceStore = [PDSActorStore storeWithDid:aliceDID dbPath:aliceDbPath error:&error];
    XCTAssertNotNil(aliceStore, @"Failed to create Alice's actor store: %@", error);

    // Add data to Alice's store
    [aliceStore transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
        [transactor putRecord:aliceRecord forDid:aliceDID error:&error];
        XCTAssertNil(error, @"Failed to put Alice's record: %@", error);

        [transactor putBlock:aliceBlock forDid:aliceDID error:&error];
        XCTAssertNil(error, @"Failed to put Alice's block: %@", error);
    } error:&error];
    XCTAssertNil(error, @"Failed to commit Alice's transaction: %@", error);

    // Create Bob's actor store
    NSString *bobDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"actorstore_%@.db", bobDID]];
    PDSActorStore *bobStore = [PDSActorStore storeWithDid:bobDID dbPath:bobDbPath error:&error];
    XCTAssertNotNil(bobStore, @"Failed to create Bob's actor store: %@", error);

    // Verify Alice's data is in her store
    __block PDSDatabaseRecord *fetchedAliceRecord = nil;
    [aliceStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        fetchedAliceRecord = [reader getRecord:aliceRecord.uri forDid:aliceDID error:&error];
    } error:&error];
    XCTAssertNotNil(fetchedAliceRecord, @"Alice's record should be found in her store");
    XCTAssertEqualObjects(fetchedAliceRecord.uri, aliceRecord.uri);

    // Verify Alice's data is NOT in Bob's store
    __block PDSDatabaseRecord *bobFetchedAliceRecord = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        bobFetchedAliceRecord = [reader getRecord:aliceRecord.uri forDid:aliceDID error:&error];
    } error:&error];
    XCTAssertNil(bobFetchedAliceRecord, @"Alice's record should NOT be found in Bob's store");

    // Verify Bob's store has no records
    __block NSArray<PDSDatabaseRecord *> *bobRecords = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        bobRecords = [reader listRecordsForDid:bobDID collection:nil limit:100 offset:0 error:&error];
    } error:&error];
    XCTAssertEqual(bobRecords.count, 0, @"Bob's store should have no records");

    // Clean up
    [aliceStore close];
    [bobStore close];

    // Remove test database files
    [[NSFileManager defaultManager] removeItemAtPath:aliceDbPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:bobDbPath error:nil];
}

- (void)testCrossTenantDataProtection {
    // Test that one tenant cannot access or modify another's data
    NSString *aliceDID = @"did:plc:alice";
    NSString *bobDID = @"did:plc:bob";

    __autoreleasing NSError *error = nil;

    // Create test data for both tenants
    PDSDatabaseRecord *aliceRecord = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:aliceDID
                                                                                         collection:@"app.bsky.feed.post"
                                                                                              rkey:@"alice-post-1"];
    PDSDatabaseRecord *bobRecord = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:bobDID
                                                                                       collection:@"app.bsky.feed.post"
                                                                                            rkey:@"bob-post-1"];

    PDSDatabaseBlock *aliceBlock = [PDSDatabaseIntegrationTestUtilities createTestBlockWithRepoDID:aliceDID];
    PDSDatabaseBlock *bobBlock = [PDSDatabaseIntegrationTestUtilities createTestBlockWithRepoDID:bobDID];

    // Create actor stores
    NSString *aliceDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"actorstore_%@.db", aliceDID]];
    PDSActorStore *aliceStore = [PDSActorStore storeWithDid:aliceDID dbPath:aliceDbPath error:&error];
    XCTAssertNotNil(aliceStore, @"Failed to create Alice's actor store: %@", error);

    NSString *bobDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"actorstore_%@.db", bobDID]];
    PDSActorStore *bobStore = [PDSActorStore storeWithDid:bobDID dbPath:bobDbPath error:&error];
    XCTAssertNotNil(bobStore, @"Failed to create Bob's actor store: %@", error);

    // Add data to Alice's store
    [aliceStore transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
        [transactor putRecord:aliceRecord forDid:aliceDID error:&error];
        XCTAssertNil(error, @"Failed to put Alice's record: %@", error);

        [transactor putBlock:aliceBlock forDid:aliceDID error:&error];
        XCTAssertNil(error, @"Failed to put Alice's block: %@", error);
    } error:&error];
    XCTAssertNil(error, @"Failed to commit Alice's transaction: %@", error);

    // Add data to Bob's store
    [bobStore transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
        [transactor putRecord:bobRecord forDid:bobDID error:&error];
        XCTAssertNil(error, @"Failed to put Bob's record: %@", error);

        [transactor putBlock:bobBlock forDid:bobDID error:&error];
        XCTAssertNil(error, @"Failed to put Bob's block: %@", error);
    } error:&error];
    XCTAssertNil(error, @"Failed to commit Bob's transaction: %@", error);

    // Verify cross-tenant protection: Alice cannot access Bob's data
    __block PDSDatabaseRecord *aliceAccessingBobRecord = nil;
    [aliceStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        aliceAccessingBobRecord = [reader getRecord:bobRecord.uri forDid:bobDID error:&error];
    } error:&error];
    XCTAssertNil(aliceAccessingBobRecord, @"Alice should NOT be able to access Bob's record");

    __block NSData *aliceAccessingBobBlock = nil;
    [aliceStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        aliceAccessingBobBlock = [reader getBlockForCID:bobBlock.cid forDid:bobDID error:&error];
    } error:&error];
    XCTAssertNil(aliceAccessingBobBlock, @"Alice should NOT be able to access Bob's block");

    // Verify cross-tenant protection: Bob cannot access Alice's data
    __block PDSDatabaseRecord *bobAccessingAliceRecord = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        bobAccessingAliceRecord = [reader getRecord:aliceRecord.uri forDid:aliceDID error:&error];
    } error:&error];
    XCTAssertNil(bobAccessingAliceRecord, @"Bob should NOT be able to access Alice's record");

    __block NSData *bobAccessingAliceBlock = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        bobAccessingAliceBlock = [reader getBlockForCID:aliceBlock.cid forDid:aliceDID error:&error];
    } error:&error];
    XCTAssertNil(bobAccessingAliceBlock, @"Bob should NOT be able to access Alice's block");

    // Verify each tenant can only see their own data
    __block NSArray<PDSDatabaseRecord *> *aliceRecords = nil;
    [aliceStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        aliceRecords = [reader listRecordsForDid:aliceDID collection:nil limit:100 offset:0 error:&error];
    } error:&error];
    XCTAssertEqual(aliceRecords.count, 1, @"Alice should see only 1 record");
    XCTAssertEqualObjects(aliceRecords.firstObject.uri, aliceRecord.uri);

    __block NSArray<PDSDatabaseRecord *> *bobRecords = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        bobRecords = [reader listRecordsForDid:bobDID collection:nil limit:100 offset:0 error:&error];
    } error:&error];
    XCTAssertEqual(bobRecords.count, 1, @"Bob should see only 1 record");
    XCTAssertEqualObjects(bobRecords.firstObject.uri, bobRecord.uri);

    // Test that operations on one store don't affect the other
    // Delete Alice's record
    [aliceStore transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
        [transactor deleteRecord:aliceRecord.uri forDid:aliceDID error:&error];
        XCTAssertNil(error, @"Failed to delete Alice's record: %@", error);
    } error:&error];
    XCTAssertNil(error, @"Failed to commit Alice's delete transaction: %@", error);

    // Verify Alice's record is gone from her store
    __block PDSDatabaseRecord *deletedAliceRecord = nil;
    [aliceStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        deletedAliceRecord = [reader getRecord:aliceRecord.uri forDid:aliceDID error:&error];
    } error:&error];
    XCTAssertNil(deletedAliceRecord, @"Alice's record should be deleted from her store");

    // Verify Bob's record is still there and unaffected
    __block PDSDatabaseRecord *unaffectedBobRecord = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        unaffectedBobRecord = [reader getRecord:bobRecord.uri forDid:bobDID error:&error];
    } error:&error];
    XCTAssertNotNil(unaffectedBobRecord, @"Bob's record should still exist and be unaffected");

    // Clean up
    [aliceStore close];
    [bobStore close];

    // Remove test database files
    [[NSFileManager defaultManager] removeItemAtPath:aliceDbPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:bobDbPath error:nil];
}

- (void)testTenantSpecificMigrations {
    // Test that schema migrations are applied correctly to each tenant's database
    NSString *aliceDID = @"did:plc:alice";
    NSString *bobDID = @"did:plc:bob";
    NSString *charlieDID = @"did:plc:charlie";

    __autoreleasing NSError *error = nil;

    // Create actor stores for multiple tenants - this should apply schema migrations
    NSString *aliceDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"actorstore_%@.db", aliceDID]];
    PDSActorStore *aliceStore = [PDSActorStore storeWithDid:aliceDID dbPath:aliceDbPath error:&error];
    XCTAssertNotNil(aliceStore, @"Failed to create Alice's actor store: %@", error);

    NSString *bobDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"actorstore_%@.db", bobDID]];
    PDSActorStore *bobStore = [PDSActorStore storeWithDid:bobDID dbPath:bobDbPath error:&error];
    XCTAssertNotNil(bobStore, @"Failed to create Bob's actor store: %@", error);

    NSString *charlieDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"actorstore_%@.db", charlieDID]];
    PDSActorStore *charlieStore = [PDSActorStore storeWithDid:charlieDID dbPath:charlieDbPath error:&error];
    XCTAssertNotNil(charlieStore, @"Failed to create Charlie's actor store: %@", error);

    // Verify each store has the correct schema by checking table existence
    // Since we can't easily query sqlite_master from sqlite3*, we'll verify by attempting operations that require the schema
    NSArray<NSString *> *expectedTables = @[@"repo_root", @"records", @"ipld_blocks", @"accounts", @"invite_codes"];

    // Test that basic operations work, which implies schema is correct
    for (PDSActorStore *store in @[aliceStore, bobStore, charlieStore]) {
        // Try to get a non-existent record - should succeed (no error) but return nil
        __block PDSDatabaseRecord *testRecord = nil;
        [store readWithBlock:^(id<PDSActorStoreReader> reader) {
            testRecord = [reader getRecord:@"at://did:plc:test/nonexistent" forDid:@"did:plc:test" error:&error];
        } error:&error];
        XCTAssertNil(error, @"Schema should allow record queries without error");
        XCTAssertNil(testRecord, @"Non-existent record should return nil");

        // Try to get record count - should succeed
        __block NSInteger recordCount = -1;
        [store readWithBlock:^(id<PDSActorStoreReader> reader) {
            recordCount = [reader getRecordCountForDid:@"did:plc:test" collection:nil error:&error];
        } error:&error];
        XCTAssertNil(error, @"Schema should allow record count queries without error");
        XCTAssertEqual(recordCount, 0, @"Empty store should have 0 records");
    }

    // Verify schema-specific features work correctly for each tenant
    // Test record operations
    PDSDatabaseRecord *aliceRecord = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:aliceDID
                                                                                         collection:@"app.bsky.feed.post"
                                                                                              rkey:@"migration-test"];

    [aliceStore transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
        [transactor putRecord:aliceRecord forDid:aliceDID error:&error];
        XCTAssertNil(error, @"Failed to put record in Alice's migrated store: %@", error);
    } error:&error];
    XCTAssertNil(error, @"Failed to commit Alice's transaction: %@", error);

    // Verify the record was stored correctly
    __block PDSDatabaseRecord *fetchedAliceRecord = nil;
    [aliceStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        fetchedAliceRecord = [reader getRecord:aliceRecord.uri forDid:aliceDID error:&error];
    } error:&error];
    XCTAssertNotNil(fetchedAliceRecord, @"Record should be retrievable from Alice's migrated store");
    XCTAssertEqualObjects(fetchedAliceRecord.uri, aliceRecord.uri);

    // Test block operations
    PDSDatabaseBlock *bobBlock = [PDSDatabaseIntegrationTestUtilities createTestBlockWithRepoDID:bobDID];

    [bobStore transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
        [transactor putBlock:bobBlock forDid:bobDID error:&error];
        XCTAssertNil(error, @"Failed to put block in Bob's migrated store: %@", error);
    } error:&error];
    XCTAssertNil(error, @"Failed to commit Bob's transaction: %@", error);

    // Verify the block was stored correctly
    __block NSData *fetchedBobBlock = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        fetchedBobBlock = [reader getBlockForCID:bobBlock.cid forDid:bobDID error:&error];
    } error:&error];
    XCTAssertNotNil(fetchedBobBlock, @"Block should be retrievable from Bob's migrated store");
    XCTAssertEqualObjects(fetchedBobBlock, bobBlock.blockData);

    // Test account operations
    PDSDatabaseAccount *charlieAccount = [PDSDatabaseIntegrationTestUtilities createTestAccountWithDID:charlieDID handle:@"charlie.test"];

    [charlieStore transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
        [transactor createAccount:charlieAccount error:&error];
        XCTAssertNil(error, @"Failed to create account in Charlie's migrated store: %@", error);
    } error:&error];
    XCTAssertNil(error, @"Failed to commit Charlie's transaction: %@", error);

    // Verify the account was stored correctly
    __block PDSDatabaseAccount *fetchedCharlieAccount = nil;
    [charlieStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        fetchedCharlieAccount = [reader getAccountForDid:charlieDID error:&error];
    } error:&error];
    XCTAssertNotNil(fetchedCharlieAccount, @"Account should be retrievable from Charlie's migrated store");
    XCTAssertEqualObjects(fetchedCharlieAccount.did, charlieAccount.did);
    XCTAssertEqualObjects(fetchedCharlieAccount.handle, charlieAccount.handle);

    // Verify tenant isolation still holds after migrations
    // Alice's record should not be in Bob's store
    __block PDSDatabaseRecord *bobAccessingAliceRecord = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader) {
        bobAccessingAliceRecord = [reader getRecord:aliceRecord.uri forDid:aliceDID error:&error];
    } error:&error];
    XCTAssertNil(bobAccessingAliceRecord, @"Alice's record should NOT be accessible from Bob's store after migration");

    // Clean up
    [aliceStore close];
    [bobStore close];
    [charlieStore close];

    // Remove test database files
    [[NSFileManager defaultManager] removeItemAtPath:aliceDbPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:bobDbPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:charlieDbPath error:nil];
}

@end