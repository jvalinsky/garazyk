// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract PDS-specific adapters for OAuthProvider and AuthVerifier.
 *
 * @discussion This module provides PDS-specific implementations of the protocols
 * required by OAuthProvider and AuthVerifier. It bridges the generic interfaces
 * to PDSDatabase, PDSAccountService, JWTMinter, etc.
 */

#import <Foundation/Foundation.h>
#import "Auth/OAuthProvider/OAuthProviderProtocols.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;
@class PDSAccountService;
@class JWTMinter;

/**
 * @abstract PDS implementation of OAuthProviderStorage.
 *
 * @discussion Uses PDSDatabase for persistence of PAR, authorization codes,
 * refresh tokens, and user consents.
 */
@interface PDSAuthStorage : NSObject <OAuthProviderStorage>

/**
 * @abstract Initialize with PDS database.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

@end


/**
 * @abstract PDS implementation of OAuthProviderClientRegistry.
 *
 * @discussion Looks up clients in PDSDatabase and validates redirect URIs.
 */
@interface PDSAuthClientRegistry : NSObject <OAuthProviderClientRegistry>

/**
 * @abstract Initialize with PDS database.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

@end


/**
 * @abstract PDS implementation of OAuthProviderTokenSigner.
 *
 * @discussion Uses JWTMinter for JWT signing and provides JWKS.
 */
@interface PDSAuthTokenSigner : NSObject <OAuthProviderTokenSigner>

/**
 * @abstract Initialize with JWT minter.
 */
- (instancetype)initWithJWTMinter:(JWTMinter *)minter issuer:(NSString *)issuer;

@end


/**
 * @abstract PDS implementation of OAuthProviderUserAuthenticator.
 *
 * @discussion Uses PDSAccountService for password/2FA verification.
 */
@interface PDSAuthUserAuthenticator : NSObject <OAuthProviderUserAuthenticator>

/**
 * @abstract Initialize with account service.
 */
- (instancetype)initWithAccountService:(PDSAccountService *)accountService;

@end


/**
 * @abstract PDS implementation of AccountPolicy.
 *
 * @discussion Checks account takedown status and admin privileges via PDSAdminController.
 */
@interface PDSAccountPolicy : NSObject <AccountPolicy>

/**
 * @abstract Initialize with PDS database.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

/**
 * @abstract Set the admin controller for admin checks.
 */
- (void)setAdminController:(id)adminController;

@end

NS_ASSUME_NONNULL_END
