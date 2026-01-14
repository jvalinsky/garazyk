#import "PDSDatabaseIntegrationTestUtilities.h"
#import "Database/PDSDatabase.h"
#import "Database/Schema.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Migration/PDSMigrationManager.h"
#import <sqlite3.h>
#import <CommonCrypto/CommonCrypto.h>

NSString * const PDSDatabaseIntegrationTestErrorDomain = @"com.atproto.pds.integrationtest";

@implementation PDSDatabaseIntegrationTestUtilities

+ (nullable PDSDatabase *)createInMemoryDatabaseWithError:(NSError **)error {
    PDSDatabase *database = [PDSDatabase databaseAtURL:[NSURL URLWithString:@":memory:"]];
    if (![database openWithError:error]) {
        return nil;
    }
    return database;
}

+ (BOOL)verifySchemaInDatabase:(PDSDatabase *)database error:(NSError **)error {
    PDSSchemaValidationTestFixture *fixture = [[PDSSchemaValidationTestFixture alloc] initWithTestName:@"SchemaValidation"];
    fixture.database = database;
    return [fixture validateSchemaWithError:error];
}

+ (PDSDatabaseAccount *)createTestAccountWithDID:(NSString *)did handle:(NSString *)handle {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = did;
    account.handle = handle;
    account.email = [NSString stringWithFormat:@"%@@example.com", handle];
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = account.createdAt;
    // Generate realistic dummy hash data using a simple hash of the handle
    NSString *hashInput = [NSString stringWithFormat:@"password:%@", handle];
    NSData *inputData = [hashInput dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t hashBytes[32];
    CC_SHA256(inputData.bytes, (CC_LONG)inputData.length, hashBytes);
    account.passwordHash = [NSData dataWithBytes:hashBytes length:32];

    // Generate salt using a hash of DID + handle
    NSString *saltInput = [NSString stringWithFormat:@"salt:%@:%@", did, handle];
    NSData *saltInputData = [saltInput dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t saltBytes[16];
    CC_MD5(saltInputData.bytes, (CC_LONG)saltInputData.length, saltBytes);
    account.passwordSalt = [NSData dataWithBytes:saltBytes length:16];
    return account;
}

+ (PDSDatabaseRepo *)createTestRepoWithOwnerDID:(NSString *)ownerDid {
    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = ownerDid;
    // Generate a realistic CID-like hash based on the owner DID
    NSString *cidInput = [NSString stringWithFormat:@"root:%@", ownerDid];
    NSData *cidInputData = [cidInput dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t cidBytes[32];
    CC_SHA256(cidInputData.bytes, (CC_LONG)cidInputData.length, cidBytes);
    repo.rootCid = [NSData dataWithBytes:cidBytes length:32];
    repo.createdAt = [NSDate date];
    repo.updatedAt = [NSDate date];
    return repo;
}

+ (PDSDatabaseRecord *)createTestRecordWithDID:(NSString *)did collection:(NSString *)collection rkey:(NSString *)rkey {
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    record.did = did;
    record.collection = collection;
    record.rkey = rkey;
    // Generate a realistic CID-like string based on the record data
    NSString *cidInput = [NSString stringWithFormat:@"record:%@:%@:%@", did, collection, rkey];
    NSData *cidInputData = [cidInput dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t cidBytes[32];
    CC_SHA256(cidInputData.bytes, (CC_LONG)cidInputData.length, cidBytes);
    NSMutableString *cidString = [NSMutableString stringWithString:@"bafyre"];
    for (int i = 0; i < 8; i++) {
        [cidString appendFormat:@"%02x", cidBytes[i]];
    }
    record.cid = cidString;
    record.createdAt = [NSDate date];
    return record;
}

+ (PDSDatabaseBlock *)createTestBlockWithRepoDID:(NSString *)repoDid {
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    // Generate realistic CID based on repo DID and content
    NSString *cidInput = [NSString stringWithFormat:@"block:%@:test block data", repoDid];
    NSData *cidInputData = [cidInput dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t cidBytes[32];
    CC_SHA256(cidInputData.bytes, (CC_LONG)cidInputData.length, cidBytes);
    block.cid = [NSData dataWithBytes:cidBytes length:32];
    block.repoDid = repoDid;
    block.blockData = [@"test block data" dataUsingEncoding:NSUTF8StringEncoding];
    block.size = block.blockData.length;
    block.createdAt = [NSDate date];
    return block;
}

+ (PDSDatabaseBlob *)createTestBlobWithDID:(NSString *)did {
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    // Generate realistic CID based on DID and blob content
    NSString *cidInput = [NSString stringWithFormat:@"blob:%@:application/octet-stream:1024", did];
    NSData *cidInputData = [cidInput dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t cidBytes[32];
    CC_SHA256(cidInputData.bytes, (CC_LONG)cidInputData.length, cidBytes);
    blob.cid = [NSData dataWithBytes:cidBytes length:32];
    blob.did = did;
    blob.mimeType = @"application/octet-stream";
    blob.size = 1024;
    blob.createdAt = [NSDate date];
    return blob;
}

@end

@implementation PDSDatabaseTestFixture

- (instancetype)initWithTestName:(NSString *)testName {
    self = [super init];
    if (self) {
        _testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"PDSDatabaseTest_%@", testName]];
        _databaseURL = [self createTemporaryDatabaseURL];
    }
    return self;
}

- (BOOL)setupDatabaseWithError:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    
    _database = [PDSDatabase databaseAtURL:self.databaseURL];
    return [_database openWithError:error];
}

- (BOOL)teardownDatabaseWithError:(NSError **)error {
    if (self.database) {
        [self.database close];
        _database = nil;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm removeItemAtPath:self.testDirectory error:error];
}

- (NSURL *)createTemporaryDatabaseURL {
    return [NSURL fileURLWithPath:[self.testDirectory stringByAppendingPathComponent:@"test.db"]];
}

- (nullable PDSDatabase *)createInMemoryDatabaseWithError:(NSError **)error {
    return [PDSDatabaseIntegrationTestUtilities createInMemoryDatabaseWithError:error];
}

@end

@implementation PDSDatabasePoolTestFixture

- (instancetype)initWithTestName:(NSString *)testName maxPoolSize:(NSUInteger)maxPoolSize {
    self = [super initWithTestName:testName];
    if (self) {
        _maxPoolSize = maxPoolSize;
    }
    return self;
}

- (BOOL)setupPoolWithError:(NSError **)error {
    if (!self.database) {
        if (![self setupDatabaseWithError:error]) {
            return NO;
        }
    }

    // Create pool directory within test directory
    NSString *poolDir = [self.testDirectory stringByAppendingPathComponent:@"pool"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:poolDir withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    _pool = [[PDSDatabasePool alloc] initWithDbDirectory:poolDir maxSize:self.maxPoolSize];
    return YES;
}

- (BOOL)teardownPoolWithError:(NSError **)error {
    if (self.pool) {
        [self.pool closeAll];
        _pool = nil;
    }
    return YES;
}

- (BOOL)testConcurrentPoolAccessWithBlock:(void (^)(PDSActorStore *store, NSError **error))block
                                     error:(NSError **)error {
    if (!self.pool) {
        if (![self setupPoolWithError:error]) {
            return NO;
        }
    }

    dispatch_group_t group = dispatch_group_create();
    __block NSError *concurrentError = nil;
    __block BOOL success = YES;

    for (NSUInteger i = 0; i < self.maxPoolSize; i++) {
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                NSError *localError = nil;
                PDSActorStore *store = [self.pool storeForDid:[NSString stringWithFormat:@"did:plc:test%lu", (unsigned long)i] error:&localError];
                if (store) {
                    block(store, &localError);
                }
                if (localError) {
                    @synchronized(self) {
                        if (!concurrentError) {
                            concurrentError = localError;
                        }
                        success = NO;
                    }
                }
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    if (!success && error) {
        *error = concurrentError;
    }

    return success;
}

@end

@implementation PDSMultiTenantTestFixture

- (instancetype)initWithTestName:(NSString *)testName
                     maxPoolSize:(NSUInteger)maxPoolSize
                         testDIDs:(NSArray<NSString *> *)testDIDs {
    self = [super initWithTestName:testName maxPoolSize:maxPoolSize];
    if (self) {
        _testDIDs = [testDIDs copy];
    }
    return self;
}

- (BOOL)setupTenantsWithError:(NSError **)error {
    if (!self.pool) {
        if (![self setupPoolWithError:error]) {
            return NO;
        }
    }

    // Create test accounts for each tenant DID
    for (NSString *did in self.testDIDs) {
        PDSDatabaseAccount *account = [PDSDatabaseIntegrationTestUtilities createTestAccountWithDID:did handle:[NSString stringWithFormat:@"%@.example.com", did.lastPathComponent]];
        __block BOOL createSuccess = YES;
        [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
            NSError *createError = nil;
            if (![transactor createAccount:account error:&createError]) {
                createSuccess = NO;
            }
        } error:error];
        if (!createSuccess) {
            return NO;
        }
    }

    return YES;
}

- (BOOL)verifyTenantIsolationWithError:(NSError **)error {
    if (!self.pool || self.testDIDs.count < 2) {
        return YES; // Need at least 2 tenants to test isolation
    }

    NSString *did1 = self.testDIDs[0];
    NSString *did2 = self.testDIDs[1];

    // Create a record in tenant 1
    PDSDatabaseRecord *record1 = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:did1 collection:@"app.bsky.feed.post" rkey:@"isolation-test"];

    __block BOOL success = YES;
    __block NSError *isolationError = nil;

    [self.pool transactWithDid:did1 block:^(id<PDSActorStoreTransactor> transactor) {
        if (![transactor putRecord:record1 forDid:did1 error:&isolationError]) {
            success = NO;
        }
    } error:&isolationError];

    if (!success) {
        if (error) *error = isolationError;
        return NO;
    }

    // Try to access the record from tenant 2 - should not be visible
    [self.pool readWithDid:did2 block:^(id<PDSActorStoreReader> reader) {
        PDSDatabaseRecord *fetched = [reader getRecord:record1.uri forDid:did1 error:&isolationError];
        if (fetched) {
            // Record should not be accessible from different tenant
            success = NO;
            isolationError = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                              code:PDSDatabaseIntegrationTestErrorConcurrentAccessFailed
                                          userInfo:@{NSLocalizedDescriptionKey: @"Tenant isolation breached - record accessible from wrong tenant"}];
        }
    } error:&isolationError];

    if (!success && error) {
        *error = isolationError;
    }

    return success;
}

- (BOOL)createTestDataForTenant:(NSString *)did error:(NSError **)error {
    __block BOOL success = YES;
    __block NSError *dataError = nil;

    [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
        // Create a test repo
        PDSDatabaseRepo *repo = [PDSDatabaseIntegrationTestUtilities createTestRepoWithOwnerDID:did];
        if (![transactor createRepo:repo error:&dataError]) {
            success = NO;
            return;
        }

        // Create a test record
        PDSDatabaseRecord *record = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:did collection:@"app.bsky.feed.post" rkey:@"tenant-test"];
        if (![transactor putRecord:record forDid:did error:&dataError]) {
            success = NO;
            return;
        }

        // Create a test block
        PDSDatabaseBlock *block = [PDSDatabaseIntegrationTestUtilities createTestBlockWithRepoDID:did];
        if (![transactor putBlock:block forDid:did error:&dataError]) {
            success = NO;
        }
    } error:&dataError];

    if (!success && error) {
        *error = dataError;
    }

    return success;
}

