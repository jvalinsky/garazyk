/**
 * @file OAuth2.h
 * @brief Implements the OAuth 2.0 authorization server for ATProto PDS.
 *
 * This header defines the core OAuth 2.0 protocol classes including authorization
 * requests and responses, token issuance, DPoP proof generation, and server-side
 * authorization code management. It supports the authorization code flow with
 * PKCE for secure token issuance.
 *
 * @note This implementation follows RFC 6749 and extends it with DPoP (RFC 9449)
 * for token binding and ATProto-specific identity resolution.
 * @see JWT.h
 * @see Session.h
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @brief Error domain for OAuth 2.0-related errors.
 */
extern NSString * const OAuth2ErrorDomain;

// Forward declarations
@class JWTMinter;
@class KeyManager;
@class DIDResolver;
@class HandleResolver;

/**
 * @brief Error codes for OAuth 2.0 operations.
 */
typedef NS_ENUM(NSInteger, OAuth2Error) {
    /** The request is missing a required parameter or is malformed. */
    OAuth2ErrorInvalidRequest = 1000,
    /** The authenticated client is not authorized to use this grant type. */
    OAuth2ErrorUnauthorizedClient,
    /** The server does not support the requested response type. */
    OAuth2ErrorUnsupportedResponseType,
    /** The requested scope is invalid, unknown, or malformed. */
    OAuth2ErrorInvalidScope,
    /** An internal server error occurred. */
    OAuth2ErrorServerError,
    /** The server is temporarily unavailable. */
    OAuth2ErrorTemporarilyUnavailable,
    /** The provided authorization grant is invalid or expired. */
    OAuth2ErrorInvalidGrant,
    /** The server does not support the requested grant type. */
    OAuth2ErrorUnsupportedGrantType,
    /** Client authentication failed. */
    OAuth2ErrorInvalidClient,
    /** The DPoP proof is invalid or malformed. */
    OAuth2ErrorInvalidDPoPProof,
    /** The access token has expired. */
    OAuth2ErrorTokenExpired,
    /** The redirect URI is invalid or not registered. */
    OAuth2ErrorInvalidRedirectURI,
    /** The resource owner denied the authorization request. */
    OAuth2ErrorAccessDenied,
    /** Interaction with the user is required to complete authorization. */
    OAuth2ErrorInteractionRequired,
    /** User consent is required before proceeding. */
    OAuth2ErrorConsentRequired
};

/**
 * @brief Predefined scope constants for ATProto authorization.
 */
extern NSString * const OAuth2ScopeIdentify;

/** Scope for signing in to the PDS. */
extern NSString * const OAuth2ScopeSignIn;

/** Scope for write access to the user's repository. */
extern NSString * const OAuth2ScopeRepoWrite;

/** Scope for read access to the user's repository. */
extern NSString * const OAuth2ScopeRepoRead;

/** Scope for access to the user's ATProto profile. */
extern NSString * const OAuth2ScopeAtprotoProfile;

@class Session;

/**
 * @brief Completion handler for authorization requests.
 *
 * @param authorizationURL The URL to redirect the user to for authorization, or nil.
 * @param authorizationCode The authorization code issued, or nil.
 * @param error An error if the operation failed, or nil.
 */
typedef void (^OAuth2AuthorizationCompletion)(NSURL * _Nullable authorizationURL, NSString * _Nullable authorizationCode, NSError * _Nullable error);

/**
 * @brief Completion handler for token requests.
 *
 * @param session The issued session with tokens, or nil.
 * @param error An error if the operation failed, or nil.
 */
typedef void (^OAuth2TokenCompletion)(Session * _Nullable session, NSError * _Nullable error);

/**
 * @brief Completion handler for token refresh requests.
 *
 * @param accessToken The new access token, or nil on failure.
 * @param error An error if the operation failed, or nil.
 */
typedef void (^OAuth2RefreshCompletion)(NSString * _Nullable accessToken, NSError * _Nullable error);

/**
 * @brief Represents an OAuth 2.0 authorization request.
 *
 * OAuth2AuthorizationRequest encapsulates all parameters needed to initiate
 * an authorization code flow, including client identification, redirect URI,
 * requested scopes, and PKCE parameters.
 */
@interface OAuth2AuthorizationRequest : NSObject

/** The client identifier for the requesting application. */
@property (nonatomic, copy) NSString *clientID;

/** The URI to redirect to after authorization completes. */
@property (nonatomic, copy, nullable) NSString *redirectURI;

/** The desired response type (e.g., "code" for authorization code flow). */
@property (nonatomic, copy, nullable) NSString *responseType;

