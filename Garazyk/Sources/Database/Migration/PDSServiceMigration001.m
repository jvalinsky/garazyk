// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabaseMigration.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"

/*!
 @class PDSServiceMigration001
 @brief Initial migration - establishes schema version tracking.

 @discussion Migration 1 creates the schema_version table used for
 tracking all future migrations. The main database schema already
 exists via CREATE IF NOT EXISTS statements in PDSSchemaManager,
 so this migration is primarily responsible for establishing the
 version tracking infrastructure.
 */
@interface PDSServiceMigration001 : NSObject <PDSDatabaseMigration>
@end

@implementation PDSServiceMigration001

- (NSInteger)version {
    return 1;
}

- (NSString *)description {
    return @"Initial schema with version tracking";
}

- (BOOL)applyToDatabase:(PDSDatabase *)database error:(NSError **)error {
    // Migration 1 is special: the main schema already exists via CREATE IF NOT EXISTS
    // Ensure the schema_version table exists
    NSString *versionTableSQL = @"CREATE TABLE IF NOT EXISTS schema_version ("
                                 "version INTEGER NOT NULL, "
                                 "description TEXT, "
                                 "applied_at INTEGER DEFAULT (strftime('%s', 'now'))"
                                 ")";

    BOOL success = [database executeParameterizedUpdate:versionTableSQL params:@[] error:error];

    if (success) {
        GZ_LOG_DB_INFO(@"Created schema_version table for migration tracking");
    } else {
        GZ_LOG_DB_ERROR(@"Failed to create schema_version table: %@", *error);
    }

    return success;
}

@end
