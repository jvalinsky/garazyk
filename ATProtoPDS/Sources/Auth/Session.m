#import "Auth/Session.h"
#import "Auth/JWT.h"
#import "Auth/KeyManager.h"

NSString * const SessionErrorDomain = @"com.atproto.pds.session";

@implementation SessionToken

+ (nullable instancetype)tokenWithValue:(NSString *)value
                              expiresIn:(NSTimeInterval)expiresIn
                                  scope:(nullable NSString *)scope
                          isRefreshToken:(BOOL)isRefreshToken {
    if (!value || expiresIn <= 0) return nil;

    SessionToken *token = [[SessionToken alloc] init];
    token.value = value;
    token.issuedAt = [NSDate date];
    token.expiresAt = [NSDate dateWithTimeIntervalSinceNow:expiresIn];
    token.scope = scope;
    token.isRefreshToken = isRefreshToken;

    return token;
}

- (BOOL)isExpired {
    return [self.expiresAt compare:[NSDate date]] == NSOrderedAscending;
}

- (BOOL)isValid {
    return !self.isExpired;
}

@end

@interface Session ()
@property (nonatomic, copy, readwrite) NSString *sessionID;
@property (nonatomic, copy, readwrite) NSString *did;
@property (nonatomic, copy, readwrite) NSString *handle;
@property (nonatomic, copy, readwrite) NSString *accessToken;
@property (nonatomic, copy, readwrite, nullable) NSString *refreshToken;
@property (nonatomic, copy, readwrite) NSString *tokenType;
@property (nonatomic, copy, readwrite) NSString *scope;
@property (nonatomic, strong, readwrite) NSDate *createdAt;
@property (nonatomic, strong, readwrite) NSDate *accessTokenExpiresAt;
@property (nonatomic, strong, readwrite, nullable) NSDate *refreshTokenExpiresAt;
@property (nonatomic, strong) SessionToken *accessTokenData;
@property (nonatomic, strong, nullable) SessionToken *refreshTokenData;
@property (nonatomic, strong) KeyManager *keyManager;
@end

@implementation Session

@synthesize minter = _minter;

