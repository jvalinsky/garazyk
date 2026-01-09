#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// Forward declarations to avoid circular imports in test headers
@class PDSDatabase;
@class PDSDatabaseAccount;
@class PDSDatabaseRepo;
@class PDSDatabaseRecord;
@class PDSDatabaseBlock;
@class PDSDatabaseBlob;
@class PDSActorStore;
@class PDSDatabasePool;
@class PDSMigrationManager;

NS_ASSUME_NONNULL_BEGIN

/**
 @header PDSDatabaseIntegrationTestUtilities.h

 @abstract Integration testing utilities for ATProto PDS database components.

 @discussion This framework provides comprehensive testing utilities for database integration tests,
 including in-memory databases, multi-tenant testing, migration testing, connection pooling,
 concurrent access testing, and schema validation.

 All utilities are designed to work with the existing PDSDatabase, ActorStore, and migration architecture.
 */

extern NSString * const PDSDatabaseIntegrationTestErrorDomain;

typedef NS_ENUM(NSInteger, PDSDatabaseIntegrationTestError) {
    PDSDatabaseIntegrationTestErrorSetupFailed = 1000,
    PDSDatabaseIntegrationTestErrorTeardownFailed,
    PDSDatabaseIntegrationTestErrorConcurrentAccessFailed,
    PDSDatabaseIntegrationTestErrorMigrationVerificationFailed,
    PDSDatabaseIntegrationTestErrorSchemaValidationFailed,
};

/**
 @class PDSDatabaseIntegrationTestUtilities

 @abstract Utility class for database integration testing.

 @discussion Provides methods to create in-memory databases, generate test data,
 and verify database schema integrity for integration tests.
 */
@interface PDSDatabaseIntegrationTestUtilities : NSObject

/**
 @method createInMemoryDatabaseWithError:

 @abstract Creates an in-memory SQLite database instance.

 @discussion Creates a PDSDatabase instance using an in-memory SQLite database
 that is not persisted to disk. The database is fully initialized with schema.

 @param error On return, contains an error if the operation failed.
 @return A new PDSDatabase instance, or nil on failure.
 */
+ (nullable PDSDatabase *)createInMemoryDatabaseWithError:(NSError **)error;

/**
 @method verifySchemaInDatabase:error:

 @abstract Verifies that the database schema is correctly initialized.

 @param database The database to verify.
 @param error On return, contains an error if verification failed.
 @return YES if the schema is valid, NO otherwise.
 */
+ (BOOL)verifySchemaInDatabase:(PDSDatabase *)database error:(NSError **)error;

/**
 @method createTestAccountWithDID:handle:

 @abstract Creates a test account object with basic information.

 @param did The DID for the account.
 @param handle The handle for the account.
 @return A PDSDatabaseAccount instance with test data.
 */
+ (PDSDatabaseAccount *)createTestAccountWithDID:(NSString *)did handle:(NSString *)handle;

/**
 @method createTestRepoWithOwnerDID:

 @abstract Creates a test repository object.

 @param ownerDid The DID of the repository owner.
 @return A PDSDatabaseRepo instance with test data.
 */
+ (PDSDatabaseRepo *)createTestRepoWithOwnerDID:(NSString *)ownerDid;

/**
 @method createTestRecordWithDID:collection:rkey:

 @abstract Creates a test record object.

 @param did The DID of the repository.
 @param collection The collection namespace.
 @param rkey The record key.
 @return A PDSDatabaseRecord instance with test data.
 */
+ (PDSDatabaseRecord *)createTestRecordWithDID:(NSString *)did collection:(NSString *)collection rkey:(NSString *)rkey;

/**
 @method createTestBlockWithRepoDID:

 @abstract Creates a test block object.

 @param repoDid The DID of the repository.
 @return A PDSDatabaseBlock instance with test data.
 */
+ (PDSDatabaseBlock *)createTestBlockWithRepoDID:(NSString *)repoDid;

/**
 @method createTestBlobWithDID:

 @abstract Creates a test blob object.

 @param did The DID of the account.
 @return A PDSDatabaseBlob instance with test data.
 */
+ (PDSDatabaseBlob *)createTestBlobWithDID:(NSString *)did;

@end

/**
 @class PDSDatabaseTestFixture

 @abstract Base test fixture for database integration tests.

 @discussion Provides common setup and teardown functionality for database tests,
 including temporary directory management and database lifecycle management.
 */
@interface PDSDatabaseTestFixture : NSObject

