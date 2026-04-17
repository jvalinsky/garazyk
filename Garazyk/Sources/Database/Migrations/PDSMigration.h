/*!
 @file PDSMigration.h

 @abstract Protocol for database schema migrations.

 @discussion Defines the interface for migration classes that transform
 database schema. Each migration has a version number, name, and up/down
 methods for/down applying and reversing the migration.

 Migrations are applied in version order and tracked in the _migrations
 table. The down method must reverse all changes made by up.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @protocol PDSMigration

 @abstract Interface for database schema migrations.

 @discussion Implementations must be immutable and provide both forward
 (up) and reverse (down) migrations. Migrations are applied in version
 order within a transaction.

 Thread-safety: Migration objects should be stateless and thread-safe.

 Example implementation:
 @code
 @interface V1InitialSchema : NSObject <PDSMigration>
 @end

 @implementation V1InitialSchema
 - (NSInteger)version { return 1; }
 - (NSString *)name { return @"initial_schema"; }
 - (BOOL)up:(sqlite3 *)db error:(NSError **)error { ... }
 - (BOOL)down:(sqlite3 *)db error:(NSError **)error { ... }
 @end
 @endcode
 */
@protocol PDSMigration <NSObject>

@required

/*!
 @property version

 @abstract Unique version number for this migration.

 @discussion Version numbers must be monotonically increasing. Migrations
 are applied in version order: 1, 2, 3, etc.

 @return Integer version number (e.g., 1, 2, 3).
 */
- (NSInteger)version;

/*!
 @property name

 @abstract Human-readable name for this migration.

 @discussion Used in logging and error messages. Should be lowercase
 with underscores (e.g., "add_rev_column").

 @return Migration name string.
 */
- (NSString *)name;

/*!
 @method up:error:

 @abstract Apply this migration to the database.

 @discussion Creates tables, adds columns, or modifies schema. Called
 within a transaction, so any error will trigger rollback.

 @param db SQLite database connection.
 @param error Error output if migration fails.
 @return YES if successful, NO on error.
 */
- (BOOL)up:(sqlite3 *)db error:(NSError **)error;

/*!
 @method down:error:

 @abstract Reverse this migration.

 @discussion Removes tables, drops columns, or reverses schema changes.
 Called within a transaction during rollback. Must fully reverse the
 changes made by the up method.

 @param db SQLite database connection.
 @param error Error output if rollback fails.
 @return YES if successful, NO on error.
 */
- (BOOL)down:(sqlite3 *)db error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
