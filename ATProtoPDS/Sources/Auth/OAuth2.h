#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @header OAuth2.h
 
 @abstract OAuth 2.0 with DPoP implementation for ATProto.
 
 @discussion This header defines the OAuth 2.0 authorization server
 implementation with DPoP (Demonstration of Proof-of-Possession) for
 ATProto authentication. Includes authorization requests/responses,
 token management, and DPoP proof generation.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

extern NSString * const OAuth2ErrorDomain;

// Forward declarations
@class JWTMinter;
@class KeyManager;
@class DIDResolver;
@class HandleResolver;
@class Session;
@class PDSDatabase;

/*!
 @enum OAuth2Error
 
 @abstract Error codes for OAuth 2.0 operations.
 
 @constant OAuth2ErrorInvalidRequest The request is missing required parameters.
 @constant OAuth2ErrorUnauthorizedClient The client is not authorized.
 @constant OAuth2ErrorUnsupportedResponseType The response type is not supported.
 @constant OAuth2ErrorInvalidScope The requested scope is invalid.
 @constant OAuth2ErrorServerError An internal server error occurred.
 @constant OAuth2ErrorTemporarilyUnavailable The server is temporarily unavailable.
 @constant OAuth2ErrorInvalidGrant The authorization grant is invalid.
 @constant OAuth2ErrorUnsupportedGrantType The grant type is not supported.
 @constant OAuth2ErrorInvalidClient The client credentials are invalid.
 @constant OAuth2ErrorInvalidDPoPProof The DPoP proof is invalid.
 @constant OAuth2ErrorTokenExpired The token has expired.
 @constant OAuth2ErrorInvalidRedirectURI The redirect URI is invalid.
 @constant OAuth2ErrorAccessDenied The resource owner denied the request.
 @constant OAuth2ErrorInteractionRequired Interaction is required.
 @constant OAuth2ErrorConsentRequired User consent is required.
 */
typedef NS_ENUM(NSInteger, OAuth2Error) {
    OAuth2ErrorInvalidRequest = 1000,
    OAuth2ErrorUnauthorizedClient,
    OAuth2ErrorUnsupportedResponseType,
    OAuth2ErrorInvalidScope,
    OAuth2ErrorServerError,
    OAuth2ErrorTemporarilyUnavailable,
    OAuth2ErrorInvalidGrant,
    OAuth2ErrorUnsupportedGrantType,
    OAuth2ErrorInvalidClient,
    OAuth2ErrorInvalidDPoPProof,
    OAuth2ErrorTokenExpired,
    OAuth2ErrorInvalidRedirectURI,
    OAuth2ErrorAccessDenied,
    OAuth2ErrorInteractionRequired,
    OAuth2ErrorConsentRequired
};

/*!
 @constant OAuth2ScopeIdentify
 
 @abstract Scope for reading user identity information.
 */
extern NSString * const OAuth2ScopeIdentify;

/*!
 @constant OAuth2ScopeSignIn
 
 @abstract Scope for signing in to the PDS.
 */
extern NSString * const OAuth2ScopeSignIn;

/*!
 @constant OAuth2ScopeRepoWrite
 
 @abstract Scope for writing to user repositories.
 */
extern NSString * const OAuth2ScopeRepoWrite;

/*!
 @constant OAuth2ScopeRepoRead
 
 @abstract Scope for reading from user repositories.
 */
extern NSString * const OAuth2ScopeRepoRead;

/*!
 @constant OAuth2ScopeAtprotoProfile
 
 @abstract Scope for reading/writing ATProto profile.
 */
extern NSString * const OAuth2ScopeAtprotoProfile;

/*!
 @typedef OAuth2AuthorizationCompletion
 
 @abstract Completion handler for authorization requests.
 
 @param authorizationURL The authorization URL to redirect the user to.
 @param authorizationCode The authorization code (for code flow).
 @param error An error if the request failed.
 */
typedef void (^OAuth2AuthorizationCompletion)(NSURL * _Nullable authorizationURL, NSString * _Nullable authorizationCode, NSError * _Nullable error);

/*!
 @typedef OAuth2TokenCompletion
 
 @abstract Completion handler for token requests.
 
 @param session The created session with tokens.
 @param error An error if the request failed.
 */
