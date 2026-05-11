// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabaseTestFixture.h"

@class PDSDatabasePool;
@class PDSActorStore;

NS_ASSUME_NONNULL_BEGIN

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

NS_ASSUME_NONNULL_END
