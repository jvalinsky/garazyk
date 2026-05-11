// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file OAuthProvider.h

 @abstract OAuthProvider - Reusable Authorization Server for ATProto.

 @discussion This module provides a standalone OAuth 2.0 Authorization Server
 implementation that can be hosted by PDS or AppView servers. It depends only on
 protocol interfaces (not concrete PDS types), allowing reuse across server types.

 The OAuthProvider handles:
 - PAR (Pushed Authorization Requests)
 - Authorization code flow
 - Token issuance with DPoP binding
 - Refresh token rotation
 - Client registration and validation
 - JWKS publishing

 Host applications must provide implementations of the required protocols:
 - OAuthProviderStorage: Persistence for codes, tokens, grants
 - OAuthProviderClientRegistry: Client lookup and validation  
 - OAuthProviderTokenSigner: JWT signing and JWKS management
 - OAuthProviderUserAuthenticator: User credential verification
 - OAuthProviderDIDResolver: DID document resolution
 - OAuthProviderHandleResolver: Handle to DID resolution

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "OAuthProviderProtocols.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @constant OAuthProviderErrorDomain
 
 @abstract Error domain for OAuthProvider operations.
 */
extern NSString * const OAuthProviderErrorDomain;

/*!
 @enum OAuthProviderError
 
 @abstract Error codes for OAuthProvider operations.
 */
typedef NS_ENUM(NSInteger, OAuthProviderError) {
    OAuthProviderErrorInvalidRequest = -1,
    OAuthProviderErrorUnauthorizedClient = -2,
    OAuthProviderErrorUnsupportedResponseType = -3,
    OAuthProviderErrorInvalidScope = -4,
    OAuthProviderErrorServerError = -5,
    OAuthProviderErrorTemporarilyUnavailable = -6,
    OAuthProviderErrorInvalidGrant = -7,
    OAuthProviderErrorUnsupportedGrantType = -8,
    OAuthProviderErrorInvalidClient = -9,
    OAuthProviderErrorInvalidDPoPProof = -10,
    OAuthProviderErrorTokenExpired = -11,
    OAuthProviderErrorInvalidRedirectURI = -12,
    OAuthProviderErrorAccessDenied = -13,
    OAuthProviderErrorInteractionRequired = -14,
    OAuthProviderErrorConsentRequired = -15,
    OAuthProviderErrorInvalidToken = -16
};

#pragma mark - Request/Response Models

/*!
 @class OAuthProviderAuthorizationRequest
 
 @abstract Represents an incoming authorization request.
 */
@interface OAuthProviderAuthorizationRequest : NSObject

@property (nonatomic, copy) NSString *clientID;
@property (nonatomic, copy) NSString *redirectURI;
@property (nonatomic, copy) NSString *responseType;
@property (nonatomic, copy, nullable) NSString *scope;
@property (nonatomic, copy, nullable) NSString *state;
@property (nonatomic, copy, nullable) NSString *codeChallenge;
@property (nonatomic, copy, nullable) NSString *codeChallengeMethod;
@property (nonatomic, copy, nullable) NSString *nonce;
@property (nonatomic, copy, nullable) NSDictionary *dpopJWK;
@property (nonatomic, copy, nullable) NSString *loginHint;
@property (nonatomic, copy, nullable) NSString *prompt;

@end

/*!
 @class OAuthProviderAuthorizationResponse
 
 @abstract Represents the authorization endpoint response.
 */
@interface OAuthProviderAuthorizationResponse : NSObject

@property (nonatomic, strong, nullable) NSURL *redirectURI;
@property (nonatomic, copy, nullable) NSString *authorizationCode;
@property (nonatomic, copy, nullable) NSString *accessToken;
@property (nonatomic, copy, nullable) NSString *refreshToken;
@property (nonatomic, copy, nullable) NSString *idToken;
@property (nonatomic, copy, nullable) NSString *tokenType;
@property (nonatomic, assign) NSTimeInterval expiresIn;
@property (nonatomic, copy, nullable) NSString *scope;
@property (nonatomic, copy, nullable) NSString *state;
@property (nonatomic, copy, nullable) NSString *error;
@property (nonatomic, copy, nullable) NSString *errorDescription;

@end

/*!
 @class OAuthProviderTokenRequest
 
 @abstract Represents a token endpoint request.
 */
@interface OAuthProviderTokenRequest : NSObject

@property (nonatomic, copy) NSString *grantType;
@property (nonatomic, copy, nullable) NSString *authorizationCode;
@property (nonatomic, copy, nullable) NSString *redirectURI;
@property (nonatomic, copy, nullable) NSString *clientID;
@property (nonatomic, copy, nullable) NSString *clientSecret;
@property (nonatomic, copy, nullable) NSString *codeVerifier;
@property (nonatomic, copy, nullable) NSString *refreshToken;
@property (nonatomic, copy, nullable) NSString *scope;
@property (nonatomic, copy, nullable) NSString *dpopProof;
@property (nonatomic, copy, nullable) NSString *clientAssertion;
@property (nonatomic, copy, nullable) NSString *clientAssertionType;

@end

/*!
 @class OAuthProviderTokenResponse
 
 @abstract Represents a token endpoint response.
 */
@interface OAuthProviderTokenResponse : NSObject

@property (nonatomic, copy) NSString *accessToken;
@property (nonatomic, copy) NSString *refreshToken;
@property (nonatomic, copy) NSString *tokenType;
@property (nonatomic, assign) NSTimeInterval expiresIn;
@property (nonatomic, copy, nullable) NSString *scope;
@property (nonatomic, copy, nullable) NSString *idToken;
@property (nonatomic, copy, nullable) NSString *dpopNonce;
@property (nonatomic, copy, nullable) NSString *dpopKeyThumbprint;

