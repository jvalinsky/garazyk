#import <XCTest/XCTest.h>
#import "Database/Integration/PDSDatabaseIntegrationTestUtilities.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"

@interface MultiTenantDatabaseTests : XCTestCase

@property (nonatomic, strong) PDSMultiTenantTestFixture *fixture;

@end

@implementation MultiTenantDatabaseTests

- (void)setUp {
    [super setUp];

    self.fixture = [[PDSMultiTenantTestFixture alloc] initWithTestName:@"MultiTenantDatabaseTests"
                                                              maxPoolSize:5
                                                                testDIDs:@[@"did:plc:alice", @"did:plc:bob", @"did:plc:charlie"]];

    __block NSError *error = nil;
    XCTAssertTrue([self.fixture setupTenantsWithError:&error], @"Failed to setup tenants: %@", error);
}

- (void)tearDown {
    __block NSError *error = nil;
    XCTAssertTrue([self.fixture teardownPoolWithError:&error], @"Failed to teardown pool: %@", error);
    self.fixture = nil;
    [super tearDown];
}

- (void)testActorStoreIsolation {
    NSString *aliceDID = @"did:plc:alice";
    NSString *bobDID = @"did:plc:bob";

    __block NSError *error = nil;

    PDSDatabaseRecord *aliceRecord = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:aliceDID
                                                                                         collection:@"app.bsky.feed.post"
                                                                                              rkey:@"alice-post-1"];
    PDSDatabaseBlock *aliceBlock = [PDSDatabaseIntegrationTestUtilities createTestBlockWithRepoDID:aliceDID];

    NSString *aliceDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"actorstore_%@.db", aliceDID]];
    PDSActorStore *aliceStore = [PDSActorStore storeWithDid:aliceDID dbPath:aliceDbPath error:&error];
    XCTAssertNotNil(aliceStore, @"Failed to create Alice's actor store: %@", error);

    [aliceStore transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        [transactor putRecord:aliceRecord forDid:aliceDID error:innerError];
        if (*innerError) return;
        [transactor putBlock:aliceBlock forDid:aliceDID error:innerError];
    } error:&error];
    XCTAssertNil(error, @"Failed to commit Alice's transaction: %@", error);

    NSString *bobDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"actorstore_%@.db", bobDID]];
    PDSActorStore *bobStore = [PDSActorStore storeWithDid:bobDID dbPath:bobDbPath error:&error];
    XCTAssertNotNil(bobStore, @"Failed to create Bob's actor store: %@", error);

    __block PDSDatabaseRecord *fetchedAliceRecord = nil;
    [aliceStore readWithBlock:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        fetchedAliceRecord = [reader getRecord:aliceRecord.uri forDid:aliceDID error:innerError];
    } error:&error];
    XCTAssertNotNil(fetchedAliceRecord, @"Alice's record should be found in her store");
    XCTAssertEqualObjects(fetchedAliceRecord.uri, aliceRecord.uri);

    __block PDSDatabaseRecord *bobFetchedAliceRecord = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        bobFetchedAliceRecord = [reader getRecord:aliceRecord.uri forDid:aliceDID error:innerError];
    } error:&error];
    XCTAssertNil(bobFetchedAliceRecord, @"Alice's record should NOT be found in Bob's store");

    __block NSArray<PDSDatabaseRecord *> *bobRecords = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        bobRecords = [reader listRecordsForDid:bobDID collection:nil limit:100 offset:0 error:innerError];
    } error:&error];
    XCTAssertEqual(bobRecords.count, 0, @"Bob's store should have no records");

    [aliceStore close];
    [bobStore close];

    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:aliceDbPath error:&error], @"Failed to remove Alice's test database: %@", error);
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:bobDbPath error:&error], @"Failed to remove Bob's test database: %@", error);
}

