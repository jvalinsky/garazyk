// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAdminMethods.h
//  ATProtoPDS
//
//  Domain module for com.atproto.admin.* XRPC endpoints.
//  Handles administrative operations including account management,
//  invite code management, and moderation actions.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class JWTMinter;
@class PDSServiceDatabases;
@class PDSRepositoryService;
@class PDSBlobAuditManager;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

/**
 * XrpcAdminMethods registers all com.atproto.admin.* endpoint handlers.
 *
 * Endpoints handled:
 * - com.atproto.admin.disableAccountInvites: Disable invite code creation for an account
 * - com.atproto.admin.enableAccountInvites: Enable invite code creation for an account
 * - com.atproto.admin.getAccountInfo: Get detailed account information
 * - com.atproto.admin.getAccountUsage: Get account storage usage
 * - com.atproto.admin.getAccountInfos: Get information for multiple accounts
 * - com.atproto.admin.getInviteCodes: List all invite codes with filtering
 * - com.atproto.admin.getSubjectStatus: Get moderation status for a subject
 * - com.atproto.admin.searchAccounts: Search accounts by email or other criteria
 * - com.atproto.admin.sendEmail: Send email to an account
 * - com.atproto.admin.updateAccountEmail: Update account email address
 * - com.atproto.admin.updateAccountHandle: Update account handle
 * - com.atproto.admin.updateAccountPassword: Update account password
 * - com.atproto.admin.updateSubjectStatus: Update moderation status (takedown)
 * - com.atproto.admin.getServerStats: Get server statistics
 * - com.atproto.admin.queryAuditLog: Query administrative audit log
 * - com.atproto.admin.repairRepo: Force re-initialize a repository
 * - com.atproto.admin.runBlobAudit: Start a blob audit job
 * - com.atproto.admin.getBlobAuditStatus: Get status of a blob audit job
 *
 * All endpoints require admin authorization via XrpcAuthHelper.authorizeAdminRequest.
 *
 * This module uses:
 * - XrpcAuthHelper for authentication and admin authorization
 * - XrpcErrorHelper for error responses
 */
@interface XrpcAdminMethods : NSObject

/**
 * Register all com.atproto.admin.* endpoint handlers with the dispatcher.
 *
 * @param dispatcher The XRPC dispatcher to register endpoints with
 * @param serviceDatabases Service-level database access
 * @param jwtMinter JWT token minter for authentication
 * @param adminController Admin controller for authorization and operations
 * @param repositoryService Repository service for repair operations
 * @param auditManager Blob audit manager
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
             repositoryService:(PDSRepositoryService *)repositoryService
                  auditManager:(PDSBlobAuditManager *)auditManager;

@end

NS_ASSUME_NONNULL_END
