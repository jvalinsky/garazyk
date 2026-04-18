/*!
 @file PDSMigrationManager.h

 @abstract Database migration management system.

 @discussion Manages database schema migrations with version tracking,
 transaction safety, and rollback support. Works with any database
 using SQLite and integrates with PDSSchemaManager.

 Migration state is tracked in the _migrations table:
 - version INTEGER PRIMARY KEY
 - name TEXT NOT NULL
 - applied_at REAL NOT NULL

 Usage:
 @code
 PDSMigrationManager *manager = [[PDSMigrationManager alloc] init];
 NSError *error = nil;
 if (![manager migrateDatabase:db error:&error]) {
     NSLog(@"Migration failed: %@", error);
 }
 @endcode

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import "PDSMigration.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSMigrationManager

 @abstract Manages database schema migrations.

 @discussion PDSMigrationManager applies migrations in version order,
 tracks applied state, and supports rollback. Migrations are wrapped
 in transactions for safety.

 Thread-safety: Manager is thread-safe. Each method synchronizes on
 internal state. However, sqlite3 connections should not be shared
 across threads without proper handling.

 Fresh install vs upgrade:
 - Fresh install: Creates _migrations table, runs all pending migrations
 - Upgrade: Checks _migrations table, runs only missing migrations
 - No legacy support: Databases without _migrations table are errors
 */
@interface PDSMigrationManager : NSObject

/*!
 @method sharedManager
 
 @abstract Returns the shared migration manager instance.
 
 @return The shared PDSMigrationManager instance.
 */
+ (instancetype)sharedManager;

/*!
 @property progressBlock
 @abstract Block called with progress updates during long-running migrations.
 */
@property (nonatomic, copy, nullable) void (^progressBlock)(double progress, NSString *status);

/*!
 @property cancelBlock
 @abstract Block called periodically to check if migration should be cancelled.
 */
@property (nonatomic, copy, nullable) BOOL (^cancelBlock)(void);

#pragma mark - Initialization

/*!
 @method init

 @abstract Initialize migration manager with default migrations.

 @discussion Loads built-in migrations for service databases and
 actor stores.

 @return Initialized migration manager.
 */
- (instancetype)init;

#pragma mark - Migration Status

/*!
 @method currentVersion:

 @abstract Get the highest applied migration version.

 @param db SQLite database connection.
 @return Current schema version, or 0 if no migrations applied.
 */
- (NSInteger)currentVersion:(sqlite3 *)db;

/*!
 @method pendingMigrations:

 @abstract Get list of migrations not yet applied.

 @param db SQLite database connection.
 @return Array of PDSMigration objects sorted by version, or empty array.
 */
- (NSArray<id<PDSMigration>> *)pendingMigrations:(sqlite3 *)db;

/*!
 @method isMigrationApplied:version:

 @abstract Check if a specific migration version is applied.

 @param db SQLite database connection.
 @param version Migration version to check.
 @return YES if migration version is in _migrations table.
 */
- (BOOL)isMigrationApplied:(sqlite3 *)db version:(NSInteger)version;

#pragma mark - Migration Operations

/*!
 @method migrateDatabase:error:

 @abstract Apply all pending migrations.

 @discussion Runs pending migrations in version order, each wrapped in
 a transaction. Logs progress for each migration applied.

 @param db SQLite database connection.
 @param error Error output if migration fails.
 @return YES if all migrations succeed, NO on error.
 */
- (BOOL)migrateDatabase:(sqlite3 *)db error:(NSError **)error;

/*!
 @method migrateDatabase:toVersion:error:

 @abstract Migrate to a specific version.

 @discussion Applies migrations up to the target version. If target
 is lower than current, performs rollback to that version.

 @param db SQLite database connection.
 @param version Target schema version.
 @param error Error output if migration fails.
 @return YES if migration succeeds, NO on error.
 */
- (BOOL)migrateDatabase:(sqlite3 *)db
              toVersion:(NSInteger)version
                  error:(NSError **)error;