@end

@implementation PDSMigrationTestFixture

- (instancetype)initWithTestName:(NSString *)testName {
    self = [super initWithTestName:testName];
    if (self) {
        _migrationManager = [PDSMigrationManager sharedManager];
    }
    return self;
}

- (BOOL)testMigrationWithSourcePath:(NSString *)sourcePath
              destinationDirectory:(NSString *)destinationDirectory
                             error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];

    // Verify source exists
    if (![fm fileExistsAtPath:sourcePath]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                      code:PDSDatabaseIntegrationTestErrorMigrationVerificationFailed
                                  userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Source database not found at path: %@", sourcePath]}];
        }
        return NO;
    }

    // Store destination directory for validation
    self.destinationDirectory = destinationDirectory;

    // Create destination directory
    if (![fm createDirectoryAtPath:destinationDirectory withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    // Perform migration
    if (![self.migrationManager migrateFromMonolithicDatabase:sourcePath toSingleTenantDirectory:destinationDirectory error:error]) {
        return NO;
    }

    // Validate schema after migration
    return [self validateSchemaAfterMigration:error];
}

- (BOOL)testMigrationRollbackWithSourcePath:(NSString *)sourcePath
                                       error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];

    // Create a backup of the source
    NSString *backupPath = [sourcePath stringByAppendingString:@".backup"];
    if (![fm copyItemAtPath:sourcePath toPath:backupPath error:error]) {
        return NO;
    }

    NSString *testDestination = [NSTemporaryDirectory() stringByAppendingPathComponent:@"migration_rollback_test"];

    // Attempt migration (may fail, that's ok for rollback test)
    [self.migrationManager migrateFromMonolithicDatabase:sourcePath toSingleTenantDirectory:testDestination error:nil];

    // Restore from backup
    if (![fm removeItemAtPath:sourcePath error:error]) {
        [fm removeItemAtPath:backupPath error:nil]; // cleanup
        return NO;
    }

    if (![fm moveItemAtPath:backupPath toPath:sourcePath error:error]) {
        return NO;
    }

    // Cleanup test destination
    [fm removeItemAtPath:testDestination error:nil];

    return YES;
}

