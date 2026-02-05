/*!
 @file PDSAdminService.h

 @abstract Protocol for consolidated admin service operations.

 @discussion Defines the interface for all administrative operations including
 account management, moderation, labeling, and invite handling. This consolidates
 functionality previously split between AdminService and PDSAdminController.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;
@class PDSDatabasePool;
@class PDSServiceDatabases;
@protocol PDSAccountService;

/*!
 @protocol PDSAdminService

 @abstract Protocol defining the consolidated admin service public interface.

 @discussion Provides administrative operations for account management,
 moderation actions, content labeling, and invite handling.
 */
@protocol PDSAdminService <NSObject>

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

#pragma mark - Account Updates

/*!
 @method updateEmail:forAccount:error:

 @abstract Updates the email address for an account.

 @param email The new email address.
 @param did The DID of the account to update.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
- (BOOL)updateEmail:(NSString *)email forAccount:(NSString *)did error:(NSError **)error;

/*!
 @method updateAccountPassword:newPassword:error:

 @abstract Updates the password for an account.

 @param did The DID of the account to update.
 @param password The new password.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
- (BOOL)updateAccountPassword:(NSString *)did newPassword:(NSString *)password error:(NSError **)error;

/*!
 @method updateHandle:forAccount:error:

 @abstract Updates the handle for an account.

 @param handle The new handle.
 @param did The DID of the account to update.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
- (BOOL)updateHandle:(NSString *)handle forAccount:(NSString *)did error:(NSError **)error;

#pragma mark - Invite Management

/*!
 @method disableAccountInvitesForDid:error:

 @abstract Disables invite generation for an account.

 @param did The DID of the account.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
- (BOOL)disableAccountInvitesForDid:(NSString *)did error:(NSError **)error;

/*!
 @method enableAccountInvitesForDid:error:

 @abstract Enables invite generation for an account.

 @param did The DID of the account.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
- (BOOL)enableAccountInvitesForDid:(NSString *)did error:(NSError **)error;

/*!
 @method createInviteCode:error:

 @abstract Creates a new invite code.

 @param params Dictionary containing invite parameters (forAccount, usesAvailable).
 @param error On return, contains an error if the operation failed.
 @return Dictionary with the created invite code, or nil on failure.
 */
- (nullable NSDictionary *)createInviteCode:(NSDictionary *)params error:(NSError **)error;

/*!
 @method disableInviteCode:error:

 @abstract Disables an invite code.

 @param code The invite code to disable.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
- (BOOL)disableInviteCode:(NSString *)code error:(NSError **)error;

/*!
 @method disableInviteCodes:error:

 @abstract Disables global invite code generation.

 @param disabled Whether to disable invite codes.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
- (BOOL)disableInviteCodes:(BOOL)disabled error:(NSError **)error;

#pragma mark - Moderation

/*!
 @method moderateAccount:error:

 @abstract Applies moderation action to an account.

 @param params Dictionary containing moderation parameters (did, action).
 @param error On return, contains an error if the operation failed.
 @return Result dictionary with moderation status.
 */
- (NSDictionary *)moderateAccount:(NSDictionary *)params error:(NSError **)error;

/*!
 @method moderateRecord:error:

 @abstract Applies moderation action to a record.

 @param params Dictionary containing moderation parameters (uri, action).
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
 @class PDSAdminService

 @abstract Service implementation for consolidated admin operations.

 @discussion Handles all administrative operations including account management,
 moderation actions, content labeling, and invite handling. Coordinates between
 database access and business logic.
 */
@interface PDSAdminService : NSObject <PDSAdminService>

/*! Database pool for transactions. */
@property (nonatomic, strong, readonly, nullable) PDSDatabasePool *databasePool;

/*! Primary database for operations. */
@property (nonatomic, strong, readonly) PDSDatabase *database;

/*! Service databases for persistence operations. */
@property (nonatomic, strong, readonly) PDSServiceDatabases *serviceDatabases;

/*! Account service for account lookups (optional). */
@property (nonatomic, strong, readonly, nullable) id<PDSAccountService> accountService;

/*!
 @method initWithDatabase:databasePool:

 @abstract Initializes the admin service with database and pool.

 @param database The primary database.
 @param databasePool The database pool for transactions.
 @return An initialized admin service.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database
                    databasePool:(nullable PDSDatabasePool *)databasePool;

/*!
 @method initWithServiceDatabases:accountService:

 @abstract Initializes the admin service with service databases.

 @param serviceDatabases The service databases for persistence.
 @param accountService The account service for lookups (may be nil).
 @return An initialized admin service.
 */
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                          accountService:(nullable id<PDSAccountService>)accountService
    NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
