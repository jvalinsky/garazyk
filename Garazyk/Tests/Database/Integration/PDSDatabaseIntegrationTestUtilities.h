// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// Import individual test components
#import "PDSDatabaseTestFixture.h"
#import "PDSDatabasePoolTestFixture.h"
#import "PDSMultiTenantTestFixture.h"
#import "PDSMigrationTestFixture.h"
#import "PDSSchemaValidationTestFixture.h"
#import "PDSConcurrentAccessTestFixture.h"
#import "PDSDatabaseIntegrationTestSuite.h"

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

NS_ASSUME_NONNULL_END