+ (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope {
    return [[Session alloc] initWithDID:did handle:handle scope:scope];
}

+ (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope
                                 minter:(nullable JWTMinter *)minter {
    return [[Session alloc] initWithDID:did handle:handle scope:scope minter:minter];
}

- (instancetype)initWithDID:(NSString *)did
                     handle:(NSString *)handle
                      scope:(NSString *)scope {
    return [self initWithDID:did handle:handle scope:scope minter:nil];
}

- (instancetype)initWithDID:(NSString *)did
                     handle:(NSString *)handle
                      scope:(NSString *)scope
                     minter:(nullable JWTMinter *)minter {
    self = [super init];
    if (self) {
        _sessionID = [[NSUUID UUID] UUIDString];
        _did = [did copy];
        _handle = [handle copy];
        _scope = [scope copy];
        _tokenType = @"Bearer";
        _createdAt = [NSDate date];
        _keyManager = [[KeyManager alloc] init];
        _minter = minter;

        [self mintTokens];
    }
    return self;
}

- (void)mintTokens {
    NSTimeInterval accessTokenLifetime = 3600;
    NSString *accessTokenValue = nil;
    
    if (self.minter) {
        NSError *error = nil;
        NSArray<NSString *> *scopes = [self.scope componentsSeparatedByString:@" "];
        JWT *jwt = [self.minter mintAccessTokenForDID:self.did
                                               handle:self.handle
                                               scopes:scopes
                                                 error:&error];
        if (jwt) {
            accessTokenValue = [jwt encodedToken];
            self.tokenType = @"DPoP"; // Standard for ATProto
        } else {
            NSLog(@"Warning: Failed to mint JWT access token: %@", error);
            accessTokenValue = [[NSUUID UUID] UUIDString];
        }
    } else {
        accessTokenValue = [[NSUUID UUID] UUIDString];
    }

    self.accessTokenData = [SessionToken tokenWithValue:accessTokenValue
                                              expiresIn:accessTokenLifetime
                                                  scope:self.scope
                                          isRefreshToken:NO];
    self.accessToken = self.accessTokenData.value;
    self.accessTokenExpiresAt = self.accessTokenData.expiresAt;

    NSTimeInterval refreshTokenLifetime = 86400 * 30;
    self.refreshTokenData = [SessionToken tokenWithValue:[[NSUUID UUID] UUIDString]
                                                 expiresIn:refreshTokenLifetime
                                                     scope:self.scope
                                             isRefreshToken:YES];
    self.refreshToken = self.refreshTokenData.value;
    self.refreshTokenExpiresAt = self.refreshTokenData.expiresAt;
}

- (instancetype)initWithDID:(NSString *)did
                     handle:(NSString *)handle
                      scope:(NSString *)scope
               accessToken:(NSString *)accessToken
              refreshToken:(nullable NSString *)refreshToken
          accessTokenExpiry:(NSDate *)accessTokenExpiry
         refreshTokenExpiry:(nullable NSDate *)refreshTokenExpiry {
    self = [super init];
    if (self) {
        _sessionID = [[NSUUID UUID] UUIDString];
        _did = [did copy];
        _handle = [handle copy];
        _scope = [scope copy];
        _accessToken = [accessToken copy];
        _refreshToken = [refreshToken copy];
        _tokenType = @"Bearer";
        _createdAt = [NSDate date];
        _accessTokenExpiresAt = accessTokenExpiry;
        _refreshTokenExpiresAt = refreshTokenExpiry;

        self.accessTokenData = [SessionToken tokenWithValue:accessToken
                                                   expiresIn:[accessTokenExpiry timeIntervalSinceNow]
                                                       scope:scope
                                               isRefreshToken:NO];
        if (refreshToken) {
            self.refreshTokenData = [SessionToken tokenWithValue:refreshToken
                                                         expiresIn:[refreshTokenExpiry timeIntervalSinceNow]
                                                             scope:scope
                                                     isRefreshToken:YES];
        }
    }
    return self;
}

- (NSDictionary *)toTokenResponse {
    NSMutableDictionary *response = [NSMutableDictionary dictionary];
    response[@"access_token"] = self.accessToken;
    response[@"token_type"] = self.tokenType;
    response[@"scope"] = self.scope;

    NSTimeInterval expiresIn = [self.accessTokenExpiresAt timeIntervalSinceNow];
    response[@"expires_in"] = @(MAX(0, (NSInteger)expiresIn));

    if (self.refreshToken) {
        response[@"refresh_token"] = self.refreshToken;
    }

    if (self.dpopKeyThumbprint) {
        response[@"dpop_key_thumbprint"] = self.dpopKeyThumbprint;
    }

    return response;
}

- (NSDictionary *)toBearerTokenResponse {
    return @{
        @"access_token": self.accessToken,
        @"token_type": self.tokenType,
        @"scope": self.scope,
        @"expires_in": @(MAX(0, (NSInteger)[self.accessTokenExpiresAt timeIntervalSinceNow]))
    };
}

- (BOOL)isAccessTokenValid {
    return [self.accessTokenData isValid];
}

- (BOOL)isRefreshTokenValid {
    return self.refreshTokenData && [self.refreshTokenData isValid];
}

- (NSString *)refreshAccessToken {
    NSTimeInterval accessTokenLifetime = 3600;
    self.accessTokenData = [SessionToken tokenWithValue:[[NSUUID UUID] UUIDString]
                                              expiresIn:accessTokenLifetime
                                                  scope:self.scope
                                          isRefreshToken:NO];
    self.accessToken = self.accessTokenData.value;
    self.accessTokenExpiresAt = self.accessTokenData.expiresAt;
    return self.accessToken;
}

@end

@interface SessionStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, Session *> *sessionsByAccessToken;
@property (nonatomic, strong) NSMutableDictionary<NSString *, Session *> *sessionsByRefreshToken;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<Session *> *> *sessionsByDID;
@property (nonatomic, strong) dispatch_queue_t accessQueue;
@property (nonatomic, assign) NSTimeInterval clockSkew;
@end

@implementation SessionStore

@synthesize minter = _minter;
@synthesize clockSkew = _clockSkew;

+ (instancetype)sharedStore {
    static SessionStore *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessionsByAccessToken = [NSMutableDictionary dictionary];
        _sessionsByRefreshToken = [NSMutableDictionary dictionary];
        _sessionsByDID = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.sessionstore", DISPATCH_QUEUE_SERIAL);
        _accessTokenLifetime = 3600;
        _refreshTokenLifetime = 86400 * 30;
        _clockSkew = 0;
    }
    return self;
}

- (nullable Session *)createSessionForDID:(NSString *)did
                                    handle:(NSString *)handle
                                     scope:(NSString *)scope
                                   dpopJWK:(nullable NSDictionary *)dpopJWK
                                     error:(NSError **)error {
    Session *session = [[Session alloc] initWithDID:did handle:handle scope:scope minter:self.minter];

    if (dpopJWK[@"kid"]) {
        session.dpopKeyThumbprint = dpopJWK[@"kid"];
    }

    dispatch_sync(self.accessQueue, ^{
        self.sessionsByAccessToken[session.accessToken] = session;
        if (session.refreshToken) {
            self.sessionsByRefreshToken[session.refreshToken] = session;
        }

        NSMutableArray *userSessions = self.sessionsByDID[did] ?: [NSMutableArray array];
        [userSessions addObject:session];
        self.sessionsByDID[did] = userSessions;
    });

    return session;
}

- (nullable Session *)createSessionForDID:(NSString *)did
                                    handle:(NSString *)handle
                                     scope:(NSString *)scope
                                   dpopJWK:(nullable NSDictionary *)dpopJWK {
    return [self createSessionForDID:did handle:handle scope:scope dpopJWK:dpopJWK error:nil];
}

- (nullable Session *)getSessionByAccessToken:(NSString *)accessToken error:(NSError **)error {
    __block Session *session = nil;

    dispatch_sync(self.accessQueue, ^{
        session = self.sessionsByAccessToken[accessToken];
    });

    if (!session) {
        if (error) {
            *error = [NSError errorWithDomain:SessionErrorDomain
                                         code:SessionErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid or expired access token"}];
        }
        return nil;
    }

    if ([session.accessTokenExpiresAt timeIntervalSinceNow] < -self.clockSkew) {
        if (error) {
            *error = [NSError errorWithDomain:SessionErrorDomain
                                         code:SessionErrorTokenExpired
                                     userInfo:@{NSLocalizedDescriptionKey: @"Access token expired"}];
        }
        return nil;
    }

    return session;
}

- (nullable Session *)getSessionByRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    __block Session *session = nil;

    dispatch_sync(self.accessQueue, ^{
        session = self.sessionsByRefreshToken[refreshToken];
    });

    if (!session) {
        if (error) {
            *error = [NSError errorWithDomain:SessionErrorDomain
                                         code:SessionErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid refresh token"}];
        }
        return nil;
    }

    if (![session isRefreshTokenValid]) {
        if (error) {
            *error = [NSError errorWithDomain:SessionErrorDomain
                                         code:SessionErrorTokenExpired
                                     userInfo:@{NSLocalizedDescriptionKey: @"Refresh token expired"}];
        }
        return nil;
    }

    return session;
}

- (nullable Session *)getSessionByID:(NSString *)sessionID error:(NSError **)error {
    __block Session *session = nil;

    dispatch_sync(self.accessQueue, ^{
        for (Session *s in self.sessionsByAccessToken.allValues) {
            if ([s.sessionID isEqualToString:sessionID]) {
                session = s;
                break;
            }
        }
    });

    if (!session && error) {
        *error = [NSError errorWithDomain:SessionErrorDomain
                                     code:SessionErrorSessionNotFound
                                 userInfo:@{NSLocalizedDescriptionKey: @"Session not found"}];
    }

    return session;
}

- (BOOL)revokeSession:(NSString *)sessionID error:(NSError **)error {
    Session *session = [self getSessionByID:sessionID error:nil];
    if (!session) {
        if (error) {
            *error = [NSError errorWithDomain:SessionErrorDomain
                                         code:SessionErrorSessionNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Session not found"}];
        }
        return NO;
    }

    dispatch_sync(self.accessQueue, ^{
        [self.sessionsByAccessToken removeObjectForKey:session.accessToken];
        if (session.refreshToken) {
            [self.sessionsByRefreshToken removeObjectForKey:session.refreshToken];
        }

        NSMutableArray *userSessions = self.sessionsByDID[session.did];
        [userSessions removeObject:session];
    });

    return YES;
}

- (BOOL)refreshSession:(NSString *)sessionID
                 scope:(nullable NSString *)newScope
               dpopJWK:(nullable NSDictionary *)dpopJWK
           newSession:(Session **)newSession
                 error:(NSError **)error {
    Session *existingSession = [self getSessionByID:sessionID error:error];
    if (!existingSession) return NO;

    if (![existingSession isRefreshTokenValid]) {
        if (error) {
            *error = [NSError errorWithDomain:SessionErrorDomain
                                         code:SessionErrorTokenExpired
                                     userInfo:@{NSLocalizedDescriptionKey: @"Refresh token expired"}];
        }
        return NO;
    }

    NSString *finalScope = newScope ?: existingSession.scope;

    dispatch_sync(self.accessQueue, ^{
        [self.sessionsByAccessToken removeObjectForKey:existingSession.accessToken];
        if (existingSession.refreshToken) {
            [self.sessionsByRefreshToken removeObjectForKey:existingSession.refreshToken];
        }
    });

    Session *refreshedSession = [self createSessionForDID:existingSession.did
                                                   handle:existingSession.handle
                                                    scope:finalScope
                                                  dpopJWK:dpopJWK];

    if (newSession) {
        *newSession = refreshedSession;
    }

    return YES;
}

- (NSArray<Session *> *)getSessionsForDID:(NSString *)did error:(NSError **)error {
    __block NSArray *sessions = @[];

    dispatch_sync(self.accessQueue, ^{
        NSArray *userSessions = self.sessionsByDID[did];
        sessions = [userSessions ?: @[] copy];
    });

    return sessions;
}

- (NSArray<Session *> *)allActiveSessions:(NSError **)error {
    __block NSArray *sessions = @[];

    dispatch_sync(self.accessQueue, ^{
        NSMutableArray *active = [NSMutableArray array];
        for (Session *session in self.sessionsByAccessToken.allValues) {
            if ([session isAccessTokenValid]) {
                [active addObject:session];
            }
        }
        sessions = [active copy];
    });

    return sessions;
}

- (NSTimeInterval)clockSkew {
    return _clockSkew;
}

- (void)setClockSkew:(NSTimeInterval)clockSkew {
    _clockSkew = clockSkew;
}

@end
