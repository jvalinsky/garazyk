#import "PDSDatabasePoolTestFixture.h"

NS_ASSUME_NONNULL_BEGIN

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

NS_ASSUME_NONNULL_END
