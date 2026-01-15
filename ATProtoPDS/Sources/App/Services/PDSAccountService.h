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

/*!
 @class PDSAccountService

 @abstract Service for account management operations.
 */
@interface PDSAccountService : NSObject

#if defined(GNUSTEP)
@property (nonatomic, assign) PDSDatabasePool *databasePool;
#else
@property (nonatomic, weak) PDSDatabasePool *databasePool;
#endif
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;

/*! JWT minter for token generation. */
@property (nonatomic, strong, nullable) JWTMinter *minter;

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

#pragma mark - Account Operations

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

NS_ASSUME_NONNULL_END