/*!
 @method rollbackToVersion:error:

 @abstract Rollback to a specific schema version.

 @discussion Runs down migrations from current version to target version
 (exclusive). Each rollback is wrapped in a transaction.

 @param db SQLite database connection.
 @param version Target version to rollback to (0 to rollback all).
 @param error Error output if rollback fails.
 @return YES if rollback succeeds, NO on error.
 */
- (BOOL)rollbackToVersion:(sqlite3 *)db
                 version:(NSInteger)version
                   error:(NSError **)error;

#pragma mark - Monolithic Migration

/*!
 @method migrateFromMonolithicDatabase:toSingleTenantDirectory:error:
 
 @abstract Migrates data from an old monolithic SQLite database to the new single-tenant directory structure.
 
 @param sourcePath Path to the monolithic .sqlite file.
 @param destinationDirectory Root directory for the new multi-tenant structure.
 @param error Output error parameter.
 @return YES if migration succeeded, NO otherwise.
 */
- (BOOL)migrateFromMonolithicDatabase:(NSString *)sourcePath
               toSingleTenantDirectory:(NSString *)destinationDirectory
                                 error:(NSError **)error;

/*!
 @method migrateFromMonolithicDatabaseAsync:toSingleTenantDirectory:completion:
 
 @abstract Asynchronously migrates data from a monolithic database.
 
 @param sourcePath Path to the monolithic .sqlite file.
 @param destinationDirectory Root directory for the new multi-tenant structure.
 @param completion Block called on completion.
 */
- (void)migrateFromMonolithicDatabaseAsync:(NSString *)sourcePath
                    toSingleTenantDirectory:(NSString *)destinationDirectory
                                 completion:(void (^ _Nullable)(NSError * _Nullable error))completion;

/*!
 @method estimatedMigrateTimeWithSourcePath:
 
 @abstract Estimates the time (in seconds) required to migrate the specified monolithic database.
 
 @param sourcePath Path to the monolithic .sqlite file.
 @return Estimated time in seconds.
 */
- (NSUInteger)estimatedMigrateTimeWithSourcePath:(NSString *)sourcePath;

#pragma mark - Migration Registration

/*!
 @method registerMigration:

 @abstract Register a migration class.

 @discussion Migrations must be registered before use. Built-in migrations
 are registered during init. Custom migrations can be added.

 @param migration Migration object to register.
 */
- (void)registerMigration:(id<PDSMigration>)migration;

/*!
 @method registeredMigrations

 @abstract Get all registered migrations.

 @return Array of PDSMigration objects sorted by version.
 */
- (NSArray<id<PDSMigration>> *)registeredMigrations;

@end

#pragma mark - Factory Methods

/*!
 @category PDSMigrationManager (Factory)

 @abstract Convenience factory methods for pre-configured managers.
 */
@interface PDSMigrationManager (Factory)

/*!
 @method serviceDatabaseMigrationManager

 @abstract Create migration manager for service databases.

 @discussion Pre-configured with V1 service schema migration.

 @return Migration manager for service databases.
 */
+ (instancetype)serviceDatabaseMigrationManager;

/*!
 @method actorStoreMigrationManager

 @abstract Create migration manager for actor stores.

 @discussion Pre-configured with V1 actor store schema migration.

 @return Migration manager for actor stores.
 */
+ (instancetype)actorStoreMigrationManager;

@end

#pragma mark - Error Domain

/*!
 @constant PDSMigrationErrorDomain

 @abstract Error domain for migration operations.
 */
extern NSString * const PDSMigrationErrorDomain;

/*!
 @enum PDSMigrationErrorCode

 @abstract Error codes for migration operations.
 */
typedef NS_ENUM(NSInteger, PDSMigrationErrorCode) {
    PDSMigrationErrorUnknown = -1,
    PDSMigrationErrorTransactionFailed = -2,
    PDSMigrationErrorMigrationFailed = -3,
    PDSMigrationErrorRollbackFailed = -4,
    PDSMigrationErrorInvalidVersion = -5,
    PDSMigrationErrorLegacyDatabase = -6,
    PDSMigrationErrorSourceNotFound = -7,
    PDSMigrationErrorCancelled = -8,
};

NS_ASSUME_NONNULL_END
