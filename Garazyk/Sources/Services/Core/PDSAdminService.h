// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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
/**
 * @abstract Defines the PDSAccountService protocol contract.
 */
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
/**
 * @abstract Performs the deactivateAccount operation.
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
 @method disableInviteCodesWithCodes:accounts:error:

 @abstract Disables invite codes by explicit code and/or owning account identifiers.

 @param codes Invite code strings to disable.
 @param accounts Account identifiers (DIDs or handles) whose invite codes should be disabled.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
/** Disables invite codes by code and/or account owner. */
- (BOOL)disableInviteCodesWithCodes:(nullable NSArray<NSString *> *)codes
                           accounts:(nullable NSArray<NSString *> *)accounts
                              error:(NSError **)error;

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
/** Retrieves labels matching admin query parameters. */
- (nullable NSDictionary *)getLabels:(NSDictionary *)params error:(NSError **)error;

#pragma mark - Server Statistics

/*!
 @method getServerStatsWithError:
 
 @abstract Retrieves server statistics for admin dashboard.
 
 @param error On return, contains an error if the operation failed.
 @return Dictionary with server statistics, or nil on failure.
 */
/** Retrieves server statistics for administrative dashboards. */
- (nullable NSDictionary *)getServerStatsWithError:(NSError **)error;

#pragma mark - Audit Logging

/*!
 @method logAdminAction:subjectType:subjectId:details:ipAddress:error:
 
 @abstract Logs an admin action to the audit log.
 
 @param action The action being performed (e.g., "account.disable").
 @param subjectType The type of subject (e.g., "account", "record", "invite_code").
 @param subjectId The identifier of the subject.
 @param details Additional details as a dictionary (will be JSON-encoded).
 @param ipAddress The IP address of the admin.
 @param adminDid The DID of the admin performing the action.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
/** Logs an administrative action to the audit log. */
- (BOOL)logAdminAction:(NSString *)action
           subjectType:(nullable NSString *)subjectType
             subjectId:(nullable NSString *)subjectId
               details:(nullable NSDictionary *)details
              ipAddress:(nullable NSString *)ipAddress
               adminDid:(NSString *)adminDid
                  error:(NSError **)error;

/*!
 @method queryAuditLog:limit:cursor:error:
 
 @abstract Queries the audit log with optional filters.
 
 @param filters Dictionary of filters (admin_did, action, subject_type, subject_id, since, until).
 @param limit Maximum number of results.
 @param cursor Pagination cursor.
 @param error On return, contains an error if the operation failed.
 @return Dictionary with audit log entries and cursor, or nil on failure.
 */
/** Queries administrative audit log entries. */
- (nullable NSDictionary *)queryAuditLog:(NSDictionary *)filters
                                   limit:(NSInteger)limit
                                 cursor:(nullable NSString *)cursor
                                   error:(NSError **)error;

#pragma mark - Reports

/*!
 @method createReport:error:
 
 @abstract Creates a new moderation report.
 
 @param params Dictionary containing report parameters (reason_type, reason, reported_by_did, subject_type, subject_did, subject_uri).
 @param error On return, contains an error if the operation failed.
 @return Dictionary with the created report, or nil on failure.
 */
/** Creates a moderation report from admin parameters. */
- (nullable NSDictionary *)createReport:(NSDictionary *)params error:(NSError **)error;

/*!
 @method queryReports:limit:cursor:error:
 
 @abstract Queries moderation reports with optional filters.
 
 @param filters Dictionary of filters (status, reason_type, reported_by_did, subject_did, subject_type).
 @param limit Maximum number of results.
 @param cursor Pagination cursor.
 @param error On return, contains an error if the operation failed.
 @return Dictionary with reports array and cursor, or nil on failure.
 */
/** Queries moderation reports with filters and pagination. */
- (nullable NSDictionary *)queryReports:(NSDictionary *)filters
                                  limit:(NSInteger)limit
                                cursor:(nullable NSString *)cursor
                                  error:(NSError **)error;

/*!
 @method resolveReport:status:resolvedBy:notes:error:
 
 @abstract Resolves or dismisses a moderation report.
 
 @param reportId The ID of the report to resolve.
 @param status The new status ("resolved" or "dismissed").
 @param resolvedBy The DID of the admin resolving the report.
 @param notes Optional resolution notes.
 @param error On return, contains an error if the operation failed.
 @return YES if successful, NO otherwise.
 */
/** Resolves or dismisses a moderation report. */
- (BOOL)resolveReport:(NSString *)reportId
               status:(NSString *)status
            resolvedBy:(nullable NSString *)resolvedBy
                notes:(nullable NSString *)notes
                error:(NSError **)error;

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
/** Initializes the admin service with a primary database and optional pool. */
- (instancetype)initWithDatabase:(PDSDatabase *)database
                    databasePool:(nullable PDSDatabasePool *)databasePool;

/*!
 @method initWithServiceDatabases:accountService:

 @abstract Initializes the admin service with service databases.

 @param serviceDatabases The service databases for persistence.
 @param accountService The account service for lookups (may be nil).
 @return An initialized admin service.
 */
/** Initializes the admin service with service databases and account lookup service. */
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                          accountService:(nullable id<PDSAccountService>)accountService
    NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
