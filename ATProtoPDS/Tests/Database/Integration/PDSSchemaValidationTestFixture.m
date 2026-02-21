#import "PDSSchemaValidationTestFixture.h"
#import "PDSDatabaseIntegrationTestUtilities.h"
#import "Database/PDSDatabase.h"
#import "Database/Schema.h"

@implementation PDSSchemaValidationTestFixture

@dynamic database;

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
