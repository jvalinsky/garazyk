// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif
#import "../../Sources/PLC/PLCOperation.h"
#import "../../Sources/PLC/PLCMockStore.h"
#import "../../Sources/PLC/PLCPersistentStore.h"
#import <sqlite3.h>

@interface PLCStoreTests : XCTestCase
@property (nonatomic, copy) NSString *testDbPath;
@end

@implementation PLCStoreTests

- (void)setUp {
    [super setUp];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.testDbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"plc_test_%@.db", uuid]];
}

- (void)tearDown {
    if (self.testDbPath) {
        [[NSFileManager defaultManager] removeItemAtPath:self.testDbPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[self.testDbPath stringByAppendingString:@"-wal"] error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[self.testDbPath stringByAppendingString:@"-shm"] error:nil];
    }
    [super tearDown];
}

- (void)testPersistentStoreOpen {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    
    XCTAssertNotNil(store);
    XCTAssertNil(error);
    XCTAssertTrue(store.isOpen);
    
    [store close];
}

- (void)testPersistentStoreAppendAndGetHistory {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store);
    
    NSString *did = @"did:plc:test1";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did;
    op1.sig = @"sig1";
    op1.prev = nil;
    op1.data = @{@"foo": @"bar"};
    
    BOOL success = [store appendOperation:op1 nullifyCIDs:@[] error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
    
    NSArray<PLCOperation *> *history = [store getHistoryForDID:did includeNullified:NO error:&error];
    XCTAssertNotNil(history);
    XCTAssertEqual(history.count, 1);
    XCTAssertEqualObjects(history[0].sig, @"sig1");
    XCTAssertEqualObjects(history[0].did, did);
    XCTAssertNotNil(history[0].data);
    
    [store close];
}

- (void)testPersistentStoreMultipleOperations {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store);
    
    NSString *did = @"did:plc:test_chain";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did;
    op1.sig = @"sig1";
    op1.prev = nil;
    op1.data = @{@"step": @"1"};
    
    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = did;
    op2.sig = @"sig2";
    op2.prev = [NSString stringWithFormat:@"prev_%@", op1.sig];
    op2.data = @{@"step": @"2"};
    
    PLCOperation *op3 = [[PLCOperation alloc] init];
    op3.did = did;
    op3.sig = @"sig3";
    op3.prev = [NSString stringWithFormat:@"prev_%@", op2.sig];
    op3.data = @{@"step": @"3"};
    
    XCTAssertTrue([store appendOperation:op1 nullifyCIDs:@[] error:&error]);
    XCTAssertTrue([store appendOperation:op2 nullifyCIDs:@[] error:&error]);
    XCTAssertTrue([store appendOperation:op3 nullifyCIDs:@[] error:&error]);
    
    NSArray<PLCOperation *> *history = [store getHistoryForDID:did includeNullified:NO error:&error];
    XCTAssertEqual(history.count, 3);
    XCTAssertEqualObjects(history[0].sig, @"sig1");
    XCTAssertEqualObjects(history[1].sig, @"sig2");
    XCTAssertEqualObjects(history[2].sig, @"sig3");
    
    [store close];
}

- (void)testPersistentStoreSequenceExport {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store);

    NSString *did = @"did:plc:sequence_test";
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did;
    op1.sig = @"sig1";
    op1.data = @{@"type": @"create", @"prev": [NSNull null]};

    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = did;
    op2.sig = @"sig2";
    op2.data = @{@"type": @"create", @"prev": [NSNull null]};

    XCTAssertTrue([store appendOperation:op1 nullifyCIDs:@[] error:&error]);
    XCTAssertTrue([store appendOperation:op2 nullifyCIDs:@[] error:&error]);
    XCTAssertEqualObjects(op1.sequence, @1);
    XCTAssertEqualObjects(op2.sequence, @2);

    NSArray<PLCOperation *> *exported = [store exportOperationsAfterSequence:@0 count:10 error:&error];
    XCTAssertEqual(exported.count, 2);
    XCTAssertEqualObjects(exported[0].sequence, @1);
    XCTAssertEqualObjects(exported[1].sequence, @2);

    NSArray<PLCOperation *> *afterFirst = [store exportOperationsAfterSequence:@1 count:10 error:&error];
    XCTAssertEqual(afterFirst.count, 1);
    XCTAssertEqualObjects(afterFirst[0].sequence, @2);

    [store close];
}

