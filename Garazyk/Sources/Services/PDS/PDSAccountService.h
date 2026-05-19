// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSAccountService.h

 @abstract Account management service layer.

 @discussion Provides high-level account operations including creation,
 authentication, token refresh, and deletion. Coordinates between
 database pool and JWT minting.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;
@class PDSDatabasePool;
@class JWTMinter;
/**
 * @abstract Defines the PDSAccountRepository protocol contract.
 */
@protocol PDSAccountRepository;
@protocol PDSSessionRepository;

/*!
 @protocol PDSAccountService
 @abstract Protocol defining the account service public interface.
 */
@protocol PDSAccountService <NSObject>

@property (nonatomic, strong, readonly, nullable) id<PDSSessionRepository> sessionRepository;

/*! Creates a new account with email, password, and handle. */
- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                             did:(nullable NSString *)did
                                          error:(NSError **)error;

/*! Authenticates a user by handle and password. */
- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                 password:(NSString *)password
                                    error:(NSError **)error;

/*! Authenticates a user by handle or email and password. */
- (nullable NSDictionary *)loginWithIdentifier:(NSString *)identifier
                                     password:(NSString *)password
                                        error:(NSError **)error;

/*! Authenticates a user by handle or email, password, and optional second-factor proof. */
- (nullable NSDictionary *)loginWithIdentifier:(NSString *)identifier
                                      password:(NSString *)password
                               authFactorToken:(nullable NSString *)authFactorToken
                                         error:(NSError **)error;

/*! Gets account info by DID. */
- (nullable NSDictionary *)getAccountForDid:(NSString *)did error:(NSError **)error;

/*! Gets storage usage for an account by DID. Returns dict with blobBytes, blobCount, repoBytes, recordCount. */
- (nullable NSDictionary *)usageForDid:(NSString *)did error:(NSError **)error;

/*! Gets all accounts. */
- (nullable NSArray *)getAllAccountsWithError:(NSError **)error;

/*! Refreshes an access token using a refresh token. */
- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken
                                       error:(NSError **)error;

/*! Deletes an account after password verification. */
- (BOOL)deleteAccount:(NSString *)did password:(NSString *)password error:(NSError **)error;

@end

/**
 * @abstract Defines the PDSEmailProvider protocol contract.
 */
@protocol PDSEmailProvider;

/*!
 @class PDSAccountService

 @abstract Service for account management operations.
 */
@interface PDSAccountService : NSObject <PDSAccountService>

/*! Database pool - owner (PDSController) must outlive this service. */
@property (nonatomic, strong) PDSDatabasePool *databasePool;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;

/*! Repositories for data access. */
@property (nonatomic, strong, nullable) id<PDSAccountRepository> accountRepository;
@property (nonatomic, strong, nullable) id<PDSSessionRepository> sessionRepository;

/*! JWT minter for token generation. */
@property (nonatomic, strong, nullable) JWTMinter *minter;

/*! Pluggable email provider for sending verification codes and alerts. */
@property (nonatomic, strong, nullable) id<PDSEmailProvider> emailProvider;

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

/*! New DI initializer. */
- (instancetype)initWithAccountRepository:(nullable id<PDSAccountRepository>)accountRepository
                        sessionRepository:(nullable id<PDSSessionRepository>)sessionRepository
                                   minter:(nullable JWTMinter *)minter
                            emailProvider:(nullable id<PDSEmailProvider>)emailProvider;

#pragma mark - Account Operations

/*! Generates a random did:plc identifier (for testing). */
- (NSString *)generatePlcIdentifier;

/*! Gets storage usage for an account by DID. Returns dict with blobBytes, blobCount, repoBytes, recordCount. */
- (nullable NSDictionary *)usageForDid:(NSString *)did error:(NSError **)error;

/*! Begins WebAuthn second-factor login after password verification. */
- (nullable NSDictionary *)beginWebAuthnSecondFactorForIdentifier:(NSString *)identifier
                                                         password:(NSString *)password
                                                            error:(NSError **)error;

/*! Completes WebAuthn second-factor login and returns an authFactorToken for createSession. */
- (nullable NSString *)completeWebAuthnSecondFactorForIdentifier:(NSString *)identifier
                                                       sessionID:(NSString *)sessionID
                                                       assertion:(NSDictionary *)assertion
                                                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