typedef void (^OAuth2TokenCompletion)(Session * _Nullable session, NSError * _Nullable error);

/*!
 @typedef OAuth2RefreshCompletion
 
 @abstract Completion handler for token refresh requests.
 
 @param accessToken The new access token.
 @param error An error if the refresh failed.
 */
typedef void (^OAuth2RefreshCompletion)(NSString * _Nullable accessToken, NSError * _Nullable error);

/*!
 @class OAuth2AuthorizationRequest
 
 @abstract Represents an OAuth 2.0 authorization request.
 
 @discussion This class encapsulates all parameters for an authorization
 request including client ID, redirect URI, scope, and PKCE parameters.
 */
@interface OAuth2AuthorizationRequest : NSObject

/*! The client identifier for the requesting application. */
@property (nonatomic, copy) NSString *clientID;

/*! The URI to redirect to after authorization. */
@property (nonatomic, copy, nullable) NSString *redirectURI;

/*! The desired response type (e.g., "code" for authorization code flow). */
@property (nonatomic, copy, nullable) NSString *responseType;

/*! The requested OAuth scopes separated by spaces. */
@property (nonatomic, copy, nullable) NSString *scope;

/*! Opaque state value for CSRF protection. */
@property (nonatomic, copy, nullable) NSString *state;

/*! PKCE code challenge for proof key. */
@property (nonatomic, copy, nullable) NSString *codeChallenge;

/*! PKCE code challenge method ("S256" or "plain"). */
@property (nonatomic, copy, nullable) NSString *codeChallengeMethod;

/*! Nonce for state normalization. */
@property (nonatomic, copy, nullable) NSString *nonce;

/*! DPoP JWK for proof-of-possession. */
@property (nonatomic, copy, nullable) NSString *dpopJWK;

/*! Login hint for pre-filling user identifier. */
@property (nonatomic, copy, nullable) NSString *loginHint;

/*!
 @method authorizationURL
 
 @abstract Constructs the authorization URL.
 
 @return The complete URL for the authorization endpoint.
 */
- (NSURL *)authorizationURL;

/*!
 @method toDictionary
 
 @abstract Converts the request to a dictionary.
 
 @return Dictionary representation of the request.
 */
- (NSDictionary *)toDictionary;

@end

/*!
 @class OAuth2AuthorizationResponse
 
 @abstract Represents an OAuth 2.0 authorization response.
 
 @discussion This class parses authorization responses from redirect
 URLs and provides access to the authorization code or error details.
 */
@interface OAuth2AuthorizationResponse : NSObject

/*! The authorization code (for successful responses). */
@property (nonatomic, copy, nullable) NSString *code;

/*! The state value (for verification). */
@property (nonatomic, copy, nullable) NSString *state;

/*! Error code if authorization failed. */
@property (nonatomic, copy, nullable) NSString *error;

/*! Human-readable error description. */
@property (nonatomic, copy, nullable) NSString *errorDescription;

/*! The redirect URI if provided in the response. */
@property (nonatomic, strong, nullable) NSURL *redirectURI;

/*!
 @method responseFromURL:expectedState:error:
 
 @abstract Parses an authorization response from a URL.
 
 @param url The redirect URL containing the response.
 @param expectedState The expected state value for verification.
 @param error On return, contains an error if parsing failed.
 @return A new response object, or nil on failure.
 */
+ (nullable instancetype)responseFromURL:(NSURL *)url expectedState:(nullable NSString *)state error:(NSError **)error;

@end

/*!
 @class OAuth2TokenRequest
 
 @abstract Represents an OAuth 2.0 token request.
 
 @discussion This class encapsulates parameters for token endpoint
 requests including grant type, authorization code, and refresh tokens.
 */
@interface OAuth2TokenRequest : NSObject

/*! The grant type (e.g., "authorization_code", "refresh_token"). */
@property (nonatomic, copy) NSString *grantType;

/*! The authorization code for code flow. */
@property (nonatomic, copy, nullable) NSString *code;

/*! The redirect URI used in authorization. */
@property (nonatomic, copy, nullable) NSString *redirectURI;

/*! The client identifier. */
@property (nonatomic, copy, nullable) NSString *clientID;

