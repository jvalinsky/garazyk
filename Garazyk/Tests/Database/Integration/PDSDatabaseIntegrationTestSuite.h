#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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
