#import <Foundation/Foundation.h>

@class PDSDatabase;

NS_ASSUME_NONNULL_BEGIN

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

NS_ASSUME_NONNULL_END
