#import "PDSMigrationTestFixture.h"
#import "PDSDatabaseIntegrationTestUtilities.h"
#import "Database/Migrations/PDSMigrationManager.h"
#import <sqlite3.h>

@interface PDSMigrationTestFixture ()
@property (nonatomic, readwrite, nullable) PDSMigrationManager *migrationManager;
@end

@implementation PDSMigrationTestFixture

- (instancetype)initWithTestName:(NSString *)testName {
    self = [super initWithTestName:testName];
    if (self) {
        _migrationManager = [PDSMigrationManager sharedManager];
    }
    return self;
}

- (BOOL)setupDatabaseWithError:(NSError **)error {
    // Migration tests don't require a full database setup
    // Just create the test directory for temporary files
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:error];
}

- (BOOL)teardownDatabaseWithError:(NSError **)error {
    // Clean up test directory
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm removeItemAtPath:self.testDirectory error:error];
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
