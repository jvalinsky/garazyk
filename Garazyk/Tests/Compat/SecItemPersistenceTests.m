// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Compat/PlatformShims/Security/SecItemLinuxStore.h"
#import "Security/PDSKeyEnvelope.h"
#import <sqlite3.h>

@interface ATProtoSecItemLinuxStore (Testing)
- (BOOL)_migrateLegacyPlaintextRows;
@end

@interface SecItemPersistenceTests : XCTestCase
@property (nonatomic, strong) ATProtoSecItemLinuxStore *store;
@end

@implementation SecItemPersistenceTests

- (void)setUp {
    [super setUp];
#ifdef __APPLE__
    // ATProtoSecItemLinuxStore is a Linux compat shim; on macOS the real
    // Security.framework SecItem* APIs are used instead.  The Linux
    // store uses global dispatch_once state that cannot be reset
    // between test runs, causing hangs on macOS.  Skip on Apple
    // platforms.
    XCTSkip(@"SecItemLinuxStore is a Linux-only compat shim");
#endif
    self.store = [[ATProtoSecItemLinuxStore alloc] init];
    for (NSString *service in @[
        @"com.test", @"com.test.encryption-at-rest", @"com.test.legacy-plaintext",
        @"com.test.pre-migration", @"com.test.persistence"
    ]) {
        [self.store deleteItemWithService:service account:@"user" error:nil];
    }
}

- (void)testAddAndRetrieveItem {
    ATProtoSecItemLinuxStore *store = [[ATProtoSecItemLinuxStore alloc] init];
    NSData *testData = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{
        (id)kSecValueData: testData,
        @"custom": @"value"
    };

    NSError *error = nil;
    BOOL success = [store addItemWithService:@"com.test"
                                    account:@"user"
                                 attributes:attributes
                                      error:&error];
    XCTAssertTrue(success);
    XCTAssertNil(error);

    NSDictionary *retrieved = [store itemWithService:@"com.test"
                                             account:@"user"
                                               error:&error];
    XCTAssertNotNil(retrieved);
    XCTAssertNil(error);
    XCTAssertEqualObjects(retrieved[(id)kSecValueData], testData);
    XCTAssertEqualObjects(retrieved[@"custom"], @"value");
}

- (void)testDuplicateItemReturnsError {
    ATProtoSecItemLinuxStore *store = [[ATProtoSecItemLinuxStore alloc] init];
    NSData *testData = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{(id)kSecValueData: testData};

    NSError *error1 = nil;
    BOOL success1 = [store addItemWithService:@"com.test"
                                     account:@"user"
                                  attributes:attributes
                                       error:&error1];
    XCTAssertTrue(success1);

    NSError *error2 = nil;
    BOOL success2 = [store addItemWithService:@"com.test"
                                     account:@"user"
                                  attributes:attributes
                                       error:&error2];
    XCTAssertFalse(success2);
    XCTAssertNotNil(error2);
}