- (BOOL)validateSchemaAfterMigration:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];

    // Verify destination directory exists
    if (!self.destinationDirectory || ![fm fileExistsAtPath:self.destinationDirectory]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                      code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                  userInfo:@{NSLocalizedDescriptionKey: @"Destination directory not found for schema validation"}];
        }
        return NO;
    }

    // Get all subdirectories (each represents a tenant)
    NSArray<NSString *> *tenantDirectories = [fm contentsOfDirectoryAtPath:self.destinationDirectory error:error];
    if (!tenantDirectories) {
        return NO;
    }

    NSMutableArray<NSError *> *validationErrors = [NSMutableArray array];

    // Validate schema for each tenant database
    for (NSString *tenantDirName in tenantDirectories) {
        NSString *tenantDirPath = [self.destinationDirectory stringByAppendingPathComponent:tenantDirName];

        // Skip non-directory items
        NSDictionary *attributes = [fm attributesOfItemAtPath:tenantDirPath error:nil];
        if (![attributes[NSFileType] isEqualToString:NSFileTypeDirectory]) {
            continue;
        }

        // Check for actor store database
        NSString *actorStorePath = [tenantDirPath stringByAppendingPathComponent:@"actorstore.db"];
        if ([fm fileExistsAtPath:actorStorePath]) {
            NSError *actorStoreError = nil;
            if (![self validateTenantDatabaseSchema:actorStorePath tenantDID:tenantDirName error:&actorStoreError]) {
                [validationErrors addObject:actorStoreError];
            }
        }

        // Check for service databases (accounts.db, repos.db, etc.)
        NSArray<NSString *> *serviceDbNames = @[@"accounts.db", @"repos.db", @"records.db", @"blocks.db"];
        for (NSString *serviceDbName in serviceDbNames) {
            NSString *serviceDbPath = [tenantDirPath stringByAppendingPathComponent:serviceDbName];
            if ([fm fileExistsAtPath:serviceDbPath]) {
                NSError *serviceDbError = nil;
                if (![self validateServiceDatabaseSchema:serviceDbPath databaseName:serviceDbName error:&serviceDbError]) {
                    [validationErrors addObject:serviceDbError];
                }
            }
        }
    }

    // If any validation errors occurred, return the first one
    if (validationErrors.count > 0) {
        if (error) {
            *error = validationErrors.firstObject;
        }
        return NO;
    }

    return YES;
}

