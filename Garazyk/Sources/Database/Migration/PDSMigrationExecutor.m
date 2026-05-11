// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSMigrationExecutor.h"
#import "PDSDatabaseMigration.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"

@implementation PDSMigrationExecutor

- (NSInteger)currentVersionOfDatabase:(PDSDatabase *)database error:(NSError **)error {
    // Query MAX(version) from schema_version table
    NSString *sql = @"SELECT MAX(version) as max_version FROM schema_version";

    NSError *queryError = nil;
    NSArray *result = [database executeParameterizedQuery:sql params:@[] error:&queryError];
    
    if (queryError || !result) {
        // Table doesn't exist yet — create it and return version 0
        NSString *createSQL = @"CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY, description TEXT)";
        NSError *createError = nil;
        if (![database executeParameterizedUpdate:createSQL params:@[] error:&createError]) {
            if (error) *error = createError;
            return 0;
        }
        return 0; // Fresh database, no migrations applied
    }
    
    if (result.count == 0) {
        return 0;
    }

    NSNumber *version = result[0][@"max_version"];
    return version ? version.integerValue : 0;
}

- (BOOL)executePendingMigrationsOnDatabase:(PDSDatabase *)database
                                migrations:(NSArray<id<PDSDatabaseMigration>> *)migrations
                                     error:(NSError **)error {
    // Get current schema version
    NSInteger currentVersion = [self currentVersionOfDatabase:database error:error];
    // currentVersionOfDatabase: creates schema_version table if missing,
    // so we only fail if the error is set after that.
    if (error && *error) {
        PDS_LOG_DB_ERROR(@"Failed to get current schema version: %@", *error);
        return NO;
    }

    // Sort migrations by version
    NSArray *sorted = [migrations sortedArrayUsingComparator:^NSComparisonResult(id<PDSDatabaseMigration> m1, id<PDSDatabaseMigration> m2) {
        return [@(m1.version) compare:@(m2.version)];
    }];

    // Execute pending migrations in transaction
    __block BOOL success = YES;
    [database transactWithBlock:^(NSError **txError) {
        for (id<PDSDatabaseMigration> migration in sorted) {
            if (migration.version <= currentVersion) {
                // Already applied
                continue;
            }

            PDS_LOG_DB_INFO(@"Applying migration %ld: %@", (long)migration.version, migration.description);

            if (![migration applyToDatabase:database error:txError]) {
                PDS_LOG_DB_ERROR(@"Migration %ld failed: %@", (long)migration.version, *txError);
                success = NO;
                return;
            }

            // Record migration in schema_version table
            NSString *insertSQL = @"INSERT INTO schema_version (version, description) VALUES (?, ?)";
            if (![database executeParameterizedUpdate:insertSQL params:@[@(migration.version), migration.description] error:txError]) {
                PDS_LOG_DB_ERROR(@"Failed to record migration %ld: %@", (long)migration.version, *txError);
                success = NO;
                return;
            }

            PDS_LOG_DB_INFO(@"Migration %ld applied successfully", (long)migration.version);
        }
    } error:error];

    return success;
}

@end