@property (nonatomic, readonly) NSString *testDirectory;
@property (nonatomic, readonly) NSURL *databaseURL;
@property (nonatomic, readonly, nullable) PDSDatabase *database;

/**
 @method initWithTestName:

 @abstract Initializes a test fixture with a unique test name.

 @param testName The name of the test (used for directory naming).
 @return An initialized test fixture.
 */
- (instancetype)initWithTestName:(NSString *)testName;

/**
 @method setupDatabaseWithError:

 @abstract Sets up a database for testing.

 @param error On return, contains an error if setup failed.
 @return YES if setup succeeded, NO otherwise.
 */
- (BOOL)setupDatabaseWithError:(NSError **)error;

/**
 @method teardownDatabaseWithError:

 @abstract Tears down the test database and cleans up resources.

 @param error On return, contains an error if teardown failed.
 @return YES if teardown succeeded, NO otherwise.
 */
- (BOOL)teardownDatabaseWithError:(NSError **)error;

/**
 @method createTemporaryDatabaseURL

 @abstract Creates a unique temporary database URL for testing.

 @return A file URL for a temporary database.
 */
- (NSURL *)createTemporaryDatabaseURL;

/**
 @method createInMemoryDatabaseWithError:
 
 @abstract Creates an in-memory SQLite database for testing.
 
 @discussion In-memory databases are faster for unit tests and don't require cleanup.
 Use this for tests that don't need persistence across test runs.
 
 @param error On return, contains an error if creation failed.
 @return A PDSDatabase instance using an in-memory SQLite database, or nil on failure.
 */
- (nullable PDSDatabase *)createInMemoryDatabaseWithError:(NSError **)error;

@end

/**
 @class PDSDatabasePoolTestFixture

 @abstract Test fixture for database pool integration testing.

 @discussion Provides utilities for testing database connection pooling,
 including pool lifecycle management and concurrent access patterns.
 */
@interface PDSDatabasePoolTestFixture : PDSDatabaseTestFixture

@property (nonatomic, readonly, nullable) PDSDatabasePool *pool;
@property (nonatomic, readonly) NSUInteger maxPoolSize;

/**
 @method initWithTestName:maxPoolSize:

 @abstract Initializes a pool test fixture.

 @param testName The name of the test.
 @param maxPoolSize Maximum number of connections in the pool.
 @return An initialized pool test fixture.
 */
- (instancetype)initWithTestName:(NSString *)testName maxPoolSize:(NSUInteger)maxPoolSize;

/**
 @method setupPoolWithError:

 @abstract Sets up a database pool for testing.

 @param error On return, contains an error if setup failed.
 @return YES if setup succeeded, NO otherwise.
 */
- (BOOL)setupPoolWithError:(NSError **)error;

/**
 @method teardownPoolWithError:

 @abstract Tears down the test pool and cleans up resources.

 @param error On return, contains an error if teardown failed.
 @return YES if teardown succeeded, NO otherwise.
 */
- (BOOL)teardownPoolWithError:(NSError **)error;

/**
 @method testConcurrentPoolAccessWithBlock:

 @abstract Tests concurrent access to the database pool.

 @discussion Runs the provided block concurrently across multiple threads
 to test thread safety and connection pooling behavior.

 @param block The test block to execute concurrently.
 @param error On return, contains an error if the test failed.
 @return YES if the concurrent test passed, NO otherwise.
 */
- (BOOL)testConcurrentPoolAccessWithBlock:(void (^)(PDSActorStore *store, NSError **error))block
                                    error:(NSError **)error;

@end

/**
 @class PDSMultiTenantTestFixture

 @abstract Test fixture for multi-tenant database testing.

 @discussion Provides utilities for testing multi-tenant database scenarios,
 including tenant isolation, cross-tenant operations, and tenant lifecycle management.
 */
@interface PDSMultiTenantTestFixture : PDSDatabasePoolTestFixture

@property (nonatomic, readonly) NSArray<NSString *> *testDIDs;

/**
 @method initWithTestName:maxPoolSize:testDIDs:

 @abstract Initializes a multi-tenant test fixture.

 @param testName The name of the test.
 @param maxPoolSize Maximum pool size.
 @param testDIDs Array of test DID strings for multi-tenant scenarios.
 @return An initialized multi-tenant test fixture.
 */
- (instancetype)initWithTestName:(NSString *)testName
                     maxPoolSize:(NSUInteger)maxPoolSize
                         testDIDs:(NSArray<NSString *> *)testDIDs;