/** The requested scopes as a space-separated string. */
@property (nonatomic, copy, nullable) NSString *scope;

/** Opaque state value for CSRF protection. */
@property (nonatomic, copy, nullable) NSString *state;

/** PKCE code challenge for secure token exchange. */
@property (nonatomic, copy, nullable) NSString *codeChallenge;

/** PKCE code challenge method (e.g., "S256" or "plain"). */
@property (nonatomic, copy, nullable) NSString *codeChallengeMethod;

/** Nonce value for ID token binding in hybrid flows. */
@property (nonatomic, copy, nullable) NSString *nonce;

/** DPoP JWK for DPoP-bound authorization. */
@property (nonatomic, copy, nullable) NSString *dpopJWK;

/** ATProto account identifier hint (handle or DID) for account selection. */
@property (nonatomic, copy, nullable) NSString *loginHint;

/**
 * @brief Constructs the authorization URL for this request.
 *
 * @return The fully formed authorization URL to redirect the user to.
 */
- (NSURL *)authorizationURL;

/**
 * @brief Converts the request to a dictionary representation.
 *
 * @return A dictionary suitable for serialization or logging.
 */
- (NSDictionary *)toDictionary;

@end

/**
 * @brief Represents the response from an authorization endpoint.
 *
 * OAuth2AuthorizationResponse encapsulates the results of an authorization
 * request, including authorization codes, errors, and state validation.
 */
@interface OAuth2AuthorizationResponse : NSObject

/** The authorization code issued by the server. */
@property (nonatomic, copy, nullable) NSString *code;

/** The state value for CSRF validation. */
@property (nonatomic, copy, nullable) NSString *state;

/** Error code if authorization failed. */
@property (nonatomic, copy, nullable) NSString *error;

/** Human-readable error description. */
@property (nonatomic, copy, nullable) NSString *errorDescription;

/** The redirect URI that was used or will be used. */
@property (nonatomic, strong, nullable) NSURL *redirectURI;

/**
 * @brief Parses an authorization response from a redirect URL.
 *
 * @param url The URL containing the authorization response parameters.
 * @param expectedState The expected state value for validation, or nil.
 * @param error On return, contains an error if parsing fails.
 * @return The parsed response, or nil if parsing failed.
 */
+ (nullable instancetype)responseFromURL:(NSURL *)url expectedState:(nullable NSString *)state error:(NSError **)error;

@end

/**
 * @brief Represents a token request to the token endpoint.
 *
 * OAuth2TokenRequest encapsulates all parameters needed to exchange an
 * authorization code for tokens or refresh an existing access token.
 */
@interface OAuth2TokenRequest : NSObject

/** The grant type (e.g., "authorization_code", "refresh_token"). */
@property (nonatomic, copy) NSString *grantType;

/** The authorization code for code grant exchanges. */
@property (nonatomic, copy, nullable) NSString *code;

/** The redirect URI used in the original request. */
@property (nonatomic, copy, nullable) NSString *redirectURI;

/** The client identifier. */
@property (nonatomic, copy, nullable) NSString *clientID;

/** PKCE code verifier for authorization code exchanges. */
@property (nonatomic, copy, nullable) NSString *codeVerifier;

/** The refresh token for token refresh requests. */
@property (nonatomic, copy, nullable) NSString *refreshToken;

/** The access token for token exchange requests. */
@property (nonatomic, copy, nullable) NSString *accessToken;

/** DPoP proof JWT for DPoP-bound token requests. */
@property (nonatomic, copy, nullable) NSString *dpopProof;

/** Requested scope for refresh or token exchange. */
@property (nonatomic, copy, nullable) NSString *scope;

/**
 * @brief Converts the request to form-encoded data.
 *
 * @return A dictionary suitable for application/x-www-form-urlencoded encoding.
 */
- (NSDictionary *)toFormData;

@end

/**
 * @brief Represents a successful token response from the server.
 *
 * OAuth2TokenResponse encapsulates the tokens and metadata returned by
 * the token endpoint, including access tokens, refresh tokens, and expiration.
 */
@interface OAuth2TokenResponse : NSObject

/** The issued access token. */
@property (nonatomic, copy, nullable) NSString *accessToken;

/** The token type (e.g., "Bearer", "DPoP"). */
@property (nonatomic, copy, nullable) NSString *tokenType;

/** The refresh token for obtaining new access tokens. */
@property (nonatomic, copy, nullable) NSString *refreshToken;

/** The lifetime in seconds for the access token. */
@property (nonatomic, assign) NSTimeInterval expiresIn;