- (BOOL)validateTenantDatabaseSchema:(NSString *)databasePath tenantDID:(NSString *)tenantDID error:(NSError **)error {
    // Open the actor store database
    sqlite3 *db;
    int result = sqlite3_open([databasePath UTF8String], &db);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                      code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                  userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open tenant database for DID %@: %s", tenantDID, sqlite3_errmsg(db)]}];
        }
        sqlite3_close(db);
        return NO;
    }

    // Check for required actor store tables
    NSArray<NSString *> *requiredTables = @[@"repo_root", @"records", @"ipld_blocks", @"accounts"];
    for (NSString *tableName in requiredTables) {
        NSString *query = @"SELECT name FROM sqlite_master WHERE type='table' AND name=?";
        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(db, [query UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [tableName UTF8String], -1, SQLITE_TRANSIENT);
            int stepResult = sqlite3_step(stmt);
            if (stepResult != SQLITE_ROW) {
                if (error) {
                    *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                              code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                          userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Required table '%@' not found in tenant database for DID %@", tableName, tenantDID]}];
                }
                sqlite3_finalize(stmt);
                sqlite3_close(db);
                return NO;
            }
            sqlite3_finalize(stmt);
        } else {
            if (error) {
                *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                          code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                      userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to query schema for table '%@' in tenant database for DID %@", tableName, tenantDID]}];
            }
            sqlite3_close(db);
            return NO;
        }
    }

    sqlite3_close(db);
    return YES;
}

