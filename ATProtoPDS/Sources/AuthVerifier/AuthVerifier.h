/*!
 @file AuthVerifier.h

 @abstract Reusable token verification for ATProto resource servers.

 @discussion AuthVerifier provides token verification logic that can be used by
 PDS, AppView, Relay, or any ATProto resource server. It verifies:
 - JWT access tokens (signature, expiration, issuer, audience)
 - DPoP proofs (binding to access token)
 - Account policies (takedown status, admin)

 The verifier depends on protocol interfaces, allowing reuse across server types.
 For PDS-specific policies (database checks), use PDSAuth adapters.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TokenKeyResolver;
@protocol AccountPolicy;
@protocol DPoPNonceStore;

@class HttpRequest;
@class HttpResponse;
@class JWT;

extern NSString * const AuthVerifierErrorDomain;

typedef NS_ENUM(NSInteger, AuthVerifierError) {
    AuthVerifierErrorInvalidRequest = -1,
    AuthVerifierErrorInvalidToken = -2,
    AuthVerifierErrorTokenExpired = -3,
    AuthVerifierErrorInvalidSignature = -4,
    AuthVerifierErrorInvalidIssuer = -5,
    AuthVerifierErrorInvalidAudience = -6,
    AuthVerifierErrorDPoPRequired = -7,
    AuthVerifierErrorDPoPMissing = -8,
    AuthVerifierErrorDPoPInvalid = -9,
    AuthVerifierErrorDPoPThumbprintMismatch = -10,
    AuthVerifierErrorAccountTakedown = -11,
    AuthVerifierErrorAccountNotFound = -12
};

@class AuthVerifierPrincipal;

/*!
 @class AuthVerifierPrincipal
 
 @abstract Represents an authenticated principal from token verification.
 */
@interface AuthVerifierPrincipal : NSObject

/*! The authenticated DID. */
@property (nonatomic, copy, readonly) NSString *did;

/*! The access token JWT (for audit logging). */
@property (nonatomic, copy, readonly, nullable) NSString *accessTokenJWT;

/*! Token claims dictionary. */
@property (nonatomic, copy, readonly, nullable) NSDictionary *tokenClaims;

/*! The DPoP key thumbprint if DPoP was used. */
@property (nonatomic, copy, readonly, nullable) NSString *dpopThumbprint;

/*! Whether DPoP binding was enforced. */
@property (nonatomic, assign, readonly) BOOL usedDPoP;

/*! Whether this is an admin request. */
@property (nonatomic, assign, readonly) BOOL isAdmin;

- (instancetype)initWithDID:(NSString *)did
                accessTokenJWT:(nullable NSString *)accessTokenJWT
                 tokenClaims:(nullable NSDictionary *)tokenClaims
              dpopThumbprint:(nullable NSString *)dpopThumbprint
                     usedDPoP:(BOOL)usedDPoP
                      isAdmin:(BOOL)isAdmin;

@end


/*!
 @class AuthVerifier
 
 @abstract Reusable token verifier for ATProto resource servers.
 
 @discussion This class verifies incoming requests to ATProto XRPC endpoints.
 It supports both Bearer tokens and DPoP-bound access tokens.
 
 The verifier uses protocols for external dependencies:
 - TokenKeyResolver: For resolving JWKS from other issuers
 - AccountPolicy: For checking account status (takedown, admin)
 - DPoPNonceStore: For DPoP nonce validation (optional)
 
 For PDS, use PDSAccountPolicy which connects to PDSDatabase.
 */
@interface AuthVerifier : NSObject

/*!
 @brief The expected audience for access tokens.
 @discussion This should match the server's own DID (e.g., "did:web:pds.example.com").
 */
@property (nonatomic, copy) NSString *expectedAudience;

/*!
 @brief Allowed issuers for access tokens.
 @discussion Tokens from other ATProto PDS servers may be accepted if listed.
 */
@property (nonatomic, copy) NSArray<NSString *> *allowedIssuers;

/*!
 @brief Whether to require DPoP for all requests.
 @discussion Default is NO (DPoP is optional but recommended).
 */
@property (nonatomic, assign) BOOL requireDPoP;

/*!
 @brief Initialize with protocols.
 @param keyResolver For resolving JWKS from other servers (optional for single-issuer).
 @param accountPolicy For checking account status (takedown, admin).
 @param nonceStore For DPoP nonce validation (optional).
 */
- (instancetype)initWithKeyResolver:(nullable id<TokenKeyResolver>)keyResolver
                      accountPolicy:(id<AccountPolicy>)accountPolicy
                         nonceStore:(nullable id<DPoPNonceStore>)nonceStore;

/*!
 @brief Verify an incoming request.
 @param request The HTTP request.
 @param response The HTTP response (for setting auth headers like DPoP-Nonce).
 @param error Set on failure.
 @return Authenticated principal, or nil if verification failed.
 */
- (nullable AuthVerifierPrincipal *)verifyRequest:(HttpRequest *)request
                                         response:(nullable HttpResponse *)response
                                            error:(NSError **)error;

/*!
 @brief Verify just an access token (without DPoP).
 @param token The JWT access token string.
 @param error Set on failure.
 @return Authenticated principal, or nil if verification failed.
 */
- (nullable AuthVerifierPrincipal *)verifyAccessToken:(nullable NSString *)token
                                               error:(NSError **)error;

/*!
 @brief Extract authorization header and verify request.
 @param authHeader The Authorization header value.
 @param dpopHeader The DPoP header value (if present).
 @param request The HTTP request for URL/method.
 @param response The HTTP response (optional).
 @param error Set on failure.
 @return Authenticated principal, or nil if verification failed.
 */
- (nullable AuthVerifierPrincipal *)verifyAuthHeader:(nullable NSString *)authHeader
                                            dpopHeader:(nullable NSString *)dpopHeader
                                              request:(nullable HttpRequest *)request
                                             response:(nullable HttpResponse *)response
                                                error:(NSError **)error;

/*!
 @brief Construct the expected DPoP URL for a request.
 @param request The HTTP request.
 @return The canonical URL for DPoP verification.
 */
- (nullable NSURL *)expectedDPoPURLForRequest:(HttpRequest *)request;

/*!
 @brief Set the JWT verification key for local issuer.
 @param publicKey The public key for verifying tokens.
 */
- (void)setLocalPublicKey:(nullable id)publicKey;

/*!
 @brief Set the issuer for local token verification.
 @param issuer The issuer URL (e.g., "https://pds.example.com").
 */
- (void)setLocalIssuer:(NSString *)issuer;

@end

NS_ASSUME_NONNULL_END
