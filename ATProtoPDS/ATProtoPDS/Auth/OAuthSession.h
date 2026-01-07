#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const OAuthErrorDomain;

typedef NS_ENUM(NSInteger, OAuthError) {
    OAuthErrorInvalidRequest = 400,
    OAuthErrorUnauthorized = 401,
    OAuthErrorUnsupportedResponseType = 400,
    OAuthErrorInvalidScope = 400,
    OAuthErrorServerError = 500,
    OAuthErrorTemporarilyUnavailable = 503,
};

@interface OAuthSession : NSObject

@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, copy, nullable) NSString *clientId;
@property (nonatomic, copy, nullable) NSString *responseType;
@property (nonatomic, copy, nullable) NSString *redirectUri;
@property (nonatomic, copy, nullable) NSString *codeChallenge;
@property (nonatomic, copy, nullable) NSString *codeVerifier;
@property (nonatomic, copy, nullable) NSString *state;
@property (nonatomic, copy, nullable) NSString *scope;
@property (nonatomic, copy, nullable) NSString *loginHint;
@property (nonatomic, copy, nullable) NSString *authorizationCode;
@property (nonatomic, strong, nullable) NSDate *codeExpiresAt;
@property (nonatomic, copy, nullable) NSString *dpopNonce;
@property (nonatomic, copy, nullable) NSString *dpopKeyThumbprint;
@property (nonatomic, copy, nullable) NSString *dpopJwt;
@property (nonatomic, copy, nullable) NSString *accountDid;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, assign) BOOL authenticated;

+ (instancetype)sessionWithId:(NSString *)sessionId;

@end

@interface OAuthPARRequest : NSObject

@property (nonatomic, copy) NSString *clientId;
@property (nonatomic, copy) NSString *responseType;
@property (nonatomic, copy) NSString *codeChallenge;
@property (nonatomic, copy) NSString *codeChallengeMethod;
@property (nonatomic, copy) NSString *state;
@property (nonatomic, copy) NSString *redirectUri;
@property (nonatomic, copy) NSString *scope;
@property (nonatomic, copy, nullable) NSString *clientAssertion;
@property (nonatomic, copy, nullable) NSString *clientAssertionType;
@property (nonatomic, copy, nullable) NSString *loginHint;
@property (nonatomic, copy, nullable) NSString *dpopJwt;

- (BOOL)validateWithError:(NSError **)error;

@end

@interface OAuthTokenRequest : NSObject

@property (nonatomic, copy) NSString *grantType;
@property (nonatomic, copy, nullable) NSString *code;
@property (nonatomic, copy, nullable) NSString *redirectUri;
@property (nonatomic, copy, nullable) NSString *codeVerifier;
@property (nonatomic, copy, nullable) NSString *clientId;
@property (nonatomic, copy, nullable) NSString *clientAssertion;
@property (nonatomic, copy, nullable) NSString *dpopJwt;
@property (nonatomic, copy, nullable) NSString *refreshToken;

- (BOOL)validateWithError:(NSError **)error;

@end

@interface OAuthPARService : NSObject

- (nullable OAuthSession *)handlePARRequest:(OAuthPARRequest *)request error:(NSError **)error;
- (nullable OAuthSession *)getSessionByRequestUri:(NSString *)requestUri error:(NSError **)error;
- (nullable NSString *)createAuthorizationCodeForSession:(OAuthSession *)session error:(NSError **)error;

@end

@interface OAuthTokenService : NSObject

- (NSDictionary *)handleTokenRequest:(OAuthTokenRequest *)request
                        session:(nullable OAuthSession *)session
                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
