/*!
 @file OAuth2Handler.h

 @abstract HTTP handler for OAuth 2.0 endpoints.

 @discussion
    Provides HTTP request handlers for standard OAuth 2.0 endpoints including
    authorization, token exchange, and token revocation. Integrates with
    OAuth2Server for processing authorization requests and issuing tokens.

    Supports the AT Protocol OAuth profile with PKCE, DPoP, and PAR.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Auth/JWT.h"

@class OAuth2Server;
@class HttpServer;
@class PDSDatabase;
@class HttpRequest;
@class HttpResponse;
@class JWTMinter;

@protocol PDSAccountService;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class OAuth2Handler

 @abstract HTTP handler for OAuth 2.0 endpoints.

 @discussion
    This class provides HTTP request handlers for the standard OAuth 2.0
    endpoints: authorize, token, and revoke. It integrates with the OAuth2Server
    class to process authorization requests and issue tokens.

    Endpoints handled:
    - GET /oauth/authorize - Authorization request display
    - POST /oauth/authorize/signin - Sign-in credential validation
    - POST /oauth/authorize/confirm - Authorization confirmation
    - POST /oauth/token - Token endpoint
    - POST /oauth/revoke - Token revocation
    - POST /oauth/par - Pushed Authorization Requests

    Thread Safety: Each request is handled independently. The underlying
    OAuth2Server uses appropriate synchronization for shared state.
 */
@interface OAuth2Handler : NSObject

/*! The underlying OAuth 2.0 server implementation. */
@property (nonatomic, strong) OAuth2Server *oauthServer;

/*! JWT minting service for token generation. */
@property (nonatomic, strong, nullable) JWTMinter *minter;

/*! Data directory for static assets (HTML templates, etc.). */
@property (nonatomic, copy, nullable) NSString *dataDirectory;

/*! Account service for sign-in credential validation. */
@property (nonatomic, strong, nullable) id<PDSAccountService> accountService;

/*! Client metadata for dynamic client validation (ATProto OAuth). */
@property (nonatomic, strong, nullable) NSDictionary *clientMetadata;

/*!
 @method initWithDatabase:

 @abstract Initializes a new OAuth2 handler with a database.

 @param database The database to use for client and token storage.

 @return An initialized OAuth2Handler instance.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

/*!
 @method init

 @abstract Initializes a new OAuth2 handler without a database.

 @return An initialized OAuth2Handler instance.

 @discussion Use initWithDatabase: for full functionality.
 */
- (instancetype)init;

/*!
 @method registerRoutesWithServer:

 @abstract Registers OAuth 2.0 routes with the HTTP server.

 @param httpServer The HTTP server to register routes with.

 @discussion Registers the following routes:
    - GET /oauth/authorize
    - POST /oauth/authorize/signin
    - POST /oauth/authorize/confirm
    - POST /oauth/token
    - POST /oauth/revoke
    - POST /oauth/par
 */
- (void)registerRoutesWithServer:(HttpServer *)httpServer;

/*!
 @method handleTokenRequest:response:

 @abstract Handles token endpoint requests.

 @param request The HTTP request containing token parameters.
 @param response The HTTP response to populate.

 @discussion Supports grant types:
    - authorization_code (with PKCE)
    - refresh_token
    - client_credentials
 */
- (void)handleTokenRequest:(HttpRequest *)request response:(HttpResponse *)response;

/*!
 @method handleAuthorizeRequest:response:

 @abstract Handles authorization request display.

 @param request The HTTP request containing authorization parameters.
 @param response The HTTP response to populate with the authorization form.
 */
- (void)handleAuthorizeRequest:(HttpRequest *)request response:(HttpResponse *)response;

/*!
 @method handleAuthorizeSignIn:response:

 @abstract Handles sign-in credential validation.

 @param request The HTTP request containing sign-in credentials.
 @param response The HTTP response to populate.

 @discussion Validates user credentials and advances the authorization flow.
 */
- (void)handleAuthorizeSignIn:(HttpRequest *)request response:(HttpResponse *)response;

/*!
 @method handleAuthorizeConfirm:response:

 @abstract Handles authorization confirmation.

 @param request The HTTP request containing user consent.
 @param response The HTTP response to populate with redirect.

 @discussion Processes user consent and issues authorization code.
 */
- (void)handleAuthorizeConfirm:(HttpRequest *)request response:(HttpResponse *)response;

/*!
 @method handleRevokeRequest:response:

 @abstract Handles token revocation requests.

 @param request The HTTP request containing the token to revoke.
 @param response The HTTP response to populate.
 */
- (void)handleRevokeRequest:(HttpRequest *)request response:(HttpResponse *)response;

/*!
 @method handlePARRequest:response:

 @abstract Handles Pushed Authorization Requests (PAR).

 @param request The HTTP request containing authorization parameters.
 @param response The HTTP response to populate with request URI.

 @discussion Stores authorization parameters and returns a request_uri
 for use in the authorization request.
 */
- (void)handlePARRequest:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