- (void)testUpdateMergesAttributes {
    ATProtoSecItemLinuxStore *store = [[ATProtoSecItemLinuxStore alloc] init];
    NSData *originalData = [@"secret1" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *updatedData = [@"secret2" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{(id)kSecValueData: originalData};

    NSError *error = nil;
    [store addItemWithService:@"com.test"
                     account:@"user"
                  attributes:attributes
                       error:&error];

    NSDictionary *toUpdate = @{(id)kSecValueData: updatedData};
    BOOL updated = [store updateItemWithService:@"com.test"
                                       account:@"user"
                             attributesToUpdate:toUpdate
                                         error:&error];
    XCTAssertTrue(updated);

    NSDictionary *retrieved = [store itemWithService:@"com.test"
                                             account:@"user"
                                               error:&error];
    XCTAssertEqualObjects(retrieved[(id)kSecValueData], updatedData);
}

- (void)testDeleteRemovesItem {
    ATProtoSecItemLinuxStore *store = [[ATProtoSecItemLinuxStore alloc] init];
    NSData *testData = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{(id)kSecValueData: testData};

    NSError *error = nil;
    [store addItemWithService:@"com.test"
                     account:@"user"
                  attributes:attributes
                       error:&error];

    BOOL deleted = [store deleteItemWithService:@"com.test"
                                       account:@"user"
                                         error:&error];
    XCTAssertTrue(deleted);

    NSDictionary *retrieved = [store itemWithService:@"com.test"
                                             account:@"user"
                                               error:&error];
    XCTAssertNil(retrieved);
}

- (void)testDeleteNonExistentItemReturnsNotFound {
    ATProtoSecItemLinuxStore *store = [[ATProtoSecItemLinuxStore alloc] init];

    NSError *error = nil;
    BOOL deleted = [store deleteItemWithService:@"com.nonexistent"
                                       account:@"missing"
                                         error:&error];
    XCTAssertFalse(deleted);
    XCTAssertNotNil(error);
}

- (void)testMissingServiceReturnsParamError {
    ATProtoSecItemLinuxStore *store = [[ATProtoSecItemLinuxStore alloc] init];
    NSData *testData = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{(id)kSecValueData: testData};

    NSError *error = nil;
    BOOL success = [store addItemWithService:nil
                                    account:@"user"
                                 attributes:attributes
                                      error:&error];
    XCTAssertFalse(success);
    XCTAssertNotNil(error);
}

#pragma mark - Encryption at rest (workstream 01 S11 slice 4)

/// test_main.m assigns a unique scratch path before the process first opens
/// the global Linux keychain store.
- (NSString *)_rawKeychainDBPath {
    const char *path = getenv("PDS_LINUX_KEYCHAIN_DB_PATH");
    XCTAssertTrue(path != NULL, @"Linux secret-store tests must use a scratch database");
    return [NSString stringWithUTF8String:path];
}

- (void)testOnDiskFileContainsNoPlaintextSecretMaterial {
    ATProtoSecItemLinuxStore *store = [[ATProtoSecItemLinuxStore alloc] init];
    NSString *secretMarker = @"unmistakable-plaintext-marker-do-not-leak";
    NSData *testData = [secretMarker dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{(id)kSecValueData: testData, @"custom": @"also-should-not-leak-in-the-clear"};

    [store deleteItemWithService:@"com.test.encryption-at-rest" account:@"user" error:nil];

    NSError *error = nil;
    BOOL success = [store addItemWithService:@"com.test.encryption-at-rest"
                                    account:@"user"
                                 attributes:attributes
                                      error:&error];
    XCTAssertTrue(success, @"%@", error);

    NSData *rawFile = [NSData dataWithContentsOfFile:[self _rawKeychainDBPath]];
    XCTAssertNotNil(rawFile);
    NSRange found = [rawFile rangeOfData:testData options:0 range:NSMakeRange(0, rawFile.length)];
    XCTAssertEqual(found.location, (NSUInteger)NSNotFound,
                    @"Secret value bytes must not appear verbatim in the on-disk store");
    NSData *walFile = [NSData dataWithContentsOfFile:[[self _rawKeychainDBPath] stringByAppendingString:@"-wal"]];
    if (walFile) {
        XCTAssertEqual([walFile rangeOfData:testData options:0 range:NSMakeRange(0, walFile.length)].location,
                       (NSUInteger)NSNotFound,
                       @"Secret value bytes must not appear verbatim in the WAL");
    }
}

- (void)testLegacyPlaintextRowStillReadableAfterUpgrade {
    // Simulate a row written by the pre-encryption release: raw plaintext
    // PLIST bytes and raw value bytes, inserted directly via SQL, bypassing
    // the store's seal path entirely.
    NSString *legacySecret = @"legacy-plaintext-secret";
    NSDictionary *legacyAttributes = @{(id)kSecValueData: [legacySecret dataUsingEncoding:NSUTF8StringEncoding], @"custom": @"legacy-value"};
    NSError *plistError = nil;
    NSData *legacyPlist = [NSPropertyListSerialization dataWithPropertyList:legacyAttributes
                                                                       format:NSPropertyListBinaryFormat_v1_0
                                                                      options:0
                                                                        error:&plistError];
    XCTAssertNotNil(legacyPlist, @"%@", plistError);

    sqlite3 *rawDB = NULL;
    XCTAssertEqual(sqlite3_open([self _rawKeychainDBPath].UTF8String, &rawDB), SQLITE_OK);
    sqlite3_stmt *insertStmt = NULL;
    const char *insertSQL = "INSERT OR REPLACE INTO items (service, account, data, attrs) VALUES (?, ?, ?, ?)";
    XCTAssertEqual(sqlite3_prepare_v2(rawDB, insertSQL, -1, &insertStmt, NULL), SQLITE_OK);
    NSData *legacyValueData = [legacySecret dataUsingEncoding:NSUTF8StringEncoding];
    sqlite3_bind_text(insertStmt, 1, "com.test.legacy-plaintext", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(insertStmt, 2, "user", -1, SQLITE_TRANSIENT);
    sqlite3_bind_blob(insertStmt, 3, legacyValueData.bytes, (int)legacyValueData.length, SQLITE_TRANSIENT);
    sqlite3_bind_blob(insertStmt, 4, legacyPlist.bytes, (int)legacyPlist.length, SQLITE_TRANSIENT);
    XCTAssertEqual(sqlite3_step(insertStmt), SQLITE_DONE);
    sqlite3_finalize(insertStmt);
    sqlite3_close(rawDB);

    ATProtoSecItemLinuxStore *store = [[ATProtoSecItemLinuxStore alloc] init];
    NSError *error = nil;
    NSDictionary *retrieved = [store itemWithService:@"com.test.legacy-plaintext" account:@"user" error:&error];
    XCTAssertNotNil(retrieved, @"%@", error);
    XCTAssertEqualObjects(retrieved[(id)kSecValueData], legacyValueData);
    XCTAssertEqualObjects(retrieved[@"custom"], @"legacy-value");
    XCTAssertTrue([store deleteItemWithService:@"com.test.legacy-plaintext" account:@"user" error:&error], @"%@", error);
}

- (void)testMigrationRewritesLegacyPlaintextRowToSealedEnvelope {
    NSDictionary *legacyAttributes = @{(id)kSecValueData: [@"pre-migration-secret" dataUsingEncoding:NSUTF8StringEncoding]};
    NSError *plistError = nil;
    NSData *legacyPlist = [NSPropertyListSerialization dataWithPropertyList:legacyAttributes
                                                                       format:NSPropertyListBinaryFormat_v1_0
                                                                      options:0
                                                                        error:&plistError];
    XCTAssertNotNil(legacyPlist, @"%@", plistError);

    sqlite3 *rawDB = NULL;
    XCTAssertEqual(sqlite3_open([self _rawKeychainDBPath].UTF8String, &rawDB), SQLITE_OK);
    sqlite3_stmt *insertStmt = NULL;
    const char *insertSQL = "INSERT OR REPLACE INTO items (service, account, data, attrs) VALUES (?, ?, ?, ?)";
    XCTAssertEqual(sqlite3_prepare_v2(rawDB, insertSQL, -1, &insertStmt, NULL), SQLITE_OK);
    sqlite3_bind_text(insertStmt, 1, "com.test.pre-migration", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(insertStmt, 2, "user", -1, SQLITE_TRANSIENT);
    sqlite3_bind_null(insertStmt, 3);
    sqlite3_bind_blob(insertStmt, 4, legacyPlist.bytes, (int)legacyPlist.length, SQLITE_TRANSIENT);
    XCTAssertEqual(sqlite3_step(insertStmt), SQLITE_DONE);
    sqlite3_finalize(insertStmt);
    sqlite3_close(rawDB);

    ATProtoSecItemLinuxStore *store = [[ATProtoSecItemLinuxStore alloc] init];
    // The store's dispatch_once has already fired earlier in this process,
    // so invoke the migration pass directly rather than relying on a fresh
    // -init to trigger it.
    XCTAssertTrue([store _migrateLegacyPlaintextRows]);

    sqlite3 *verifyDB = NULL;
    XCTAssertEqual(sqlite3_open([self _rawKeychainDBPath].UTF8String, &verifyDB), SQLITE_OK);
    sqlite3_stmt *selectStmt = NULL;
    const char *selectSQL = "SELECT attrs FROM items WHERE service = ? AND account = ?";
    XCTAssertEqual(sqlite3_prepare_v2(verifyDB, selectSQL, -1, &selectStmt, NULL), SQLITE_OK);
    sqlite3_bind_text(selectStmt, 1, "com.test.pre-migration", -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(selectStmt, 2, "user", -1, SQLITE_TRANSIENT);
    XCTAssertEqual(sqlite3_step(selectStmt), SQLITE_ROW);
    const void *attrBytes = sqlite3_column_blob(selectStmt, 0);
    int attrLen = sqlite3_column_bytes(selectStmt, 0);
    NSData *storedAttrs = [NSData dataWithBytes:attrBytes length:attrLen];
    sqlite3_finalize(selectStmt);
    sqlite3_close(verifyDB);

    XCTAssertTrue([PDSKeyEnvelope isVersionedEnvelope:storedAttrs],
                   @"Migration should have rewritten the legacy plaintext row to a sealed envelope");

    // And it must still round-trip through the normal read path.
    NSError *readError = nil;
    NSDictionary *retrieved = [store itemWithService:@"com.test.pre-migration" account:@"user" error:&readError];
    XCTAssertNotNil(retrieved, @"%@", readError);
    XCTAssertEqualObjects(retrieved[(id)kSecValueData], [@"pre-migration-secret" dataUsingEncoding:NSUTF8StringEncoding]);

    NSData *rawFile = [NSData dataWithContentsOfFile:[self _rawKeychainDBPath]];
    NSData *legacySecret = [@"pre-migration-secret" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqual([rawFile rangeOfData:legacySecret options:0 range:NSMakeRange(0, rawFile.length)].location,
                   (NSUInteger)NSNotFound,
                   @"Migration must not leave plaintext in the main SQLite file");
    NSData *walFile = [NSData dataWithContentsOfFile:[[self _rawKeychainDBPath] stringByAppendingString:@"-wal"]];
    XCTAssertTrue(walFile.length == 0 || [walFile rangeOfData:legacySecret options:0 range:NSMakeRange(0, walFile.length)].location == NSNotFound,
                  @"Migration must not leave plaintext in the SQLite WAL");
}

- (void)testPersistenceAcrossStoreInstances {
    ATProtoSecItemLinuxStore *storeA = [[ATProtoSecItemLinuxStore alloc] init];
    NSData *testData = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{(id)kSecValueData: testData};

    NSError *error = nil;
    [storeA addItemWithService:@"com.test"
                      account:@"user"
                   attributes:attributes
                        error:&error];

    ATProtoSecItemLinuxStore *storeB = [[ATProtoSecItemLinuxStore alloc] init];
    NSDictionary *retrieved = [storeB itemWithService:@"com.test"
                                              account:@"user"
                                                error:&error];
    XCTAssertNotNil(retrieved);
    XCTAssertEqualObjects(retrieved[(id)kSecValueData], testData);
}

@end