/** The granted scope. */
@property (nonatomic, copy, nullable) NSString *scope;

/** The DPoP key thumbprint for DPoP-bound tokens. */
@property (nonatomic, copy, nullable) NSString *dpopKeyThumbprint;

/**
 * @brief Creates a token response from a dictionary.
 *
 * @param dictionary The dictionary containing token response data.
 * @param error On return, contains an error if parsing fails.
 * @return The parsed response, or nil if parsing failed.
 */
+ (nullable instancetype)responseFromDictionary:(NSDictionary *)dictionary error:(NSError **)error;

@end

/**
 * @brief Represents a DPoP proof JWT.
 *
 * OAuth2DPoPProof encapsulates the parameters needed to create a DPoP proof
 * JWT that binds tokens to a specific key pair.
 *
 * @see RFC 9449 for DPoP specification.
 */
@interface OAuth2DPoPProof : NSObject

/** The JSON Web Key as a JSON string. */
@property (nonatomic, copy) NSString *jwk;

/** The HTTP method for which this proof is valid. */
@property (nonatomic, copy) NSString *htm;

/** The HTTP URI (endpoint) for which this proof is valid. */
@property (nonatomic, copy) NSString *htu;

/** The issuance time of the proof. */
@property (nonatomic, strong) NSDate *iat;

/**
 * @brief Creates a DPoP proof JWT for the specified request.
 *
 * @param url The URL of the endpoint being accessed.
 * @param method The HTTP method of the request.
 * @param jwk The JWK to bind the proof to.
 * @param error On return, contains an error if creation fails.
 * @return The encoded DPoP proof JWT, or nil on failure.
 */
+ (nullable NSString *)createProofForURL:(NSURL *)url
                                 method:(NSString *)method
                                   key:(NSDictionary *)jwk
                                  error:(NSError **)error;

@end

/**
 * @brief The OAuth 2.0 authorization server implementation.
 *
 * OAuth2Server handles authorization requests, token issuance, and session
 * management. It integrates with JWT minting, key management, and ATProto
 * identity resolution to provide a complete OAuth 2.0 implementation.
 */
@interface OAuth2Server : NSObject

/** The issuer identifier for this server. */
@property (nonatomic, copy) NSString *issuer;

/** The authorization endpoint URL. */
@property (nonatomic, copy) NSString *authorizationEndpoint;

/** The token endpoint URL. */
@property (nonatomic, copy) NSString *tokenEndpoint;

/** The JWKS URI for public key discovery. */
@property (nonatomic, copy) NSString *jwksURI;

/** Allowed clock skew in seconds for time validation. */
@property (nonatomic, assign) NSTimeInterval clockSkew;

/** Internal storage for active authorization codes. */
@property (nonatomic, strong) NSMutableDictionary *authorizationCodes;

/** Internal storage for active sessions. */
@property (nonatomic, strong) NSMutableDictionary *activeSessions;

/** The JWT minting service. */
@property (nonatomic, strong) JWTMinter *jwtMinter;

/** The cryptographic key manager. */
@property (nonatomic, strong) KeyManager *keyManager;

/** The DID resolver for ATProto identity resolution. */
@property (nonatomic, strong) DIDResolver *didResolver;

/** The handle resolver for ATProto identity resolution. */
@property (nonatomic, strong) HandleResolver *handleResolver;

/**
 * @brief Initializes a new OAuth 2.0 server instance.
 *
 * @return The initialized server with default configuration.
 */
- (instancetype)init;

/**
 * @brief Processes an authorization request.
 *
 * @param request The authorization request to process.
 * @param completion The completion handler called with the result.
 */
- (void)handleAuthorizationRequest:(OAuth2AuthorizationRequest *)request
                        completion:(OAuth2AuthorizationCompletion)completion;

/**
 * @brief Processes a token request.
 *
 * @param request The token request to process.
 * @param completion The completion handler called with the result.
 */
- (void)handleTokenRequest:(OAuth2TokenRequest *)request
                completion:(OAuth2TokenCompletion)completion;

/**
 * @brief Refreshes an access token using a refresh token.
 *
 * @param refreshToken The refresh token to use.
 * @param scope Optional new scope to request.
 * @param dpopJWK Optional new DPoP key for the refreshed token.
 * @param completion The completion handler called with the result.
 */
- (void)refreshAccessToken:(NSString *)refreshToken
                      scope:(nullable NSString *)scope
                    dpopJWK:(nullable NSDictionary *)dpopJWK
                 completion:(OAuth2RefreshCompletion)completion;

@end

NS_ASSUME_NONNULL_END
