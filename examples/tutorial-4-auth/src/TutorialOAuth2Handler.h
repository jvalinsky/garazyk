/*!
 @file TutorialOAuth2Handler.h

 @abstract OAuth 2.0 authorization server handler for tutorials.

 @discussion Implements a simplified OAuth 2.0 authorization flow with:
 - Authorization code flow with PKCE (S256)
 - ES256-signed access and refresh tokens
 - DPoP binding support
 - Token refresh

 This is the educational version of the production OAuthProviderServer in
 Garazyk/Sources/OAuthProvider/OAuthProviderServer.h.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class TutorialJWTMinter;
@class TutorialECDSAKeyPair;

NS_ASSUME_NONNULL_BEGIN

@interface TutorialOAuth2Handler : NSObject

/*! The JWT minter for signing tokens. */
@property (nonatomic, strong) TutorialJWTMinter *minter;

/*!
 @method initWithMinter:

 @abstract Creates an OAuth2 handler with a JWT minter.

 @param minter The ES256 JWT minter for signing tokens.
 @return A new handler instance.
 */
- (instancetype)initWithMinter:(TutorialJWTMinter *)minter;

/*!
 @method handleAuthorize:completion:

 @abstract Handles an authorization request (authorization code flow).

 @param params The request parameters (client_id, redirect_uri, scope, state, code_challenge, code_challenge_method).
 @param completion Called with the redirect URL or error.
 */
- (void)handleAuthorize:(NSDictionary *)params
             completion:(void (^)(NSString * _Nullable redirectURL, NSError * _Nullable error))completion;

/*!
 @method handleToken:completion:

 @abstract Handles a token exchange request (authorization_code or refresh_token).

 @param params The request parameters (grant_type, code, code_verifier, client_id, redirect_uri, refresh_token).
 @param completion Called with the token response or error.
 */
- (void)handleToken:(NSDictionary *)params
          completion:(void (^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
