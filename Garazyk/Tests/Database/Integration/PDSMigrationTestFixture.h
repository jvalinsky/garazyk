#import "PDSDatabaseTestFixture.h"

@class PDSMigrationManager;

NS_ASSUME_NONNULL_BEGIN

/**
 @class PDSMigrationTestFixture

 @abstract Test fixture for database migration testing.

 @discussion Provides utilities for testing database migrations,
 including migration execution, rollback verification, and schema validation.
 */
@interface PDSMigrationTestFixture : PDSDatabaseTestFixture

@property (nonatomic, readonly, nullable) PDSMigrationManager *migrationManager;
@property (nonatomic, strong, nullable) NSString *destinationDirectory;

/**
 @method testMigrationWithSourcePath:destinationDirectory:error:

 @abstract Tests a database migration from monolithic to multi-tenant.

 @param sourcePath Path to the source monolithic database.
 @param destinationDirectory Directory for migrated tenant databases.
 @param error On return, contains an error if the test failed.
 @return YES if migration succeeded and was verified, NO otherwise.
 */
- (BOOL)testMigrationWithSourcePath:(NSString *)sourcePath
                 destinationDirectory:(NSString *)destinationDirectory
                                error:(NSError **)error;

/**
 @method testMigrationRollbackWithSourcePath:error:

 @abstract Tests migration rollback functionality.

 @discussion Creates a backup of the source database, runs migration,
 then verifies rollback restores the original state.

 @param sourcePath Path to the source database.
 @param error On return, contains an error if the test failed.
 @return YES if rollback verification succeeded, NO otherwise.
 */
- (BOOL)testMigrationRollbackWithSourcePath:(NSString *)sourcePath
                                      error:(NSError **)error;

/**
 @method validateSchemaAfterMigration:error:

 @abstract Validates database schema after migration.

 @param error On return, contains an error if validation failed.
 @return YES if schema is valid, NO otherwise.
 */
- (BOOL)validateSchemaAfterMigration:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
