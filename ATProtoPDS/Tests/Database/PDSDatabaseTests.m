// Tests for PDSDatabase: open/close, parameterized queries, transactions, CRUD operations.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Database/PDSDatabase.h"
#import "Database/Schema.h"

@interface PDSDatabaseTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, copy) NSString *dbPath;
@end

@implementation PDSDatabaseTests

- (void)setUp {
    [super setUp];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"pds_test_%@.db", uuid]];
    NSURL *url = [NSURL fileURLWithPath:self.dbPath];
    self.db = [PDSDatabase databaseAtURL:url];
    NSError *error = nil;
    BOOL opened = [self.db openWithError:&error];
    XCTAssertTrue(opened, @"Database should open: %@", error);
    XCTAssertNil(error);
}

- (void)tearDown {
    [self.db close];
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

#pragma mark - Open/Close

- (void)testDatabaseIsOpenAfterOpen {
    XCTAssertTrue(self.db.isOpen);
}

- (void)testDatabaseIsClosedAfterClose {
    [self.db close];
    XCTAssertFalse(self.db.isOpen);
    // Re-open so tearDown doesn't fail
    [self.db openWithError:nil];
}

- (void)testDatabaseURLMatchesPath {
    XCTAssertEqualObjects(self.db.databaseURL.path, self.dbPath);
}

#pragma mark - Raw SQL / Schema Tables

- (void)testSchemaContainsAccountsTable {
    NSError *error = nil;
    NSArray *rows = [self.db executeQuery:
                     @"SELECT name FROM sqlite_master WHERE type='table' AND name='accounts'"
                                    error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(rows.count, (NSUInteger)1, @"accounts table must exist after migration");
}

- (void)testSchemaContainsReposTable {
    NSError *error = nil;
    NSArray *rows = [self.db executeQuery:
                     @"SELECT name FROM sqlite_master WHERE type='table' AND name='repos'"
                                    error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(rows.count, (NSUInteger)1, @"repos table must exist after migration");
}

- (void)testSchemaContainsRecordsTable {
    NSError *error = nil;
    NSArray *rows = [self.db executeQuery:
                     @"SELECT name FROM sqlite_master WHERE type='table' AND name='records'"
                                    error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(rows.count, (NSUInteger)1, @"records table must exist after migration");
}

- (void)testSchemaContainsBlocksTable {
    NSError *error = nil;
    NSArray *rows = [self.db executeQuery:
                     @"SELECT name FROM sqlite_master WHERE type='table' AND name='blocks'"
                                    error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(rows.count, (NSUInteger)1, @"blocks table must exist after migration");
}

- (void)testSchemaContainsJWTSigningKeysTable {
    NSError *error = nil;
    NSArray *rows = [self.db executeQuery:
                     @"SELECT name FROM sqlite_master WHERE type='table' AND name='jwt_signing_keys'"
                                    error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(rows.count, (NSUInteger)1, @"jwt_signing_keys table must exist after migration");
}

#pragma mark - Parameterized Update & Query

- (void)testParameterizedUpdateAndQuery {
    // Create a temp table for this test
    NSError *error = nil;
    BOOL ok = [self.db executeRawSQL:@"CREATE TABLE IF NOT EXISTS pds_test_kv (k TEXT PRIMARY KEY, v TEXT)"
                               error:&error];
    XCTAssertTrue(ok, @"CREATE TABLE: %@", error);

    ok = [self.db executeParameterizedUpdate:@"INSERT INTO pds_test_kv (k, v) VALUES (?, ?)"
                                      params:@[@"hello", @"world"]
                                       error:&error];
    XCTAssertTrue(ok, @"INSERT: %@", error);

    NSArray *rows = [self.db executeParameterizedQuery:@"SELECT v FROM pds_test_kv WHERE k = ?"
                                                params:@[@"hello"]
                                                 error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(rows.count, (NSUInteger)1);
    XCTAssertEqualObjects(rows[0][@"v"], @"world");

    [self.db executeRawSQL:@"DROP TABLE pds_test_kv" error:nil];
}

- (void)testParameterizedQueryReturnsEmptyArrayForNoMatch {
    NSError *error = nil;
    [self.db executeRawSQL:@"CREATE TABLE IF NOT EXISTS pds_test_empty (id INTEGER PRIMARY KEY)" error:nil];

    NSArray *rows = [self.db executeParameterizedQuery:@"SELECT * FROM pds_test_empty WHERE id = ?"
                                                params:@[@9999]
                                                 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(rows);
    XCTAssertEqual(rows.count, (NSUInteger)0);

    [self.db executeRawSQL:@"DROP TABLE pds_test_empty" error:nil];
}

#pragma mark - Transactions

- (void)testTransactionCommitPersistsData {
    NSError *error = nil;
    [self.db executeRawSQL:@"CREATE TABLE IF NOT EXISTS pds_test_txn (n INTEGER)" error:nil];

    BOOL ok = [self.db beginTransactionWithError:&error];
    XCTAssertTrue(ok, @"BEGIN: %@", error);

    ok = [self.db executeParameterizedUpdate:@"INSERT INTO pds_test_txn VALUES (?)"
                                      params:@[@42]
                                       error:&error];
    XCTAssertTrue(ok);

    ok = [self.db commitTransactionWithError:&error];
    XCTAssertTrue(ok, @"COMMIT: %@", error);

    NSArray *rows = [self.db executeQuery:@"SELECT n FROM pds_test_txn" error:&error];
    XCTAssertEqual(rows.count, (NSUInteger)1);
    XCTAssertEqualObjects(rows[0][@"n"], @42);

    [self.db executeRawSQL:@"DROP TABLE pds_test_txn" error:nil];
}

- (void)testTransactionRollbackDiscardsData {
    NSError *error = nil;
    [self.db executeRawSQL:@"CREATE TABLE IF NOT EXISTS pds_test_rollback (n INTEGER)" error:nil];

    BOOL ok = [self.db beginTransactionWithError:&error];
    XCTAssertTrue(ok);

    ok = [self.db executeParameterizedUpdate:@"INSERT INTO pds_test_rollback VALUES (?)"
                                      params:@[@99]
                                       error:&error];
    XCTAssertTrue(ok);

    ok = [self.db rollbackTransactionWithError:&error];
    XCTAssertTrue(ok, @"ROLLBACK: %@", error);

    NSArray *rows = [self.db executeQuery:@"SELECT n FROM pds_test_rollback" error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(rows.count, (NSUInteger)0, @"Rolled-back insert must not persist");

    [self.db executeRawSQL:@"DROP TABLE pds_test_rollback" error:nil];
}

#pragma mark - Account CRUD

- (PDSDatabaseAccount *)makeTestAccountWithDID:(NSString *)did {
    PDSDatabaseAccount *acct = [[PDSDatabaseAccount alloc] init];
    acct.did = did;
    acct.handle = [NSString stringWithFormat:@"%@.test", did];
    acct.email = [NSString stringWithFormat:@"%@@example.com", did];
    acct.createdAt = [[NSDate date] timeIntervalSince1970];
    acct.updatedAt = acct.createdAt;
    return acct;
}

- (void)testCreateAndGetAccountByDID {
    NSError *error = nil;
    PDSDatabaseAccount *acct = [self makeTestAccountWithDID:@"did:plc:testaccount001"];
    BOOL ok = [self.db createAccount:acct error:&error];
    XCTAssertTrue(ok, @"createAccount: %@", error);

    PDSDatabaseAccount *fetched = [self.db getAccountByDid:@"did:plc:testaccount001" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(fetched);
    XCTAssertEqualObjects(fetched.did, @"did:plc:testaccount001");
    XCTAssertEqualObjects(fetched.handle, @"did:plc:testaccount001.test");
}

- (void)testGetAccountByHandleReturnsAccount {
    NSError *error = nil;
    PDSDatabaseAccount *acct = [self makeTestAccountWithDID:@"did:plc:handletest"];
    BOOL ok = [self.db createAccount:acct error:&error];
    XCTAssertTrue(ok);

    PDSDatabaseAccount *fetched = [self.db getAccountByHandle:@"did:plc:handletest.test" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(fetched);
    XCTAssertEqualObjects(fetched.did, @"did:plc:handletest");
}

- (void)testGetAccountByNonExistentDIDReturnsNil {
    NSError *error = nil;
    PDSDatabaseAccount *fetched = [self.db getAccountByDid:@"did:plc:doesnotexist" error:&error];
    XCTAssertNil(fetched);
}

- (void)testGetAllAccountsReturnsInsertedAccounts {
    NSError *error = nil;
    [self.db createAccount:[self makeTestAccountWithDID:@"did:plc:acctA"] error:nil];
    [self.db createAccount:[self makeTestAccountWithDID:@"did:plc:acctB"] error:nil];

    NSArray<PDSDatabaseAccount *> *all = [self.db getAllAccountsWithError:&error];
    XCTAssertNil(error);
    NSUInteger found = 0;
    for (PDSDatabaseAccount *a in all) {
        if ([a.did isEqualToString:@"did:plc:acctA"] || [a.did isEqualToString:@"did:plc:acctB"]) {
            found++;
        }
    }
    XCTAssertEqual(found, (NSUInteger)2);
}

- (void)testDeleteAccountRemovesIt {
    NSError *error = nil;
    [self.db createAccount:[self makeTestAccountWithDID:@"did:plc:todelete"] error:nil];

    BOOL ok = [self.db deleteAccount:@"did:plc:todelete" error:&error];
    XCTAssertTrue(ok, @"deleteAccount: %@", error);

    PDSDatabaseAccount *fetched = [self.db getAccountByDid:@"did:plc:todelete" error:&error];
    XCTAssertNil(fetched);
}

#pragma mark - Record CRUD

- (void)testSaveAndGetRecord {
    NSError *error = nil;
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = @"at://did:plc:abc/app.bsky.feed.post/tid001";
    record.did = @"did:plc:abc";
    record.collection = @"app.bsky.feed.post";
    record.rkey = @"tid001";
    record.cid = @"bafyreifoo";
    record.createdAt = [NSDate date];

    BOOL ok = [self.db saveRecord:record error:&error];
    XCTAssertTrue(ok, @"saveRecord: %@", error);

    PDSDatabaseRecord *fetched = [self.db getRecord:@"at://did:plc:abc/app.bsky.feed.post/tid001"
                                              error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(fetched);
    XCTAssertEqualObjects(fetched.cid, @"bafyreifoo");
    XCTAssertEqualObjects(fetched.collection, @"app.bsky.feed.post");
}

- (void)testGetNonExistentRecordReturnsNil {
    NSError *error = nil;
    PDSDatabaseRecord *fetched = [self.db getRecord:@"at://did:plc:nobody/col/rkey" error:&error];
    XCTAssertNil(fetched);
}

- (void)testGetRecordsForDidAndCollection {
    NSError *error = nil;
    for (NSUInteger i = 0; i < 3; i++) {
        PDSDatabaseRecord *r = [[PDSDatabaseRecord alloc] init];
        r.did = @"did:plc:multirecord";
        r.collection = @"app.bsky.actor.profile";
        r.rkey = [NSString stringWithFormat:@"rkey%lu", (unsigned long)i];
        r.uri = [NSString stringWithFormat:@"at://did:plc:multirecord/app.bsky.actor.profile/rkey%lu",
                 (unsigned long)i];
        r.cid = @"bafytest";
        r.createdAt = [NSDate date];
        [self.db saveRecord:r error:nil];
    }

    NSArray<PDSDatabaseRecord *> *records =
        [self.db getRecordsForDid:@"did:plc:multirecord"
                       collection:@"app.bsky.actor.profile"
                            error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(records.count, (NSUInteger)3);
}

#pragma mark - Schema Constants

- (void)testSchemaVersionIsPositive {
    XCTAssertGreaterThan(kPDSDatabaseSchemaVersion, (NSInteger)0);
}

- (void)testSchemaTableNamesNonEmpty {
    XCTAssertGreaterThan(kPDSAccountTableName.length, (NSUInteger)0);
    XCTAssertGreaterThan(kPDSRepoTableName.length, (NSUInteger)0);
    XCTAssertGreaterThan(kPDSRecordTableName.length, (NSUInteger)0);
    XCTAssertGreaterThan(kPDSBlockTableName.length, (NSUInteger)0);
    XCTAssertGreaterThan(kPDSBlobTableName.length, (NSUInteger)0);
}

- (void)testSchemaCreateSQLContainsExpectedKeywords {
    XCTAssertTrue([kPDSAccountTableCreateSQL containsString:@"CREATE TABLE"],
                  @"Account CREATE SQL must contain 'CREATE TABLE'");
    XCTAssertTrue([kPDSJWTSigningKeysTableCreateSQL containsString:@"CREATE TABLE"],
                  @"JWT signing keys CREATE SQL must contain 'CREATE TABLE'");
}

@end