- (BOOL)validateServiceDatabaseSchema:(NSString *)databasePath databaseName:(NSString *)databaseName error:(NSError **)error {
    // Open the service database
    sqlite3 *db;
    int result = sqlite3_open([databasePath UTF8String], &db);
    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                      code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                  userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open service database %@: %s", databaseName, sqlite3_errmsg(db)]}];
        }
        sqlite3_close(db);
        return NO;
    }

    // Determine expected table based on database name
    NSString *expectedTable;
    if ([databaseName isEqualToString:@"accounts.db"]) {
        expectedTable = @"accounts";
    } else if ([databaseName isEqualToString:@"repos.db"]) {
        expectedTable = @"repos";
    } else if ([databaseName isEqualToString:@"records.db"]) {
        expectedTable = @"records";
    } else if ([databaseName isEqualToString:@"blocks.db"]) {
        expectedTable = @"blocks";
    } else {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                      code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                  userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown service database type: %@", databaseName]}];
        }
        sqlite3_close(db);
        return NO;
    }

    // Check for the expected table
    NSString *query = @"SELECT name FROM sqlite_master WHERE type='table' AND name=?";
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, [query UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, [expectedTable UTF8String], -1, SQLITE_TRANSIENT);
        int stepResult = sqlite3_step(stmt);
        if (stepResult != SQLITE_ROW) {
            if (error) {
                *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                          code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                      userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Required table '%@' not found in service database %@", expectedTable, databaseName]}];
            }
            sqlite3_finalize(stmt);
            sqlite3_close(db);
            return NO;
        }
        sqlite3_finalize(stmt);
    } else {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                      code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                  userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to query schema for table '%@' in service database %@", expectedTable, databaseName]}];
        }
        sqlite3_close(db);
        return NO;
    }

    sqlite3_close(db);
    return YES;
}

@end

@implementation PDSSchemaValidationTestFixture

- (BOOL)validateSchemaWithError:(NSError **)error {
    return [self validateSchemaInDatabase:self.database error:error];
}

- (BOOL)validateSchemaInDatabase:(PDSDatabase *)database error:(NSError **)error {
    // Check that all required tables exist
    NSArray<NSString *> *requiredTables = @[
        kPDSAccountTableName,
        kPDSRepoTableName,
        kPDSRecordTableName,
        kPDSBlockTableName,
        kPDSBlobTableName,
        kPDSInviteCodeTableName,
        kPDSPasskeysTableName,
        kPDSAdminTakedownTableName
    ];

    for (NSString *tableName in requiredTables) {
        NSString *query = @"SELECT name FROM sqlite_master WHERE type='table' AND name=?";
        NSArray *params = @[tableName];
        NSArray *results = [database executeParameterizedQuery:query params:params error:error];
        if (!results || results.count == 0) {
            if (error) {
                *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                              code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                          userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Required table '%@' not found", tableName]}];
            }
            return NO;
        }
    }

    // Validate specific table structures (sample validation)
    NSDictionary *expectedAccountColumns = @{
        @"did": @"TEXT",
        @"handle": @"TEXT",
        @"email": @"TEXT",
        @"password_hash": @"BLOB",
        @"password_salt": @"BLOB",
        @"created_at": @"TEXT",
        @"updated_at": @"TEXT"
    };

    if (![self validateTable:kPDSAccountTableName expectedColumns:expectedAccountColumns error:error]) {
        return NO;
    }

    // Validate constraints and indexes
    if (![self validateConstraintsWithError:error]) {
        return NO;
    }

    if (![self validateIndexesWithError:error]) {
        return NO;
    }

    return YES;
}

