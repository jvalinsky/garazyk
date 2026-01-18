/*!
 @file PDSAdminController.h

 @abstract Administrative operations controller for the PDS.

 @discussion PDSAdminController centralizes all administrative operations
 including account management, moderation, and labeling. This extraction
 from PDSController improves separation of concerns and testability.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;
@class PDSDatabase;
@protocol PDSAccountService;

/*!
 @protocol PDSAdminController

 @abstract Protocol defining the admin controller public interface.

 @discussion Provides administrative operations for account management,
 moderation actions, and content labeling.
 */
@protocol PDSAdminController <NSObject>

#pragma mark - Account Administration

/*!
 @method getAllAccountsWithError:

 @abstract Retrieves all accounts in the PDS.

 @param error On return, contains an error if the operation failed.
 @return Array of account dictionaries, or nil on failure.
 */
- (nullable NSArray *)getAllAccountsWithError:(NSError **)error;

/*!
 @method takeDownAccount:reason:error:

 @abstract Takes down an account for policy violations.

 @param did The DID of the account to take down.
 @param reason The reason for the takedown.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
- (BOOL)takeDownAccount:(NSString *)did reason:(NSString *)reason error:(NSError **)error;

/*!
 @method reinstateAccount:error:

 @abstract Reinstates a previously taken down account.

 @param did The DID of the account to reinstate.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error;

/*!
 @method isAccountTakedownActive:error:

 @abstract Checks if an account is currently taken down.

 @param did The DID of the account to check.
 @param error On return, contains an error if the operation failed.
 @return YES if the account is taken down, NO otherwise.
 */
- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error;

#pragma mark - Moderation

/*!
 @method moderateAccount:error:

 @abstract Applies moderation action to an account.

 @param params Dictionary containing moderation parameters.
 @param error On return, contains an error if the operation failed.
 @return Result dictionary with moderation status.
 */
- (NSDictionary *)moderateAccount:(NSDictionary *)params error:(NSError **)error;

/*!
 @method moderateRecord:error:

 @abstract Applies moderation action to a record.

 @param params Dictionary containing moderation parameters.
 @param error On return, contains an error if the operation failed.
 @return Result dictionary with moderation status.
 */
- (NSDictionary *)moderateRecord:(NSDictionary *)params error:(NSError **)error;

#pragma mark - Labeling

/*!
 @method createLabel:error:

 @abstract Creates a new label on content.

 @param params Dictionary containing label parameters (src, uri, val, cts).
 @param error On return, contains an error if the operation failed.
 @return Dictionary with the created label, or nil on failure.
 */
- (nullable NSDictionary *)createLabel:(NSDictionary *)params error:(NSError **)error;

/*!
 @method getLabels:error:

 @abstract Retrieves labels matching the given criteria.

 @param params Dictionary containing query parameters (uriPatterns, sources, limit, cursor).
 @param error On return, contains an error if the operation failed.
 @return Dictionary with labels array and cursor, or nil on failure.
 */
- (nullable NSDictionary *)getLabels:(NSDictionary *)params error:(NSError **)error;

@end

/*!
 @class PDSAdminController

 @abstract Implementation of administrative operations for the PDS.

 @discussion Provides administrative capabilities including account takedowns,
 moderation actions, and content labeling. Requires service databases for
 persistence and optionally an account service for account lookups.

 @code
 PDSAdminController *admin = [[PDSAdminController alloc] initWithServiceDatabases:databases
                                                                   accountService:accountService];
 
 // Take down an account
 NSError *error = nil;
 [admin takeDownAccount:@"did:plc:abc123" reason:@"TOS violation" error:&error];
 
 // Create a label
 NSDictionary *label = [admin createLabel:@{@"uri": @"at://...", @"val": @"spam"} error:&error];
 @endcode
 */
@interface PDSAdminController : NSObject <PDSAdminController>

/*! Service databases for persistence operations. */
@property (nonatomic, strong, readonly) PDSServiceDatabases *serviceDatabases;

/*! Account service for account lookups (optional). */
@property (nonatomic, strong, readonly, nullable) id<PDSAccountService> accountService;

/*!
 @method initWithServiceDatabases:accountService:

 @abstract Initializes the admin controller with dependencies.

 @param serviceDatabases The service databases for persistence.
 @param accountService The account service for account operations (may be nil).
 @return An initialized admin controller.
 */
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                          accountService:(nullable id<PDSAccountService>)accountService NS_DESIGNATED_INITIALIZER;

/*!
 @method initWithServiceDatabases:

 @abstract Initializes the admin controller with just service databases.

 @param serviceDatabases The service databases for persistence.
 @return An initialized admin controller.
 */
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END