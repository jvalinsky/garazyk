#import "PDSDatabaseMigration.h"
#import "Database/PDSDatabase.h"
#import "Database/Schema/PDSSchemaManager.h"
#import "Debug/PDSLogger.h"

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
    // We just need to ensure the schema_version table exists
    PDSSchemaManager *schemaManager = [PDSSchemaManager sharedManager];
    NSString *versionTableSQL = [schemaManager schemaVersionTableSQL];

    BOOL success = [database executeUpdate:versionTableSQL params:@[] error:error];

    if (success) {
        PDS_LOG_DB_INFO(@"Created schema_version table for migration tracking");
    } else {
        PDS_LOG_DB_ERROR(@"Failed to create schema_version table: %@", *error);
    }

    return success;
}

@end