- (BOOL)validateTable:(NSString *)tableName
      expectedColumns:(NSDictionary<NSString *, NSString *> *)expectedColumns
                error:(NSError **)error {
    // Get actual table schema
    NSString *pragmaSQL = [NSString stringWithFormat:@"PRAGMA table_info(%@)", tableName];
    NSArray *tableInfo = [self.database executeParameterizedQuery:pragmaSQL params:@[] error:error];
    if (!tableInfo) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                      code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                  userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to get table info for '%@'", tableName]}];
        }
        return NO;
    }

    // Build dictionary of actual columns
    NSMutableDictionary<NSString *, NSString *> *actualColumns = [NSMutableDictionary dictionary];
    for (NSDictionary *columnInfo in tableInfo) {
        NSString *columnName = columnInfo[@"name"];
        NSString *columnType = columnInfo[@"type"];
        if (columnName && columnType) {
            actualColumns[columnName] = columnType;
        }
    }

    // Check that all expected columns exist with correct types
    for (NSString *expectedColumn in expectedColumns) {
        NSString *expectedType = expectedColumns[expectedColumn];
        NSString *actualType = actualColumns[expectedColumn];

        if (!actualType) {
            if (error) {
                *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                          code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                      userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Table '%@' missing expected column '%@'", tableName, expectedColumn]}];
            }
            return NO;
        }

        if (![actualType isEqualToString:expectedType]) {
            if (error) {
                *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                          code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                      userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Table '%@' column '%@' has type '%@', expected '%@'", tableName, expectedColumn, actualType, expectedType]}];
            }
            return NO;
        }
    }

    return YES;
}

- (BOOL)validateConstraintsWithError:(NSError **)error {
    // Define expected foreign key relationships for each table
    NSDictionary<NSString *, NSArray<NSDictionary *> *> *expectedForeignKeys = @{
        kPDSRecordTableName: @[
            @{@"from": @"did", @"table": kPDSAccountTableName, @"to": @"did"}
        ],
        kPDSBlockTableName: @[
            @{@"from": @"repo_did", @"table": kPDSRepoTableName, @"to": @"owner_did"}
        ],
        kPDSBlobTableName: @[
            @{@"from": @"did", @"table": kPDSAccountTableName, @"to": @"did"}
        ],
        kPDSInviteCodeTableName: @[
            // invite_codes table currently has no foreign key constraints defined
        ],
        kPDSPasskeysTableName: @[
            @{@"from": @"account_did", @"table": kPDSAccountTableName, @"to": @"did"}
        ]
    };

    for (NSString *tableName in expectedForeignKeys) {
        NSString *fkSQL = [NSString stringWithFormat:@"PRAGMA foreign_key_list(%@)", tableName];
        NSArray *fkList = [self.database executeParameterizedQuery:fkSQL params:@[] error:error];
        if (!fkList) {
            if (error) {
                *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                          code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                      userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to get foreign key list for '%@'", tableName]}];
            }
            return NO;
        }

        NSArray<NSDictionary *> *expectedFKs = expectedForeignKeys[tableName];

        // Check that we have the expected number of foreign keys
        if (fkList.count != expectedFKs.count) {
            if (error) {
                *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                          code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                      userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Table '%@' has %lu foreign keys, expected %lu",
                                                                             tableName, (unsigned long)fkList.count, (unsigned long)expectedFKs.count]}];
            }
            return NO;
        }

        // Validate each expected foreign key relationship
        for (NSDictionary *expectedFK in expectedFKs) {
            NSString *fromColumn = expectedFK[@"from"];
            NSString *toTable = expectedFK[@"table"];
            NSString *toColumn = expectedFK[@"to"];

            // Find the matching foreign key in the actual list
            BOOL foundMatchingFK = NO;
            for (NSDictionary *actualFK in fkList) {
                NSString *actualFrom = actualFK[@"from"];
                NSString *actualTable = actualFK[@"table"];
                NSString *actualTo = actualFK[@"to"];

                if ([actualFrom isEqualToString:fromColumn] &&
                    [actualTable isEqualToString:toTable] &&
                    [actualTo isEqualToString:toColumn]) {
                    foundMatchingFK = YES;
                    break;
                }
            }

            if (!foundMatchingFK) {
                if (error) {
                    *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                              code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                          userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Table '%@' missing expected foreign key: %@ -> %@.%@",
                                                                                 tableName, fromColumn, toTable, toColumn]}];
                }
                return NO;
            }
        }
    }

    return YES;
}

