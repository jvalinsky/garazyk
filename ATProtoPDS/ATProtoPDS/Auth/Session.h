#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SessionErrorDomain;

typedef NS_ENUM(NSInteger, SessionError) {
    SessionErrorInvalidToken = 1000,
    SessionErrorTokenExpired,
    SessionErrorInvalidSession,
    SessionErrorSessionNotFound,
    SessionErrorInvalidScope,
    SessionErrorRevoked,
    SessionErrorConcurrencyConflict
};

@interface SessionToken : NSObject

@property (nonatomic, copy) NSString *value;
@property (nonatomic, strong) NSDate *issuedAt;
@property (nonatomic, strong) NSDate *expiresAt;
@property (nonatomic, copy, nullable) NSString *scope;
@property (nonatomic, assign) BOOL isRefreshToken;

+ (nullable instancetype)tokenWithValue:(NSString *)value
                              expiresIn:(NSTimeInterval)expiresIn
                                  scope:(nullable NSString *)scope
                          isRefreshToken:(BOOL)isRefreshToken;

- (BOOL)isExpired;
- (BOOL)isValid;

@end

@interface Session : NSObject

@property (nonatomic, copy, readonly) NSString *sessionID;
@property (nonatomic, copy, readonly) NSString *did;
@property (nonatomic, copy, readonly) NSString *handle;
@property (nonatomic, copy, readonly) NSString *accessToken;
@property (nonatomic, copy, readonly, nullable) NSString *refreshToken;
@property (nonatomic, copy, readonly) NSString *tokenType;
@property (nonatomic, copy, readonly) NSString *scope;
@property (nonatomic, strong, readonly) NSDate *createdAt;
@property (nonatomic, strong, readonly) NSDate *accessTokenExpiresAt;
@property (nonatomic, strong, readonly, nullable) NSDate *refreshTokenExpiresAt;
@property (nonatomic, copy, readonly, nullable) NSString *dpopKeyThumbprint;

+ (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope;

- (instancetype)initWithDID:(NSString *)did
                     handle:(NSString *)handle
                      scope:(NSString *)scope;

- (NSDictionary *)toTokenResponse;
- (NSDictionary *)toBearerTokenResponse;

@end

@interface SessionStore : NSObject

@property (nonatomic, assign) NSTimeInterval accessTokenLifetime;
@property (nonatomic, assign) NSTimeInterval refreshTokenLifetime;

- (nullable Session *)createSessionForDID:(NSString *)did
                                   handle:(NSString *)handle
                                    scope:(NSString *)scope
                                  dpopJWK:(nullable NSDictionary *)dpopJWK;

- (nullable Session *)getSessionByAccessToken:(NSString *)accessToken error:(NSError **)error;
- (nullable Session *)getSessionByRefreshToken:(NSString *)refreshToken error:(NSError **)error;
- (nullable Session *)getSessionByID:(NSString *)sessionID error:(NSError **)error;

- (BOOL)revokeSession:(NSString *)sessionID error:(NSError **)error;
- (BOOL)refreshSession:(NSString *)sessionID
                 scope:(nullable NSString *)newScope
               dpopJWK:(nullable NSDictionary *)dpopJWK
           newSession:(Session **)newSession
                 error:(NSError **)error;

- (NSArray<Session *> *)getSessionsForDID:(NSString *)did error:(NSError **)error;
- (NSArray<Session *> *)allActiveSessions:(NSError **)error;

- (NSTimeInterval)clockSkew;
- (void)setClockSkew:(NSTimeInterval)clockSkew;

@end

NS_ASSUME_NONNULL_END