- (void)testPersistentStoreMultipleDIDs {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store);
    
    NSString *did1 = @"did:plc:test_a";
    NSString *did2 = @"did:plc:test_b";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did1;
    op1.sig = @"sig_a";
    op1.data = @{};
    
    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = did2;
    op2.sig = @"sig_b";
    op2.data = @{};
    
    [store appendOperation:op1 nullifyCIDs:@[] error:nil];
    [store appendOperation:op2 nullifyCIDs:@[] error:nil];
    
    NSArray<PLCOperation *> *history1 = [store getHistoryForDID:did1 includeNullified:NO error:nil];
    NSArray<PLCOperation *> *history2 = [store getHistoryForDID:did2 includeNullified:NO error:nil];
    
    XCTAssertEqual(history1.count, 1);
    XCTAssertEqualObjects(history1[0].sig, @"sig_a");
    
    XCTAssertEqual(history2.count, 1);
    XCTAssertEqualObjects(history2[0].sig, @"sig_b");
    
    [store close];
}

- (void)testPersistentStoreEmptyHistory {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store);
    
    NSArray<PLCOperation *> *history = [store getHistoryForDID:@"did:plc:nonexistent" includeNullified:NO error:&error];
    XCTAssertNotNil(history);
    XCTAssertEqual(history.count, 0);
    
    [store close];
}

- (void)testPersistentStoreOperationCount {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store);
    
    NSString *did = @"did:plc:count_test";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did;
    op1.sig = @"sig1";
    op1.data = @{};
    
    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = did;
    op2.sig = @"sig2";
    op2.data = @{};
    
    XCTAssertEqual([store operationCountForDid:did error:&error], 0);
    
    [store appendOperation:op1 nullifyCIDs:@[] error:nil];
    XCTAssertEqual([store operationCountForDid:did error:&error], 1);
    
    [store appendOperation:op2 nullifyCIDs:@[] error:nil];
    XCTAssertEqual([store operationCountForDid:did error:&error], 2);
    
    [store close];
}

- (void)testPersistentStoreDeleteOperations {
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store);
    
    NSString *did = @"did:plc:delete_test";
    
    PLCOperation *op = [[PLCOperation alloc] init];
    op.did = did;
    op.sig = @"sig_to_delete";
    op.data = @{};
    
    [store appendOperation:op nullifyCIDs:@[] error:nil];
    XCTAssertEqual([store operationCountForDid:did error:&error], 1);
    
    BOOL deleted = [store deleteOperationsForDid:did error:&error];
    XCTAssertTrue(deleted);
    XCTAssertEqual([store operationCountForDid:did error:&error], 0);
    
    NSArray<PLCOperation *> *history = [store getHistoryForDID:did includeNullified:NO error:&error];
    XCTAssertEqual(history.count, 0);
    
    [store close];
}

- (void)testMockStoreAppendAndGetHistory {
    PLCMockStore *store = [[PLCMockStore alloc] init];
    NSString *did = @"did:plc:test1";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did;
    op1.sig = @"sig1";
    op1.data = @{@"foo": @"bar"};
    
    NSError *error = nil;
    BOOL success = [store appendOperation:op1 nullifyCIDs:@[] error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);
    
    NSArray<PLCOperation *> *history = [store getHistoryForDID:did includeNullified:NO error:&error];
    XCTAssertNotNil(history);
    XCTAssertEqual(history.count, 1);
    XCTAssertEqualObjects(history[0].sig, @"sig1");
}

- (void)testMockStoreMultipleDIDs {
    PLCMockStore *store = [[PLCMockStore alloc] init];
    NSString *did1 = @"did:plc:test1";
    NSString *did2 = @"did:plc:test2";
    
    PLCOperation *op1 = [[PLCOperation alloc] init];
    op1.did = did1;
    op1.sig = @"sig1";
    op1.data = @{};
    
    PLCOperation *op2 = [[PLCOperation alloc] init];
    op2.did = did2;
    op2.sig = @"sig2";
    op2.data = @{};
    
    [store appendOperation:op1 nullifyCIDs:@[] error:nil];
    [store appendOperation:op2 nullifyCIDs:@[] error:nil];
    
    NSArray<PLCOperation *> *history1 = [store getHistoryForDID:did1 includeNullified:NO error:nil];
    NSArray<PLCOperation *> *history2 = [store getHistoryForDID:did2 includeNullified:NO error:nil];
    
    XCTAssertEqual(history1.count, 1);
    XCTAssertEqualObjects(history1[0].sig, @"sig1");
    
    XCTAssertEqual(history2.count, 1);
    XCTAssertEqualObjects(history2[0].sig, @"sig2");
}

