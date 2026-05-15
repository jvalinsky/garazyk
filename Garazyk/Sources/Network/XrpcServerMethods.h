// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcServerMethods.h
//  ATProtoPDS
//
//  Domain module for com.atproto.server.* XRPC endpoints.
//  Handles account creation, session management, invite codes, app passwords,
//  email operations, and account lifecycle methods.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class JWTMinter;
@class ATProtoServiceConfiguration;
@class PDSServiceDatabases;
@class PDSDatabasePool;
@class PDSRepositoryService;
@protocol PDSAccountService;
@protocol PDSAdminController;
@protocol PDSEmailProvider;
@protocol PDSRegistrationGate;

NS_ASSUME_NONNULL_BEGIN

/**
 @brief Domain module for com.atproto.server.* endpoints.
 
 This module registers all server-related XRPC endpoints including:
 - describeServer
 - createAccount, createSession, refreshSession, getSession, deleteSession
 - createInviteCode, createInviteCodes, getAccountInviteCodes
 - createAppPassword, listAppPasswords, revokeAppPassword
 - requestAccountDelete, deleteAccount
 - updateEmail, requestEmailUpdate, confirmEmail, requestEmailConfirmation
 - getServiceAuth
 - reserveSigningKey, activateAccount, deactivateAccount
 - requestPasswordReset, resetPassword
 - getAccount, checkAccountStatus
 */
@interface XrpcServerMethods : NSObject

/**
 @brief Register all com.atproto.server.* endpoint handlers with the dispatcher.
 
 @param dispatcher The XRPC dispatcher to register handlers with
 @param jwtMinter JWT token minter for authentication
 @param adminController Admin operations controller
 @param accountService Account management service
 @param repositoryService Repository operations service
 @param serviceDatabases Service-level database access
 @param userDatabasePool User-level database pool
 @param config Server configuration
 @param enforceDidWebServiceAuth Whether to enforce did:web service auth for account creation
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
                accountService:(id<PDSAccountService>)accountService
             repositoryService:(PDSRepositoryService *)repositoryService
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
              userDatabasePool:(PDSDatabasePool *)userDatabasePool
                 configuration:(ATProtoServiceConfiguration *)config
    enforceDidWebServiceAuth:(BOOL)enforceDidWebServiceAuth
            registrationGate:(nullable id<PDSRegistrationGate>)registrationGate;

@end

NS_ASSUME_NONNULL_END