- (void)testCrossTenantDataProtection {
    NSString *aliceDID = @"did:plc:alice";
    NSString *bobDID = @"did:plc:bob";

    __block NSError *error = nil;

    PDSDatabaseRecord *aliceRecord = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:aliceDID
                                                                                         collection:@"app.bsky.feed.post"
                                                                                              rkey:@"alice-post-1"];
    PDSDatabaseRecord *bobRecord = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:bobDID
                                                                                       collection:@"app.bsky.feed.post"
                                                                                            rkey:@"bob-post-1"];

    PDSDatabaseBlock *aliceBlock = [PDSDatabaseIntegrationTestUtilities createTestBlockWithRepoDID:aliceDID];
    PDSDatabaseBlock *bobBlock = [PDSDatabaseIntegrationTestUtilities createTestBlockWithRepoDID:bobDID];

    NSString *aliceDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"actorstore_%@.db", aliceDID]];
    PDSActorStore *aliceStore = [PDSActorStore storeWithDid:aliceDID dbPath:aliceDbPath error:&error];
    XCTAssertNotNil(aliceStore, @"Failed to create Alice's actor store: %@", error);

    NSString *bobDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"actorstore_%@.db", bobDID]];
    PDSActorStore *bobStore = [PDSActorStore storeWithDid:bobDID dbPath:bobDbPath error:&error];
    XCTAssertNotNil(bobStore, @"Failed to create Bob's actor store: %@", error);

    [aliceStore transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        [transactor putRecord:aliceRecord forDid:aliceDID error:innerError];
        if (*innerError) return;
        [transactor putBlock:aliceBlock forDid:aliceDID error:innerError];
    } error:&error];
    XCTAssertNil(error, @"Failed to commit Alice's transaction: %@", error);

    [bobStore transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        [transactor putRecord:bobRecord forDid:bobDID error:innerError];
        if (*innerError) return;
        [transactor putBlock:bobBlock forDid:bobDID error:innerError];
    } error:&error];
    XCTAssertNil(error, @"Failed to commit Bob's transaction: %@", error);

    __block PDSDatabaseRecord *aliceAccessingBobRecord = nil;
    [aliceStore readWithBlock:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        aliceAccessingBobRecord = [reader getRecord:bobRecord.uri forDid:bobDID error:innerError];
    } error:&error];
    XCTAssertNil(aliceAccessingBobRecord, @"Alice should NOT be able to access Bob's record");

    __block NSData *aliceAccessingBobBlock = nil;
    [aliceStore readWithBlock:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        aliceAccessingBobBlock = [reader getBlockForCID:bobBlock.cid forDid:bobDID error:innerError];
    } error:&error];
    XCTAssertNil(aliceAccessingBobBlock, @"Alice should NOT be able to access Bob's block");

    __block PDSDatabaseRecord *bobAccessingAliceRecord = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        bobAccessingAliceRecord = [reader getRecord:aliceRecord.uri forDid:aliceDID error:innerError];
    } error:&error];
    XCTAssertNil(bobAccessingAliceRecord, @"Bob should NOT be able to access Alice's record");

    __block NSData *bobAccessingAliceBlock = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        bobAccessingAliceBlock = [reader getBlockForCID:aliceBlock.cid forDid:aliceDID error:innerError];
    } error:&error];
    XCTAssertNil(bobAccessingAliceBlock, @"Bob should NOT be able to access Alice's block");

    __block NSArray<PDSDatabaseRecord *> *aliceRecords = nil;
    [aliceStore readWithBlock:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        aliceRecords = [reader listRecordsForDid:aliceDID collection:nil limit:100 offset:0 error:innerError];
    } error:&error];
    XCTAssertEqual(aliceRecords.count, 1, @"Alice should see only 1 record");
    XCTAssertEqualObjects(aliceRecords.firstObject.uri, aliceRecord.uri);

    __block NSArray<PDSDatabaseRecord *> *bobRecords = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        bobRecords = [reader listRecordsForDid:bobDID collection:nil limit:100 offset:0 error:innerError];
    } error:&error];
    XCTAssertEqual(bobRecords.count, 1, @"Bob should see only 1 record");
    XCTAssertEqualObjects(bobRecords.firstObject.uri, bobRecord.uri);

    [aliceStore transactWithBlock:^(id<PDSActorStoreTransactor> transactor, NSError **innerError) {
        [transactor deleteRecord:aliceRecord.uri forDid:aliceDID error:innerError];
    } error:&error];
    XCTAssertNil(error, @"Failed to commit Alice's delete transaction: %@", error);

    __block PDSDatabaseRecord *deletedAliceRecord = nil;
    [aliceStore readWithBlock:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        deletedAliceRecord = [reader getRecord:aliceRecord.uri forDid:aliceDID error:innerError];
    } error:&error];
    XCTAssertNil(deletedAliceRecord, @"Alice's record should be deleted from her store");

    __block PDSDatabaseRecord *unaffectedBobRecord = nil;
    [bobStore readWithBlock:^(id<PDSActorStoreReader> reader, NSError **innerError) {
        unaffectedBobRecord = [reader getRecord:bobRecord.uri forDid:bobDID error:innerError];
    } error:&error];
    XCTAssertNotNil(unaffectedBobRecord, @"Bob's record should still be there");
    XCTAssertEqualObjects(unaffectedBobRecord.uri, bobRecord.uri);

    [aliceStore close];
    [bobStore close];

    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:aliceDbPath error:&error], @"Failed to remove Alice's test database: %@", error);
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:bobDbPath error:&error], @"Failed to remove Bob's test database: %@", error);
}

@end
