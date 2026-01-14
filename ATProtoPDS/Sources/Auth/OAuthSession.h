/*!
 @file OAuthSession.h

 @abstract OAuth 2.0 session and flow management.

 @discussion Implements OAuth 2.0 authorization code flow with PKCE and DPoP.
 Includes Pushed Authorization Request (PAR), session tracking, and token
 exchange. Supports ATProto authentication requirements.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for OAuth operations. */
extern NSString * const OAuthErrorDomain;

/*!
 @enum OAuthError

 @abstract OAuth 2.0 error codes per RFC 6749.

 @constant OAuthErrorInvalidRequest Request is missing required parameters.
 @constant OAuthErrorUnauthorized Client authentication failed.
 @constant OAuthErrorUnsupportedResponseType Response type not supported.
 @constant OAuthErrorInvalidScope Requested scope is invalid.
 @constant OAuthErrorServerError Server encountered error.
 @constant OAuthErrorTemporarilyUnavailable Server temporarily unavailable.
 */
typedef NS_ENUM(NSInteger, OAuthError) {
    OAuthErrorInvalidRequest = 400,
    OAuthErrorUnauthorized = 401,
    OAuthErrorUnsupportedResponseType = 400,
    OAuthErrorInvalidScope = 400,
    OAuthErrorServerError = 500,
    OAuthErrorTemporarilyUnavailable = 503,
};

/*!
 @class OAuthSession

 @abstract OAuth authorization session state.

 @discussion Tracks OAuth flow state including PKCE challenge, DPoP binding,
 and authorization codes. Sessions expire after 10 minutes if not completed.
 */
@interface OAuthSession : NSObject

/*! Unique session identifier. */
@property (nonatomic, copy) NSString *sessionId;

/*! OAuth client ID. */
@property (nonatomic, copy, nullable) NSString *clientId;

/*! Response type (typically "code"). */
@property (nonatomic, copy, nullable) NSString *responseType;

/*! Client redirect URI. */
@property (nonatomic, copy, nullable) NSString *redirectUri;

/*! PKCE code challenge (S256 hash of verifier). */
@property (nonatomic, copy, nullable) NSString *codeChallenge;

/*! PKCE code verifier (for validation). */
@property (nonatomic, copy, nullable) NSString *codeVerifier;

/*! Client state parameter for CSRF protection. */
@property (nonatomic, copy, nullable) NSString *state;

/*! Requested OAuth scope. */
@property (nonatomic, copy, nullable) NSString *scope;

/*! Login hint for pre-filling username. */
@property (nonatomic, copy, nullable) NSString *loginHint;

/*! Generated authorization code. */
@property (nonatomic, copy, nullable) NSString *authorizationCode;

/*! Authorization code expiration (typically 10 minutes). */
@property (nonatomic, strong, nullable) NSDate *codeExpiresAt;

/*! DPoP nonce for replay protection. */
@property (nonatomic, copy, nullable) NSString *dpopNonce;

/*! DPoP key thumbprint for binding. */
@property (nonatomic, copy, nullable) NSString *dpopKeyThumbprint;

/*! DPoP JWT proof. */
@property (nonatomic, copy, nullable) NSString *dpopJwt;

/*! Associated account DID after authentication. */
@property (nonatomic, copy, nullable) NSString *accountDid;

/*! Session creation timestamp. */
@property (nonatomic, strong) NSDate *createdAt;

/*! Whether user has authenticated. */
@property (nonatomic, assign) BOOL authenticated;

/*! Create session with ID. */
+ (instancetype)sessionWithId:(NSString *)sessionId;

@end

/*!
 @class OAuthPARRequest

 @abstract Pushed Authorization Request per RFC 9126.

 @discussion PAR improves security by submitting authorization parameters
 to token endpoint before redirecting user. Returns request_uri for use
 in authorization endpoint.
 */
@interface OAuthPARRequest : NSObject

/*! OAuth client ID. */
@property (nonatomic, copy) NSString *clientId;

/*! Response type (typically "code"). */
@property (nonatomic, copy) NSString *responseType;

/*! PKCE code challenge (S256 hash). */
@property (nonatomic, copy) NSString *codeChallenge;

/*! PKCE challenge method (typically "S256"). */
@property (nonatomic, copy) NSString *codeChallengeMethod;

/*! Client state for CSRF protection. */
@property (nonatomic, copy) NSString *state;

/*! Client redirect URI. */
@property (nonatomic, copy) NSString *redirectUri;

/*! Requested OAuth scope. */
@property (nonatomic, copy) NSString *scope;

/*! Client assertion JWT for authentication. */
@property (nonatomic, copy, nullable) NSString *clientAssertion;

/*! Client assertion type (urn:ietf:params:oauth:client-assertion-type:jwt-bearer). */
@property (nonatomic, copy, nullable) NSString *clientAssertionType;

/*! Login hint for pre-filling. */
@property (nonatomic, copy, nullable) NSString *loginHint;

/*! DPoP proof JWT. */
@property (nonatomic, copy, nullable) NSString *dpopJwt;

/*! Validate request parameters. */
- (BOOL)validateWithError:(NSError **)error;

@end

/*!
 @class OAuthTokenRequest

 @abstract Token endpoint request per RFC 6749.

 @discussion Exchanges authorization code for access/refresh tokens.
 Supports authorization_code and refresh_token grant types.
 */
@interface OAuthTokenRequest : NSObject

/*! Grant type (authorization_code or refresh_token). */
@property (nonatomic, copy) NSString *grantType;

/*! Authorization code for code exchange. */
@property (nonatomic, copy, nullable) NSString *code;

/*! Redirect URI (must match PAR request). */
@property (nonatomic, copy, nullable) NSString *redirectUri;

/*! PKCE code verifier for challenge validation. */
@property (nonatomic, copy, nullable) NSString *codeVerifier;

/*! OAuth client ID. */
@property (nonatomic, copy, nullable) NSString *clientId;

/*! Client assertion JWT for authentication. */
@property (nonatomic, copy, nullable) NSString *clientAssertion;

/*! DPoP proof JWT for token binding. */
@property (nonatomic, copy, nullable) NSString *dpopJwt;

/*! Refresh token for token refresh grant. */
@property (nonatomic, copy, nullable) NSString *refreshToken;

/*! Validate request parameters. */
- (BOOL)validateWithError:(NSError **)error;

@end

/*!
 @class OAuthPARService

 @abstract Service for Pushed Authorization Requests.

 @discussion Handles PAR endpoint, creates sessions, issues request_uri
 tokens, and generates authorization codes.
 */
@interface OAuthPARService : NSObject

/*! Process PAR request and create session. */
- (nullable OAuthSession *)handlePARRequest:(OAuthPARRequest *)request error:(NSError **)error;

/*! Retrieve session by request_uri. */
- (nullable OAuthSession *)getSessionByRequestUri:(NSString *)requestUri error:(NSError **)error;

/*! Generate authorization code for authenticated session. */
- (nullable NSString *)createAuthorizationCodeForSession:(OAuthSession *)session error:(NSError **)error;

@end

/*!
 @class OAuthTokenService

 @abstract Service for token endpoint operations.

 @discussion Exchanges authorization codes for tokens, validates PKCE and
 DPoP, issues access/refresh tokens, and handles token refresh.
 */
@interface OAuthTokenService : NSObject

/*! Process token request and issue tokens. */
- (NSDictionary *)handleTokenRequest:(OAuthTokenRequest *)request
                        session:(nullable OAuthSession *)session
                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