@end

/*!
 @class OAuthProviderClientMetadata
 
 @abstract Represents OAuth client metadata (RFC 8414).
 */
@interface OAuthProviderClientMetadata : NSObject

@property (nonatomic, copy) NSString *clientID;
@property (nonatomic, copy) NSArray<NSString *> *redirectURIs;
@property (nonatomic, copy, nullable) NSString *clientName;
@property (nonatomic, copy, nullable) NSString *clientURI;
@property (nonatomic, copy, nullable) NSString *logoURI;
@property (nonatomic, copy, nullable) NSString *tosURI;
@property (nonatomic, copy, nullable) NSString *policyURI;
@property (nonatomic, copy, nullable) NSString *jwksURI;
@property (nonatomic, copy, nullable) NSDictionary *jwks;
@property (nonatomic, copy) NSString *tokenEndpointAuthMethod;
@property (nonatomic, copy, nullable) NSArray<NSString *> *grantTypes;
@property (nonatomic, copy, nullable) NSArray<NSString *> *responseTypes;
@property (nonatomic, copy, nullable) NSArray<NSString *> *contacts;
@property (nonatomic, copy, nullable) NSString *softwareID;
@property (nonatomic, copy, nullable) NSString *softwareVersion;

+ (nullable instancetype)metadataFromDictionary:(NSDictionary *)dict error:(NSError **)error;
- (NSDictionary *)toDictionary;

@end

#pragma mark - Completion Handlers

typedef void (^OAuthProviderAuthorizationCompletion)(NSURL * _Nullable redirectURI, NSString * _Nullable authCode, NSError * _Nullable error);
typedef void (^OAuthProviderTokenCompletion)(OAuthProviderTokenResponse * _Nullable response, NSError * _Nullable error);

#pragma mark - OAuthProvider Server

/*!
 @class OAuthProviderServer
 
 @abstract Main OAuth 2.0 Authorization Server implementation.
 
 @discussion This class implements the OAuth 2.0 authorization server logic.
 It is initialized with protocol implementations for storage, client registry,
 token signing, and user authentication. This design allows the same server
 code to be used by PDS (now) and AppView (future) without modification.
 
 The server does NOT handle HTTP directly. Instead, it provides methods that
 HTTP handlers (like OAuthProviderRoutes) call with parsed request data.
 */
@interface OAuthProviderServer : NSObject

- (instancetype)init NS_UNAVAILABLE;

/*!
 @brief The issuer URL for this authorization server.
 */
@property (nonatomic, copy) NSString *issuer;

/*!
 @brief Supported token endpoint auth methods.
 */
@property (nonatomic, copy) NSArray<NSString *> *supportedTokenEndpointAuthMethods;

/*!
 @brief Initialize with protocol implementations.
 @param storage Storage for codes, tokens, grants.
 @param clientRegistry Client lookup and validation.
 @param tokenSigner JWT signing and JWKS.
 @param userAuthenticator User credential verification.
 @param didResolver DID document resolution (optional).
 @param handleResolver Handle to DID resolution (optional).
 */
- (instancetype)initWithStorage:(id<OAuthProviderStorage>)storage
                 clientRegistry:(id<OAuthProviderClientRegistry>)clientRegistry
                   tokenSigner:(id<OAuthProviderTokenSigner>)tokenSigner
             userAuthenticator:(id<OAuthProviderUserAuthenticator>)userAuthenticator
                   didResolver:(nullable id<OAuthProviderDIDResolver>)didResolver
               handleResolver:(nullable id<OAuthProviderHandleResolver>)handleResolver;

/*!
 @brief Process a PAR (Pushed Authorization Request).
 @param requestData The PAR request parameters.
 @param completion Called with request_uri or error.
 */
- (void)processPAR:(NSDictionary *)requestData
        completion:(void (^)(NSString * _Nullable requestURI, NSDate * _Nullable expiresIn, NSError * _Nullable error))completion;

/*!
 @brief Process an authorization request.
 @param request The parsed authorization request.
 @param completion Called with redirect URI and auth code, or error.
 */
- (void)processAuthorizationRequest:(OAuthProviderAuthorizationRequest *)request
                         completion:(OAuthProviderAuthorizationCompletion)completion;

/*!
 @brief Process a token request.
 @param request The parsed token request.
 @param completion Called with token response or error.
 */
- (void)processTokenRequest:(OAuthProviderTokenRequest *)request
                  completion:(OAuthProviderTokenCompletion)completion;

/*!
 @brief Get server metadata for discovery endpoint.
 @return RFC 8414 server metadata dictionary.
 */
- (NSDictionary *)serverMetadata;

/*!
 @brief Get JWKS for the token signing keys.
 @return JWKS dictionary for the jwks_uri endpoint.
 */
- (NSDictionary *)jwks;

/*!
 @brief Revoke a token.
 @param token The token to revoke (access or refresh).
 @param tokenTypeHint Hint about token type (optional).
 @param completion Called with success/failure.
 */
- (void)revokeToken:(NSString *)token
       tokenTypeHint:(nullable NSString *)tokenTypeHint
         completion:(void (^)(NSError * _Nullable error))completion;

/*!
 @brief Introspect a token.
 @param token The token to introspect.
 @param completion Called with introspection result or error.
 */
- (void)introspectToken:(NSString *)token
             completion:(void (^)(NSDictionary * _Nullable introspection, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
