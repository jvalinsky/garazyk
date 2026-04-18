/*!
 @file PDSMigrationExecutor.h
 @brief Executes database migrations in version order.

 @discussion Provides functionality to execute pending migrations on
 a database, track migration versions, and handle transaction rollback
 on failure.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class PDSDatabase;
@protocol PDSDatabaseMigration;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSMigrationExecutor

 @abstract Executes database schema migrations in order.

 @discussion PDSMigrationExecutor manages the execution of migrations
 on a database. It:
 - Detects the current schema version
 - Identifies pending migrations
 - Executes them in version order within transactions
 - Records successful migrations in schema_version table
 - Rolls back on failure
 */
@interface PDSMigrationExecutor : NSObject

/*!
 @method executePendingMigrationsOnDatabase:migrations:error:

 @abstract Execute pending migrations on the given database.

 @param database The database to migrate.
 @param migrations Array of migrations sorted by version.
 @param error Output error parameter.
 @return YES if all pending migrations succeeded, NO otherwise.

 @discussion This method:
 1. Detects the current schema version
 2. Filters to migrations with version > current
 3. Executes each migration in a transaction
 4. Records the version in schema_version table
 5. Rolls back the entire transaction on any failure
 */
- (BOOL)executePendingMigrationsOnDatabase:(PDSDatabase *)database
                                migrations:(NSArray<id<PDSDatabaseMigration>> *)migrations
                                     error:(NSError **)error;

/*!
 @method currentVersionOfDatabase:error:

 @abstract Get the current schema version of a database.

 @param database The database to check.
 @param error Output error parameter.
 @return Current schema version, or 0 if no migrations have been applied.

 @discussion Returns the MAX(version) from the schema_version table.
 If the table doesn't exist or is empty, returns 0.
 */
- (NSInteger)currentVersionOfDatabase:(PDSDatabase *)database error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