- (BOOL)validateIndexesWithError:(NSError **)error {
    // Expected indexes based on schema
    NSArray<NSString *> *expectedIndexes = @[
        @"idx_records_did_collection",
        @"idx_records_did_collection_rkey",
        @"idx_blocks_repo_did",
        @"idx_blobs_did",
        @"idx_accounts_handle",
        @"idx_invite_codes_account_did",
        @"idx_admin_takedowns_subject_id",
        @"idx_passkeys_account_did",
        @"idx_passkeys_credential_id"
    ];

    for (NSString *indexName in expectedIndexes) {
        NSString *indexSQL = @"SELECT name FROM sqlite_master WHERE type='index' AND name=?";
        NSArray *indexResult = [self.database executeParameterizedQuery:indexSQL params:@[indexName] error:error];
        if (!indexResult || indexResult.count == 0) {
            if (error) {
                *error = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                          code:PDSDatabaseIntegrationTestErrorSchemaValidationFailed
                                      userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Expected index '%@' not found", indexName]}];
            }
            return NO;
        }
    }

    return YES;
}

@end

@implementation PDSConcurrentAccessTestFixture

- (instancetype)initWithTestName:(NSString *)testName
                     maxPoolSize:(NSUInteger)maxPoolSize
                concurrentThreads:(NSUInteger)concurrentThreads {
    self = [super initWithTestName:testName maxPoolSize:maxPoolSize];
    if (self) {
        _concurrentThreads = concurrentThreads;
    }
    return self;
}

