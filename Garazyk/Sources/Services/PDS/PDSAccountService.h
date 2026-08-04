// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSAccountService.h
 *
 * @abstract Account management service layer.
 *
 * @discussion Provides high-level account operations including creation,
 * authentication, token refresh, and deletion. Coordinates between
 * database pool and JWT minting.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Core/PDSPLCAccountOperationProvider.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;
@class PDSDatabasePool;
@class ATProtoJWTMinter;
/**
 * @abstract Defines the PDSAccountRepository protocol contract.
 */
@protocol PDSAccountRepository;
@protocol PDSSessionRepository;

/**
 * @abstract Protocol defining the account service public interface.
 */
@protocol PDSAccountService <NSObject>

@property (nonatomic, strong, readonly, nullable) id<PDSSessionRepository> sessionRepository;

/**
 * @abstract Creates a new account with email, password, and handle.
 * @param email The account email address.
 * @param password The account password.
 * @param handle The account handle.
 * @param did Optional decentralized identifier for the account.
 * @param error Receives validation or database errors.
 * @return The account dictionary, or nil if creation fails.
 */
- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                             did:(nullable NSString *)did
                                          error:(NSError **)error;

/**
 * @abstract Authenticates a user by handle and password.
 * @param handle The user handle.
 * @param password The user password.
 * @param error Receives validation or database errors.
 * @return The session dictionary, or nil if authentication fails.
 */
- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                 password:(NSString *)password
                                    error:(NSError **)error;

/**
 * @abstract Authenticates a user by handle or email and password.
 * @param identifier The user handle or email address.
 * @param password The user password.
 * @param error Receives validation or database errors.
 * @return The session dictionary, or nil if authentication fails.
 */
- (nullable NSDictionary *)loginWithIdentifier:(NSString *)identifier
                                     password:(NSString *)password
                                        error:(NSError **)error;

/**
 * @abstract Authenticates a user by handle or email, password, and optional second-factor proof.
 * @param identifier The user handle or email address.
 * @param password The user password.
 * @param authFactorToken The second-factor authentication token.
 * @param error Receives validation or database errors.
 * @return The session dictionary, or nil if authentication fails.
 */
- (nullable NSDictionary *)loginWithIdentifier:(NSString *)identifier
                                      password:(NSString *)password
                               authFactorToken:(nullable NSString *)authFactorToken
                                         error:(NSError **)error;

/**
 * @abstract Retrieves account information by DID.
 * @param did The decentralized identifier.
 * @param error Receives validation or database errors.
 * @return The account dictionary, or nil if the account is not found.
 */
- (nullable NSDictionary *)getAccountForDid:(NSString *)did error:(NSError **)error;

/**
 * @abstract Retrieves storage usage for an account by DID.
 * @discussion Returns a dictionary containing blobBytes, blobCount, repoBytes, and recordCount.
 * @param did The decentralized identifier.
 * @param error Receives validation or database errors.
 * @return The usage dictionary, or nil if the account is not found.
 */
- (nullable NSDictionary *)usageForDid:(NSString *)did error:(NSError **)error;

/**
 * @abstract Retrieves all accounts.
 * @param error Receives database errors.
 * @return An array of account dictionaries, or nil if retrieval fails.
 */
- (nullable NSArray *)getAllAccountsWithError:(NSError **)error;

/**
 * @abstract Refreshes an access token using a refresh token.
 * @param refreshToken The refresh token.
 * @param error Receives validation or database errors.
 * @return The new session dictionary, or nil if refresh fails.
 */
- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken
                                       error:(NSError **)error;

/**
 * @abstract Deletes an account after password verification.
 * @param did The decentralized identifier.
 * @param password The user password.
 * @param error Receives validation or database errors.
 * @return YES if deletion succeeded, NO otherwise.
 */
- (BOOL)deleteAccount:(NSString *)did password:(NSString *)password error:(NSError **)error;

@end

/**
 * @abstract Defines the PDSEmailProvider protocol contract.
 */
@protocol PDSEmailProvider;

/**
 * @abstract Service for account management operations.
 */
@interface PDSAccountService : NSObject <PDSAccountService>

/**
 * @abstract Database pool.
 * @discussion The owner (PDSController) must outlive this service.
 */
@property (nonatomic, strong) PDSDatabasePool *databasePool;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;

/**
 * @abstract Repository for account data access.
 */
@property (nonatomic, strong, nullable) id<PDSAccountRepository> accountRepository;

/**
 * @abstract Repository for session data access.
 */
@property (nonatomic, strong, nullable) id<PDSSessionRepository> sessionRepository;

/**
 * @abstract JWT minter for token generation.
 */
@property (nonatomic, strong, nullable) ATProtoJWTMinter *minter;

/**
 * @abstract Pluggable email provider for sending verification codes and alerts.
 */
@property (nonatomic, strong, nullable) id<PDSEmailProvider> emailProvider;

/** PLC account-operation signer supplied by Runtime composition. */
@property (nonatomic, strong, nullable) id<PDSPLCAccountOperationProvider> plcOperationProvider;

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

/**
 * @abstract Initializes the service with dependencies.
 * @param accountRepository Repository for account operations.
 * @param sessionRepository Repository for session operations.
 * @param minter JWT minter for tokens.
 * @param emailProvider Email provider for alerts and verification.
 * @return An initialized instance.
 */
- (instancetype)initWithAccountRepository:(nullable id<PDSAccountRepository>)accountRepository
                        sessionRepository:(nullable id<PDSSessionRepository>)sessionRepository
                                   minter:(nullable ATProtoJWTMinter *)minter
                            emailProvider:(nullable id<PDSEmailProvider>)emailProvider;

#pragma mark - Account Operations

/**
 * @abstract Generates a random did:plc identifier.
 * @return A new decentralized identifier.
 */
- (NSString *)generatePlcIdentifier;

/**
 * @abstract Retrieves storage usage for an account by DID.
 * @discussion Returns a dictionary containing blobBytes, blobCount, repoBytes, and recordCount.
 * @param did The decentralized identifier.
 * @param error Receives validation or database errors.
 * @return The usage dictionary, or nil if the account is not found.
 */
- (nullable NSDictionary *)usageForDid:(NSString *)did error:(NSError **)error;

/**
 * @abstract Begins WebAuthn second-factor login after password verification.
 * @param identifier The user handle or email address.
 * @param password The user password.
 * @param error Receives validation or database errors.
 * @return The WebAuthn challenge dictionary, or nil if initiation fails.
 */
- (nullable NSDictionary *)beginWebAuthnSecondFactorForIdentifier:(NSString *)identifier
                                                         password:(NSString *)password
                                                            error:(NSError **)error;

/**
 * @abstract Completes WebAuthn second-factor login.
 * @param identifier The user handle or email address.
 * @param sessionID The session identifier.
 * @param assertion The WebAuthn assertion dictionary.
 * @param error Receives validation or database errors.
 * @return An auth factor token, or nil if completion fails.
 */
- (nullable NSString *)completeWebAuthnSecondFactorForIdentifier:(NSString *)identifier
                                                       sessionID:(NSString *)sessionID
                                                       assertion:(NSDictionary *)assertion
                                                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
