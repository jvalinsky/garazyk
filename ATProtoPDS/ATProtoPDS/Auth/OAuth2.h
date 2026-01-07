#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const OAuth2ErrorDomain;

// Forward declarations
@class JWTMinter;
@class KeyManager;
@class DIDResolver;
@class HandleResolver;

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

extern NSString * const OAuth2ScopeIdentify;
extern NSString * const OAuth2ScopeSignIn;
extern NSString * const OAuth2ScopeRepoWrite;
extern NSString * const OAuth2ScopeRepoRead;
extern NSString * const OAuth2ScopeAtprotoProfile;

@class Session;

typedef void (^OAuth2AuthorizationCompletion)(NSURL * _Nullable authorizationURL, NSString * _Nullable authorizationCode, NSError * _Nullable error);
typedef void (^OAuth2TokenCompletion)(Session * _Nullable session, NSError * _Nullable error);
typedef void (^OAuth2RefreshCompletion)(NSString * _Nullable accessToken, NSError * _Nullable error);

@interface OAuth2AuthorizationRequest : NSObject

@property (nonatomic, copy) NSString *clientID;
@property (nonatomic, copy, nullable) NSString *redirectURI;
@property (nonatomic, copy, nullable) NSString *responseType;
@property (nonatomic, copy, nullable) NSString *scope;
@property (nonatomic, copy, nullable) NSString *state;
@property (nonatomic, copy, nullable) NSString *codeChallenge;
@property (nonatomic, copy, nullable) NSString *codeChallengeMethod;
@property (nonatomic, copy, nullable) NSString *nonce;
@property (nonatomic, copy, nullable) NSString *dpopJWK;
@property (nonatomic, copy, nullable) NSString *loginHint; // ATProto: account identifier (handle or DID)

- (NSURL *)authorizationURL;
- (NSDictionary *)toDictionary;

@end

@interface OAuth2AuthorizationResponse : NSObject

@property (nonatomic, copy, nullable) NSString *code;
@property (nonatomic, copy, nullable) NSString *state;
@property (nonatomic, copy, nullable) NSString *error;
@property (nonatomic, copy, nullable) NSString *errorDescription;
@property (nonatomic, strong, nullable) NSURL *redirectURI;

+ (nullable instancetype)responseFromURL:(NSURL *)url expectedState:(nullable NSString *)state error:(NSError **)error;

@end

@interface OAuth2TokenRequest : NSObject

@property (nonatomic, copy) NSString *grantType;
@property (nonatomic, copy, nullable) NSString *code;
@property (nonatomic, copy, nullable) NSString *redirectURI;
@property (nonatomic, copy, nullable) NSString *clientID;
@property (nonatomic, copy, nullable) NSString *codeVerifier;
@property (nonatomic, copy, nullable) NSString *refreshToken;
@property (nonatomic, copy, nullable) NSString *accessToken;
@property (nonatomic, copy, nullable) NSString *dpopProof;
@property (nonatomic, copy, nullable) NSString *scope;

- (NSDictionary *)toFormData;

@end

@interface OAuth2TokenResponse : NSObject

@property (nonatomic, copy, nullable) NSString *accessToken;
@property (nonatomic, copy, nullable) NSString *tokenType;
@property (nonatomic, copy, nullable) NSString *refreshToken;
@property (nonatomic, assign) NSTimeInterval expiresIn;
@property (nonatomic, copy, nullable) NSString *scope;
@property (nonatomic, copy, nullable) NSString *dpopKeyThumbprint;

+ (nullable instancetype)responseFromDictionary:(NSDictionary *)dictionary error:(NSError **)error;

@end

@interface OAuth2DPoPProof : NSObject

@property (nonatomic, copy) NSString *jwk;
@property (nonatomic, copy) NSString *htm;
@property (nonatomic, copy) NSString *htu;
@property (nonatomic, strong) NSDate *iat;

+ (nullable NSString *)createProofForURL:(NSURL *)url
                                method:(NSString *)method
                                  key:(NSDictionary *)jwk
                                 error:(NSError **)error;

@end

@interface OAuth2Server : NSObject

@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, copy) NSString *authorizationEndpoint;
@property (nonatomic, copy) NSString *tokenEndpoint;
@property (nonatomic, copy) NSString *jwksURI;
@property (nonatomic, assign) NSTimeInterval clockSkew;
@property (nonatomic, strong) NSMutableDictionary *authorizationCodes;
@property (nonatomic, strong) NSMutableDictionary *activeSessions;
@property (nonatomic, strong) JWTMinter *jwtMinter;
@property (nonatomic, strong) KeyManager *keyManager;
@property (nonatomic, strong) DIDResolver *didResolver; // ATProto: for identity resolution
@property (nonatomic, strong) HandleResolver *handleResolver; // ATProto: for identity resolution

- (instancetype)init;
- (void)handleAuthorizationRequest:(OAuth2AuthorizationRequest *)request
                        completion:(OAuth2AuthorizationCompletion)completion;
- (void)handleTokenRequest:(OAuth2TokenRequest *)request
                completion:(OAuth2TokenCompletion)completion;
- (void)refreshAccessToken:(NSString *)refreshToken
                     scope:(nullable NSString *)scope
                   dpopJWK:(nullable NSDictionary *)dpopJWK
                completion:(OAuth2RefreshCompletion)completion;

@end

NS_ASSUME_NONNULL_END