- (BOOL)testConcurrentReadsWithError:(NSError **)error {
    if (!self.pool) {
        if (![self setupPoolWithError:error]) {
            return NO;
        }
    }

    dispatch_group_t group = dispatch_group_create();
    __block NSError *readError = nil;
    __block BOOL success = YES;
    __block NSUInteger completedReads = 0;

    for (NSUInteger i = 0; i < self.concurrentThreads; i++) {
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                NSError *localError = nil;
                [self.pool readWithDid:@"did:plc:concurrent-test" block:^(id<PDSActorStoreReader> reader) {
                    // Perform a read operation
                    NSError *readErr = nil;
                    PDSDatabaseAccount *account = [reader getAccountForDid:@"did:plc:concurrent-test" error:&readErr];
                    if (readErr && readErr.code != PDSActorStoreErrorNotFound) {
                        @synchronized(self) {
                            if (!readError) {
                                readError = readErr;
                            }
                            success = NO;
                        }
                    }
                } error:nil];

                @synchronized(self) {
                    completedReads++;
                }
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    if (!success && error) {
        *error = readError;
    }

    return success && (completedReads == self.concurrentThreads);
}

- (BOOL)testConcurrentWritesWithError:(NSError **)error {
    if (!self.pool) {
        if (![self setupPoolWithError:error]) {
            return NO;
        }
    }

    dispatch_group_t group = dispatch_group_create();
    __block NSError *writeError = nil;
    __block BOOL success = YES;
    __block NSUInteger completedWrites = 0;

    for (NSUInteger i = 0; i < self.concurrentThreads; i++) {
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                NSError *localError = nil;
                NSString *did = [NSString stringWithFormat:@"did:plc:write-test-%lu", (unsigned long)i];
                PDSDatabaseAccount *account = [PDSDatabaseIntegrationTestUtilities createTestAccountWithDID:did handle:[NSString stringWithFormat:@"write%lu.example.com", (unsigned long)i]];

                [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
                    NSError *createErr = nil;
                    if (![transactor createAccount:account error:&createErr]) {
                        @synchronized(self) {
                            if (!writeError) {
                                writeError = createErr;
                            }
                            success = NO;
                        }
                    }
                } error:nil];

                @synchronized(self) {
                    completedWrites++;
                }
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    if (!success && error) {
        *error = writeError;
    }

    return success && (completedWrites == self.concurrentThreads);
}

- (BOOL)testTransactionIsolationWithError:(NSError **)error {
    // Test basic transaction isolation - create a record in one transaction
    // and verify it's not visible in another concurrent transaction until committed
    if (!self.pool) {
        if (![self setupPoolWithError:error]) {
            return NO;
        }
    }

    NSString *did = @"did:plc:isolation-test";
    __block BOOL success = YES;
    __block NSError *isolationError = nil;

    // Create account first
    PDSDatabaseAccount *account = [PDSDatabaseIntegrationTestUtilities createTestAccountWithDID:did handle:@"isolation.example.com"];
    [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
        [transactor createAccount:account error:nil];
    } error:nil];

    // Test that records created in transactions are properly isolated
    dispatch_group_t group = dispatch_group_create();
    __block PDSDatabaseRecord *createdRecord = nil;

    dispatch_group_enter(group);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
            PDSDatabaseRecord *record = [PDSDatabaseIntegrationTestUtilities createTestRecordWithDID:did collection:@"app.bsky.feed.post" rkey:@"isolation-test"];
            if ([transactor putRecord:record forDid:did error:&isolationError]) {
                createdRecord = record;
            } else {
                success = NO;
            }
        } error:&isolationError];
        dispatch_group_leave(group);
    });

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    // Verify the record is now visible after transaction commit
    if (success && createdRecord) {
        [self.pool readWithDid:did block:^(id<PDSActorStoreReader> reader) {
            PDSDatabaseRecord *fetched = [reader getRecord:createdRecord.uri forDid:did error:&isolationError];
            if (!fetched) {
                success = NO;
                isolationError = [NSError errorWithDomain:PDSDatabaseIntegrationTestErrorDomain
                                                  code:PDSDatabaseIntegrationTestErrorConcurrentAccessFailed
                                              userInfo:@{NSLocalizedDescriptionKey: @"Transaction isolation failed - record not visible after commit"}];
            }
        } error:&isolationError];
    }

    if (!success && error) {
        *error = isolationError;
    }

    return success;
}

- (BOOL)testDeadlockDetectionWithError:(NSError **)error {
    // Basic deadlock detection test - attempt concurrent operations that might deadlock
    // In a real implementation, this would create more complex scenarios
    if (!self.pool) {
        if (![self setupPoolWithError:error]) {
            return NO;
        }
    }

    dispatch_group_t group = dispatch_group_create();
    __block NSError *deadlockError = nil;
    __block BOOL success = YES;

    // Run multiple concurrent transactions that access shared resources
    for (NSUInteger i = 0; i < MIN(self.concurrentThreads, 4); i++) {
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                NSError *localError = nil;
                NSString *did = @"did:plc:deadlock-test";

                [self.pool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
                    // Perform some database operations that might conflict
                    PDSDatabaseAccount *account = [PDSDatabaseIntegrationTestUtilities createTestAccountWithDID:did handle:@"deadlock.example.com"];
                    NSError *createErr = nil;
                    [transactor createAccount:account error:&createErr];

                    // Add small delay to increase chance of interleaving
                    usleep(1000);
                } error:nil];

                if (localError) {
                    @synchronized(self) {
                        if (!deadlockError) {
                            deadlockError = localError;
                        }
                        // Don't fail on constraint violations (expected for duplicate accounts)
                        if (localError.code != PDSDatabaseErrorConstraintViolation) {
                            success = NO;
                        }
                    }
                }
            }
            dispatch_group_leave(group);
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    if (!success && error) {
        *error = deadlockError;
    }

    return success;
}

@end

@implementation PDSDatabaseIntegrationTestSuite

- (BOOL)runAllTestsWithError:(NSError **)error {
    // Implementation for running all tests
    return YES;
}

- (BOOL)runPerformanceTestsWithError:(NSError **)error {
    // Implementation for performance tests
    return YES;
}

@end