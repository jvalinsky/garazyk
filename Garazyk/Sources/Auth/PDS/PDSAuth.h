/*!
 @file PDSAuth.h

 @abstract PDS-specific adapters for OAuthProvider and AuthVerifier.

 @discussion This module provides PDS-specific implementations of the protocols
 required by OAuthProvider and AuthVerifier. It bridges the generic interfaces
 to PDSDatabase, PDSAccountService, JWTMinter, etc.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Auth/OAuthProvider/OAuthProviderProtocols.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;
@class PDSAccountService;
@class JWTMinter;

/*!
 @class PDSAuthStorage
 
 @abstract PDS implementation of OAuthProviderStorage.
 
 @discussion Uses PDSDatabase for persistence of PAR, authorization codes,
 refresh tokens, and user consents.
 */
@interface PDSAuthStorage : NSObject <OAuthProviderStorage>

/*!
 @brief Initialize with PDS database.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

@end


/*!
 @class PDSAuthClientRegistry
 
 @abstract PDS implementation of OAuthProviderClientRegistry.
 
 @discussion Looks up clients in PDSDatabase and validates redirect URIs.
 */
@interface PDSAuthClientRegistry : NSObject <OAuthProviderClientRegistry>

/*!
 @brief Initialize with PDS database.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

@end


/*!
 @class PDSAuthTokenSigner
 
 @abstract PDS implementation of OAuthProviderTokenSigner.
 
 @discussion Uses JWTMinter for JWT signing and provides JWKS.
 */
@interface PDSAuthTokenSigner : NSObject <OAuthProviderTokenSigner>

/*!
 @brief Initialize with JWT minter.
 */
- (instancetype)initWithJWTMinter:(JWTMinter *)minter issuer:(NSString *)issuer;

@end


/*!
 @class PDSAuthUserAuthenticator
 
 @abstract PDS implementation of OAuthProviderUserAuthenticator.
 
 @discussion Uses PDSAccountService for password/2FA verification.
 */
@interface PDSAuthUserAuthenticator : NSObject <OAuthProviderUserAuthenticator>

/*!
 @brief Initialize with account service.
 */
- (instancetype)initWithAccountService:(PDSAccountService *)accountService;

@end


/*!
 @class PDSAccountPolicy
 
 @abstract PDS implementation of AccountPolicy.
 
 @discussion Checks account takedown status and admin privileges via PDSAdminController.
 */
@interface PDSAccountPolicy : NSObject <AccountPolicy>

/*!
 @brief Initialize with PDS database.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

/*!
 @brief Set the admin controller for admin checks.
 */
- (void)setAdminController:(id)adminController;

@end

NS_ASSUME_NONNULL_END