/**
 @method setupTenantsWithError:

 @abstract Sets up test tenants in the database.

 @param error On return, contains an error if setup failed.
 @return YES if setup succeeded, NO otherwise.
 */
- (BOOL)setupTenantsWithError:(NSError **)error;

/**
 @method verifyTenantIsolationWithError:

 @abstract Verifies that tenant data is properly isolated.

 @discussion Tests that data from one tenant cannot be accessed by another tenant.

 @param error On return, contains an error if verification failed.
 @return YES if tenant isolation is maintained, NO otherwise.
 */
- (BOOL)verifyTenantIsolationWithError:(NSError **)error;

/**
 @method createTestDataForTenant:error:

 @abstract Creates test data for a specific tenant.

 @param did The DID of the tenant.
 @param error On return, contains an error if creation failed.
 @return YES if test data was created successfully, NO otherwise.
 */
- (BOOL)createTestDataForTenant:(NSString *)did error:(NSError **)error;

@end

/**
 @class PDSMigrationTestFixture

 @abstract Test fixture for database migration testing.

 @discussion Provides utilities for testing database migrations,
 including migration execution, rollback verification, and schema validation.
 */
@interface PDSMigrationTestFixture : PDSDatabaseTestFixture

@property (nonatomic, readonly, nullable) PDSMigrationManager *migrationManager;

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

/**
 @class PDSConcurrentAccessTestFixture

 @abstract Test fixture for concurrent database access testing.

 @discussion Provides utilities for testing concurrent database operations,
 including transaction isolation, deadlock detection, and performance under load.
 */
@interface PDSConcurrentAccessTestFixture : PDSDatabasePoolTestFixture

@property (nonatomic, readonly) NSUInteger concurrentThreads;

/**
 @method initWithTestName:maxPoolSize:concurrentThreads:

 @abstract Initializes a concurrent access test fixture.

 @param testName The name of the test.
 @param maxPoolSize Maximum pool size.
 @param concurrentThreads Number of concurrent threads for testing.
 @return An initialized concurrent access test fixture.
 */
- (instancetype)initWithTestName:(NSString *)testName
                     maxPoolSize:(NSUInteger)maxPoolSize
                concurrentThreads:(NSUInteger)concurrentThreads;

/**
 @method testConcurrentReadsWithError:

 @abstract Tests concurrent read operations.

 @param error On return, contains an error if the test failed.
 @return YES if concurrent reads succeeded, NO otherwise.
 */
- (BOOL)testConcurrentReadsWithError:(NSError **)error;

/**
 @method testConcurrentWritesWithError:

 @abstract Tests concurrent write operations with proper locking.

 @param error On return, contains an error if the test failed.
 @return YES if concurrent writes succeeded, NO otherwise.
 */
- (BOOL)testConcurrentWritesWithError:(NSError **)error;

/**
 @method testTransactionIsolationWithError:

 @abstract Tests transaction isolation levels.

 @discussion Verifies that transactions provide proper isolation
 between concurrent operations.

 @param error On return, contains an error if the test failed.
 @return YES if transaction isolation is maintained, NO otherwise.
 */
- (BOOL)testTransactionIsolationWithError:(NSError **)error;

/**
 @method testDeadlockDetectionWithError:

 @abstract Tests deadlock detection and resolution.

 @param error On return, contains an error if the test failed.
 @return YES if deadlocks are properly detected and resolved, NO otherwise.
 */
- (BOOL)testDeadlockDetectionWithError:(NSError **)error;

@end

/**
 @class PDSDatabaseIntegrationTestSuite

 @abstract Comprehensive integration test suite for database components.

 @discussion Runs a full suite of database integration tests including
 all fixtures and utilities provided by this framework.
 */
@interface PDSDatabaseIntegrationTestSuite : NSObject

/**
 @method runAllTestsWithError:

 @abstract Runs the complete database integration test suite.

 @discussion Executes all database integration tests in sequence,
 providing comprehensive coverage of database functionality.

 @param error On return, contains an error if any test failed.
 @return YES if all tests passed, NO otherwise.
 */
- (BOOL)runAllTestsWithError:(NSError **)error;

/**
 @method runPerformanceTestsWithError:

 @abstract Runs performance-focused database integration tests.

 @discussion Tests database performance under various load conditions,
 including concurrent access patterns and large dataset operations.

 @param error On return, contains an error if any test failed.
 @return YES if all performance tests passed, NO otherwise.
 */
- (BOOL)runPerformanceTestsWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END