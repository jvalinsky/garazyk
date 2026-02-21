#import "PDSDatabasePoolTestFixture.h"

NS_ASSUME_NONNULL_BEGIN

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

NS_ASSUME_NONNULL_END