/*! PKCE code verifier for proof key. */
@property (nonatomic, copy, nullable) NSString *codeVerifier;

/*! The refresh token for refreshing access. */
@property (nonatomic, copy, nullable) NSString *refreshToken;

/*! The access token for DPoP-bound requests. */
@property (nonatomic, copy, nullable) NSString *accessToken;

/*! The DPoP proof JWT. */
@property (nonatomic, copy, nullable) NSString *dpopProof;

/*! Thumbprint of the DPoP proof key. */
@property (nonatomic, copy, nullable) NSString *dpopKeyThumbprint;

/*! The requested scope for the new token. */
@property (nonatomic, copy, nullable) NSString *scope;

/*! The 2FA code (TOTP or backup code) if required. */
@property (nonatomic, copy, nullable) NSString *tfaCode;

/*!
 @method toFormData
 
 @abstract Converts the request to form-encoded data.
 
 @return Dictionary suitable for URL-encoded form body.
 */
- (NSDictionary *)toFormData;

@end

/*!
 @class OAuth2TokenResponse
 
 @abstract Represents an OAuth 2.0 token response.
 
 @discussion This class parses token endpoint responses and provides
 access to issued tokens and their metadata.
 */
@interface OAuth2TokenResponse : NSObject

/*! The issued access token. */
@property (nonatomic, copy, nullable) NSString *accessToken;

/*! The token type (typically "DPoP"). */
@property (nonatomic, copy, nullable) NSString *tokenType;

/*! The refresh token for obtaining new access tokens. */
@property (nonatomic, copy, nullable) NSString *refreshToken;

/*! Lifetime of the access token in seconds. */
@property (nonatomic, assign) NSTimeInterval expiresIn;

/*! The granted scope. */
@property (nonatomic, copy, nullable) NSString *scope;

/*! Thumbprint of the DPoP key. */
@property (nonatomic, copy, nullable) NSString *dpopKeyThumbprint;

/*!
 @method responseFromDictionary:error:
 
 @abstract Creates a response from a dictionary.
 
 @param dictionary The token response dictionary.
 @param error On return, contains an error if parsing failed.
 @return A new response object, or nil on failure.
 */
+ (nullable instancetype)responseFromDictionary:(NSDictionary *)dictionary error:(NSError **)error;

@end

/*!
 @class OAuth2DPoPProof
 
 @abstract Generates DPoP proof JWTs.
 
 @discussion DPoP (Demonstration of Proof-of-Possession) binds tokens
 to a public/private key pair, preventing token theft and misuse.
 */
@interface OAuth2DPoPProof : NSObject

/*! The JWK representing the proof key. */
@property (nonatomic, copy) NSString *jwk;

/*! The HTTP method the proof is for. */
@property (nonatomic, copy) NSString *htm;

/*! The URL the proof is for. */
@property (nonatomic, copy) NSString *htu;

/*! The timestamp when the proof was created. */
@property (nonatomic, strong) NSDate *iat;

/*!
 @method createProofForURL:method:key:error:
 
 @abstract Creates a DPoP proof JWT for a request.
 
 @param url The URL the proof will be used for.
 @param method The HTTP method (GET, POST, etc.).
 @param key The JWK to sign the proof with.
 @param error On return, contains an error if creation failed.
 @return The DPoP proof JWT string.
 */
+ (nullable NSString *)createProofForURL:(NSURL *)url
                                 method:(NSString *)method
                                   key:(NSDictionary *)jwk
                                  error:(NSError **)error;

/*!
 @method verifyProof:method:url:nonce:outThumbprint:error:
 
 @abstract Verifies a DPoP proof JWT and validates its claims.
 
 @param dpopJwt The proof JWT from the DPoP header.
 @param method The HTTP method the proof is for.
 @param url The URL the proof is for.
 @param nonce Optional server-provided nonce.
 @param thumbprint On return, the RFC 7638 JWK thumbprint if verification succeeds.
 @param error On return, contains an error if verification failed.
 @return YES if the proof is valid, NO otherwise.
 */
+ (BOOL)verifyProof:(NSString *)dpopJwt
              method:(NSString *)method
                 url:(NSURL *)url
               nonce:(nullable NSString *)nonce
        requireNonce:(BOOL)requireNonce
       outThumbprint:(NSString * _Nullable * _Nullable)thumbprint
               error:(NSError **)error;