- (void)testMockStoreEmptyHistory {
    PLCMockStore *store = [[PLCMockStore alloc] init];
    NSArray<PLCOperation *> *history = [store getHistoryForDID:@"did:plc:nonexistent" includeNullified:NO error:nil];
    XCTAssertNotNil(history);
    XCTAssertEqual(history.count, 0);
}

#pragma mark - Schema migration atomicity

// Seeds a pre-migration plc_operations table (no cid/nullified/seq columns) with one row.
- (BOOL)seedLegacyDatabaseWithDID:(NSString *)did {
    sqlite3 *db = NULL;
    if (sqlite3_open(self.testDbPath.UTF8String, &db) != SQLITE_OK) {
        sqlite3_close(db);
        return NO;
    }
    const char *schema =
        "CREATE TABLE plc_operations ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  did TEXT NOT NULL,"
        "  prev TEXT,"
        "  sig TEXT NOT NULL,"
        "  data BLOB NOT NULL,"
        "  created_at DATETIME DEFAULT CURRENT_TIMESTAMP"
        ");";
    BOOL ok = sqlite3_exec(db, schema, NULL, NULL, NULL) == SQLITE_OK;
    if (ok) {
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(db, "INSERT INTO plc_operations (did, sig, data) VALUES (?, ?, ?);", -1, &stmt, NULL) == SQLITE_OK) {
            const char *json = "{\"legacy\":true}";
            sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, "legacy-sig", -1, SQLITE_TRANSIENT);
            sqlite3_bind_blob(stmt, 3, json, (int)strlen(json), SQLITE_TRANSIENT);
            ok = sqlite3_step(stmt) == SQLITE_DONE;
        } else {
            ok = NO;
        }
        sqlite3_finalize(stmt);
    }
    sqlite3_close(db);
    return ok;
}

- (BOOL)databaseHasTable:(NSString *)name {
    sqlite3 *db = NULL;
    if (sqlite3_open(self.testDbPath.UTF8String, &db) != SQLITE_OK) {
        sqlite3_close(db);
        return NO;
    }
    BOOL exists = NO;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?;", -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, name.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            exists = sqlite3_column_int(stmt, 0) > 0;
        }
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return exists;
}

- (void)testLegacySchemaUpgradeAddsColumnsAndBackfillsSeq {
    XCTAssertTrue([self seedLegacyDatabaseWithDID:@"did:plc:legacy"], @"seed legacy database");

    // Opening the store upgrades the legacy schema (adds cid/nullified/seq atomically) and
    // backfills seq = id, leaving the pre-existing operation readable.
    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(store, @"store should open and upgrade a legacy database: %@", error);

    NSArray<PLCOperation *> *history = [store getHistoryForDID:@"did:plc:legacy" includeNullified:NO error:&error];
    XCTAssertEqual(history.count, 1u, @"legacy op should be readable after upgrade: %@", error);
    XCTAssertEqualObjects(history.firstObject.sig, @"legacy-sig");
    XCTAssertEqualObjects(history.firstObject.sequence, @1, @"seq backfilled to id (1)");

    // Reopen: the upgrade is idempotent and converges.
    [store close];
    PLCPersistentStore *reopened = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNotNil(reopened, @"reopen converges: %@", error);
    XCTAssertEqual([reopened getHistoryForDID:@"did:plc:legacy" includeNullified:NO error:nil].count, 1u);
    [reopened close];
}

- (void)testSchemaSetupRollsBackOnInjectedIndexFailure {
    // Pre-create an object whose name collides with a schema index so CREATE INDEX fails
    // partway through setup, after CREATE TABLE plc_operations has run in the same
    // transaction. The whole setup must roll back rather than leave a half-migrated table.
    sqlite3 *db = NULL;
    XCTAssertEqual(sqlite3_open(self.testDbPath.UTF8String, &db), SQLITE_OK);
    XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE idx_plc_operations_did (x INTEGER);", NULL, NULL, NULL), SQLITE_OK);
    sqlite3_close(db);

    NSError *error = nil;
    PLCPersistentStore *store = [PLCPersistentStore storeWithPath:self.testDbPath error:&error];
    XCTAssertNil(store, @"open must fail when a schema statement conflicts");
    XCTAssertNotNil(error);

    // Atomicity: the CREATE TABLE plc_operations run earlier in the same transaction is
    // rolled back, so no half-migrated table remains; the colliding table is untouched.
    XCTAssertFalse([self databaseHasTable:@"plc_operations"], @"schema setup must roll back on failure");
    XCTAssertTrue([self databaseHasTable:@"idx_plc_operations_did"], @"pre-existing object untouched");
}

@end
