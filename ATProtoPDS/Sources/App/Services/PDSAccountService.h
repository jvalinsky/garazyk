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
@protocol PDSAccountRepository;
@protocol PDSSessionRepository;

/*!
 @protocol PDSAccountService
 @abstract Protocol defining the account service public interface.
 */
@protocol PDSAccountService <NSObject>

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

/*! Gets account info by DID. */
- (nullable NSDictionary *)getAccountForDid:(NSString *)did error:(NSError **)error;

/*! Gets all accounts. */
- (nullable NSArray *)getAllAccountsWithError:(NSError **)error;

/*! Refreshes an access token using a refresh token. */
- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken
                                       error:(NSError **)error;

/*! Deletes an account after password verification. */
- (BOOL)deleteAccount:(NSString *)did password:(NSString *)password error:(NSError **)error;

@end

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



@end

NS_ASSUME_NONNULL_END
