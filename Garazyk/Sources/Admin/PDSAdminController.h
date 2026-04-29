/*!
 @file PDSAdminController.h

 @abstract Thin controller for administrative operations.

 @discussion PDSAdminController is a thin controller that delegates to PDSAdminService
 for all business logic. This class handles request parsing, validation, and response
 formatting only. All administrative operations are implemented in PDSAdminService.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;
@class PDSAdminService;
@protocol PDSAccountService;
@protocol PDSAdminService;

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
 @method deactivateAccount:reason:error:

 @abstract Deactivates an account (user-initiated, reversible).

 @discussion Sets the account status to "deactivated" which is distinct from
 takedown. Deactivation is a user-initiated action; takedown is an admin action
 for policy violations.

 @param did The DID of the account to deactivate.
 @param reason The reason for deactivation.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
- (BOOL)deactivateAccount:(NSString *)did reason:(NSString *)reason error:(NSError **)error;

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

/*!
 @method disableInviteCodesWithCodes:accounts:error:

 @abstract Disables invite codes by explicit code and/or owning account identifiers.

 @param codes Invite code strings to disable.
 @param accounts Account identifiers (DIDs or handles) whose invite codes should be disabled.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
- (BOOL)disableInviteCodesWithCodes:(nullable NSArray<NSString *> *)codes
                           accounts:(nullable NSArray<NSString *> *)accounts
                              error:(NSError **)error;

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

#pragma mark - Server Statistics

/*!
 @method getServerStatsWithError:
 
 @abstract Retrieves server statistics for admin dashboard.
 
 @param error On return, contains an error if the operation failed.
 @return Dictionary with server statistics, or nil on failure.
 */
- (nullable NSDictionary *)getServerStatsWithError:(NSError **)error;

#pragma mark - Audit Logging

/*!
 @method logAdminAction:subjectType:subjectId:details:ipAddress:adminDid:error:
 
 @abstract Logs an admin action to the audit log.
 
 @param action The action being performed.
 @param subjectType The type of subject.
 @param subjectId The identifier of the subject.
 @param details Additional details dictionary.
 @param ipAddress The IP address of the admin.
 @param adminDid The DID of the admin.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
- (BOOL)logAdminAction:(NSString *)action
           subjectType:(nullable NSString *)subjectType
             subjectId:(nullable NSString *)subjectId
               details:(nullable NSDictionary *)details
              ipAddress:(nullable NSString *)ipAddress
               adminDid:(NSString *)adminDid
                  error:(NSError **)error;

/*!
 @method queryAuditLog:limit:cursor:error:
 
 @abstract Queries the audit log with filters.
 
 @param filters Dictionary of filters.
 @param limit Maximum results.
 @param cursor Pagination cursor.
 @param error On return, contains an error if the operation failed.
 @return Dictionary with audit log entries, or nil on failure.
 */
- (nullable NSDictionary *)queryAuditLog:(NSDictionary *)filters
                                   limit:(NSInteger)limit
                                 cursor:(nullable NSString *)cursor
                                   error:(NSError **)error;

#pragma mark - Reports

/*!
 @method createReport:error:
 
 @abstract Creates a new moderation report.
 
 @param params Report parameters.
 @param error On return, contains an error if the operation failed.
 @return Dictionary with created report, or nil on failure.
 */
- (nullable NSDictionary *)createReport:(NSDictionary *)params error:(NSError **)error;

/*!
 @method queryReports:limit:cursor:error:
 
 @abstract Queries moderation reports.
 
 @param filters Filter dictionary.
 @param limit Maximum results.
 @param cursor Pagination cursor.
 @param error On return, contains an error if the operation failed.
 @return Dictionary with reports, or nil on failure.
 */
- (nullable NSDictionary *)queryReports:(NSDictionary *)filters
                                  limit:(NSInteger)limit
                                cursor:(nullable NSString *)cursor
                                  error:(NSError **)error;

/*!
 @method resolveReport:status:resolvedBy:notes:error:
 
 @abstract Resolves a moderation report.
 
 @param reportId Report ID.
 @param status New status.
 @param resolvedBy Admin DID.
 @param notes Resolution notes.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
- (BOOL)resolveReport:(NSString *)reportId
               status:(NSString *)status
            resolvedBy:(nullable NSString *)resolvedBy
                notes:(nullable NSString *)notes
                error:(NSError **)error;

@end

/*!
 @class PDSAdminController

 @abstract Thin controller for administrative operations.

 @discussion Delegates all operations to PDSAdminService for business logic.
 Handles request parsing, validation, and response formatting.

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

/*! Admin service for business logic delegation (readonly). */
@property (nonatomic, strong, readonly) id<PDSAdminService> adminService;

/*!
 @method initWithServiceDatabases:accountService:

 @abstract Initializes the admin controller with dependencies.

 @param serviceDatabases The service databases for persistence.
 @param accountService The account service for account operations (may be nil).
 @return An initialized admin controller, or nil if service creation failed.
 */
- (nullable instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                                   accountService:(nullable id<PDSAccountService>)accountService
    NS_DESIGNATED_INITIALIZER;

/*!
 @method initWithServiceDatabases:

  @abstract Initializes the admin controller with service databases.

 @param serviceDatabases The service databases for persistence.
 @return An initialized admin controller.
 */
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;

/*!
 @method initWithAdminService:

 @abstract Initializes the admin controller with a pre-configured admin service.

 @param adminService The admin service to delegate to.
 @return An initialized admin controller.
 */
- (instancetype)initWithAdminService:(id<PDSAdminService>)adminService NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
