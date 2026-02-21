#import "PDSDatabaseTestFixture.h"

NS_ASSUME_NONNULL_BEGIN

/**
 @class PDSSchemaValidationTestFixture

 @abstract Test fixture for database schema validation.

 @discussion Provides utilities for validating database schemas,
 including table structure, indexes, constraints, and data integrity.
 */
@interface PDSSchemaValidationTestFixture : PDSDatabaseTestFixture

@property (nonatomic, readwrite, nullable) PDSDatabase *database;

/**
 @method validateSchemaWithError:

 @abstract Validates the complete database schema.

 @discussion Checks all tables, columns, indexes, constraints, and foreign keys
 against the expected schema definition.

 @param error On return, contains an error if validation failed.
 @return YES if schema is valid, NO otherwise.
 */
- (BOOL)validateSchemaWithError:(NSError **)error;

/**
 @method validateTable:expectedColumns:error:

 @abstract Validates a specific table's structure.

 @param tableName The name of the table to validate.
 @param expectedColumns Dictionary mapping column names to expected types.
 @param error On return, contains an error if validation failed.
 @return YES if table structure is valid, NO otherwise.
 */
- (BOOL)validateTable:(NSString *)tableName
      expectedColumns:(NSDictionary<NSString *, NSString *> *)expectedColumns
                error:(NSError **)error;

/**
 @method validateConstraintsWithError:

 @abstract Validates database constraints.

 @discussion Checks primary keys, foreign keys, unique constraints, and check constraints.

 @param error On return, contains an error if validation failed.
 @return YES if all constraints are valid, NO otherwise.
 */
- (BOOL)validateConstraintsWithError:(NSError **)error;

/**
 @method validateIndexesWithError:

 @abstract Validates database indexes.

 @discussion Checks that expected indexes exist and are properly configured.

 @param error On return, contains an error if validation failed.
 @return YES if all indexes are valid, NO otherwise.
 */
- (BOOL)validateIndexesWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