+ (BOOL)verifyProof:(NSString *)dpopJwt
              method:(NSString *)method
                 url:(NSURL *)url
               nonce:(nullable NSString *)nonce
       outThumbprint:(NSString * _Nullable * _Nullable)thumbprint
               error:(NSError **)error;

@end

/*!
 @class OAuth2Server
 
 @abstract OAuth 2.0 authorization server implementation.
 
 @discussion OAuth2Server handles all authorization server operations
 including authorization requests, token issuance, and token refresh.
 It integrates with JWT minting, key management, and identity resolution.
 
 @code
 OAuth2Server *server = [[OAuth2Server alloc] init];
 server.issuer = @"https://pds.example.com";
 server.authorizationEndpoint = @"https://pds.example.com/oauth/authorize";
 server.tokenEndpoint = @"https://pds.example.com/oauth/token";
 
 [server handleAuthorizationRequest:request completion:^(URL, code, error) {
     // Redirect user to URL with code
 }];
 @endcode
 */
@interface OAuth2Server : NSObject

/*! The issuer identifier for this server. */
@property (nonatomic, copy) NSString *issuer;

/*! The authorization endpoint URL. */
@property (nonatomic, copy) NSString *authorizationEndpoint;

/*! The token endpoint URL. */
@property (nonatomic, copy) NSString *tokenEndpoint;

/*! The JWKS URI for publishing public keys. */
@property (nonatomic, copy) NSString *jwksURI;

/*! Allowed clock skew in seconds for validation. */
@property (nonatomic, assign) NSTimeInterval clockSkew;

/*! In-memory storage for authorization codes. */
@property (nonatomic, strong) NSMutableDictionary *authorizationCodes;

/*! In-memory storage for active sessions. */
@property (nonatomic, strong) NSMutableDictionary *activeSessions;

/*! Serial queue for thread-safe authorization code access. */
@property (nonatomic, strong, readonly) dispatch_queue_t authorizationQueue;

/*! Serial queue for thread-safe session access. */
@property (nonatomic, strong, readonly) dispatch_queue_t sessionQueue;

/*! JWT minting service. */
@property (nonatomic, strong, nullable) JWTMinter *jwtMinter;

/*! Key management service. */
@property (nonatomic, strong) KeyManager *keyManager;

/*! DID resolution service for identity verification. */
@property (nonatomic, strong) DIDResolver *didResolver;

/*! Handle resolution service. */
@property (nonatomic, strong) HandleResolver *handleResolver;

/*! Database accessor for account verification. */
@property (nonatomic, strong) PDSDatabase *database;

/*!
 @method init

 @abstract Initializes a new authorization server.

 @return An initialized OAuth2Server instance.
 */
- (instancetype)init;

/*!
 @method initWithDatabase:

 @abstract Initializes a new authorization server with a shared database.

 @param database The database to use for OAuth client storage.
 @return An initialized OAuth2Server instance.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

/*!
 @method handleAuthorizationRequest:completion:
 
 @abstract Processes an authorization request.
 
 @param request The authorization request parameters.
 @param completion Completion handler with URL or code.
 */
- (void)handleAuthorizationRequest:(OAuth2AuthorizationRequest *)request
                        completion:(OAuth2AuthorizationCompletion)completion;

/*!
 @method handleTokenRequest:completion:
 
 @abstract Processes a token request.
 
 @param request The token request parameters.
 @param completion Completion handler with session or error.
 */
- (void)handleTokenRequest:(OAuth2TokenRequest *)request
                completion:(OAuth2TokenCompletion)completion;

/*!
 @method refreshAccessToken:scope:dpopJWK:completion:
 
 @abstract Refreshes an access token.
 
 @param refreshToken The refresh token to use.
 @param scope Optional new scope for the token.
 @param dpopJWK Optional new DPoP key.
 @param completion Completion handler with new access token or error.
 */
- (void)refreshAccessToken:(NSString *)refreshToken
                     scope:(nullable NSString *)scope
                   dpopJWK:(nullable NSDictionary *)dpopJWK
                completion:(OAuth2RefreshCompletion)completion;

@end

NS_ASSUME_NONNULL_END
