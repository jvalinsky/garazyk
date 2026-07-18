// SPDX-FileCopyrightText: 2024-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file Session.m

 @abstract Session and SessionToken management for authenticated users.

 @discussion This file implements session lifecycle management including token
 minting, validation, storage, and refresh. Sessions are created with both
 access tokens (short-lived) and refresh tokens (long-lived).

 @copyright Copyright (c) 2024-2026 Jack Valinsky
 */

#import "Auth/Session.h"
#import "Auth/JWT.h"
#import "Auth/PDSKeyManagerFactory.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Connection/ATProtoConnectionManagerSerial.h"
#import "Database/Utils/ATProtoDatabaseQueryRunner.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import <sqlite3.h>

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
@property (nonatomic, strong) id<PDSKeyManager> keyManager;
@end

@implementation Session

+ (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope
                      dpopKeyThumbprint:(nullable NSString *)jkt {
    return [[Session alloc] initWithDID:did handle:handle scope:scope dpopKeyThumbprint:jkt];
}

+ (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope {
    return [[Session alloc] initWithDID:did handle:handle scope:scope dpopKeyThumbprint:nil];
}

+ (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope
                                 minter:(nullable JWTMinter *)minter
                      dpopKeyThumbprint:(nullable NSString *)jkt {
    return [[Session alloc] initWithDID:did handle:handle scope:scope minter:minter dpopKeyThumbprint:jkt];
}

+ (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope
                                 minter:(nullable JWTMinter *)minter {
    return [[Session alloc] initWithDID:did handle:handle scope:scope minter:minter dpopKeyThumbprint:nil];
}

- (instancetype)initWithDID:(NSString *)did
                     handle:(NSString *)handle
                      scope:(NSString *)scope
          dpopKeyThumbprint:(nullable NSString *)jkt {
    return [self initWithDID:did handle:handle scope:scope minter:nil dpopKeyThumbprint:jkt];
}

- (instancetype)initWithDID:(NSString *)did
                     handle:(NSString *)handle
                      scope:(NSString *)scope {
    return [self initWithDID:did handle:handle scope:scope minter:nil dpopKeyThumbprint:nil];
}

- (instancetype)initWithDID:(NSString *)did
                     handle:(NSString *)handle
                      scope:(NSString *)scope
                     minter:(nullable JWTMinter *)minter
          dpopKeyThumbprint:(nullable NSString *)jkt {
    self = [super init];
    if (self) {
        _sessionID = [[NSUUID UUID] UUIDString];
        _did = [did copy];
        _handle = [handle copy];
        _scope = [scope copy];
        _tokenType = jkt ? @"DPoP" : @"Bearer";
        _createdAt = [NSDate date];
        _minter = minter;
        _dpopKeyThumbprint = [jkt copy];

        [self mintTokens];
    }
    return self;
}

- (instancetype)initWithDID:(NSString *)did
                     handle:(NSString *)handle
                      scope:(NSString *)scope
                     minter:(nullable JWTMinter *)minter {
    return [self initWithDID:did handle:handle scope:scope minter:minter dpopKeyThumbprint:nil];
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
                                            sessionID:self.sessionID
                                    dpopKeyThumbprint:self.dpopKeyThumbprint
                                                 error:&error];
        if (jwt) {
            accessTokenValue = [jwt encodedToken];
            self.tokenType = @"DPoP"; // Standard for ATProto
        } else {
            GZ_LOG_AUTH_WARN(@"Failed to mint JWT access token (falling back to UUID): %@", error);
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
    NSString *refreshTokenValue = nil;
    if (self.minter) {
        NSError *error = nil;
        NSArray<NSString *> *scopes = [self.scope componentsSeparatedByString:@" "];
        JWT *jwt = [self.minter mintRefreshTokenForDID:self.did
                                                 handle:self.handle
                                                 scopes:scopes
                                                  error:&error];
        if (jwt) {
            refreshTokenValue = [jwt encodedToken];
        } else {
            GZ_LOG_AUTH_WARN(@"Failed to mint JWT refresh token (falling back to UUID): %@", error);
            refreshTokenValue = [[NSUUID UUID] UUIDString];
        }
    } else {
        refreshTokenValue = [[NSUUID UUID] UUIDString];
    }

    self.refreshTokenData = [SessionToken tokenWithValue:refreshTokenValue
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
    [self mintTokens];
    return self.accessToken;
}

@end



#pragma mark - Storage Implementations

@interface PDSMemorySessionStorage ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, Session *> *sessionsByAccessToken;
@property (nonatomic, strong) NSMutableDictionary<NSString *, Session *> *sessionsByRefreshToken;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<Session *> *> *sessionsByDID;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t accessQueue;
@end

@implementation PDSMemorySessionStorage

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessionsByAccessToken = [NSMutableDictionary dictionary];
        _sessionsByRefreshToken = [NSMutableDictionary dictionary];
        _sessionsByDID = [NSMutableDictionary dictionary];
        _accessQueue = dispatch_queue_create("com.atproto.pds.memorystorage", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)saveSession:(Session *)session error:(NSError **)error {
    dispatch_sync(self.accessQueue, ^{
        self.sessionsByAccessToken[session.accessToken] = session;
        if (session.refreshToken) {
            self.sessionsByRefreshToken[session.refreshToken] = session;
        }
        
        // Remove existing session with same ID if present (update)
        NSMutableArray *userSessions = self.sessionsByDID[session.did];
        if (!userSessions) {
            userSessions = [NSMutableArray array];
            self.sessionsByDID[session.did] = userSessions;
        } else {
            // Check for duplicate by ID and remove if found
            for (NSInteger i = 0; i < userSessions.count; i++) {
                Session *existing = userSessions[i];
                if ([existing.sessionID isEqualToString:session.sessionID]) {
                    [userSessions removeObjectAtIndex:i];
                    break;
                }
            }
        }
        [userSessions addObject:session];
    });
    return YES;
}

- (nullable Session *)getSessionByAccessToken:(NSString *)token error:(NSError **)error {
    __block Session *session = nil;
    dispatch_sync(self.accessQueue, ^{
        session = self.sessionsByAccessToken[token];
    });
    return session;
}

- (nullable Session *)getSessionByRefreshToken:(NSString *)token error:(NSError **)error {
    __block Session *session = nil;
    dispatch_sync(self.accessQueue, ^{
        session = self.sessionsByRefreshToken[token];
    });
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
    return session;
}

- (BOOL)revokeSessionByID:(NSString *)sessionID error:(NSError **)error {
    __block BOOL found = NO;
    dispatch_sync(self.accessQueue, ^{
        Session *session = nil;
        for (Session *s in self.sessionsByAccessToken.allValues) {
            if ([s.sessionID isEqualToString:sessionID]) {
                session = s;
                break;
            }
        }
        
        if (session) {
            [self.sessionsByAccessToken removeObjectForKey:session.accessToken];
            if (session.refreshToken) {
                [self.sessionsByRefreshToken removeObjectForKey:session.refreshToken];
            }
            [self.sessionsByDID[session.did] removeObject:session];
            found = YES;
        }
    });
    return found;
}

- (NSArray<Session *> *)getSessionsForDID:(NSString *)did error:(NSError **)error {
    __block NSArray *sessions = nil;
    dispatch_sync(self.accessQueue, ^{
        sessions = [self.sessionsByDID[did] copy] ?: @[];
    });
    return sessions;
}

- (NSArray<Session *> *)allActiveSessions:(NSError **)error {
    __block NSMutableArray *sessions = [NSMutableArray array];
    dispatch_sync(self.accessQueue, ^{
        for (Session *s in self.sessionsByAccessToken.allValues) {
            if ([s isAccessTokenValid]) {
                [sessions addObject:s];
            }
        }
    });
    return sessions;
}

@end

@interface PDSSQLiteSessionStorage ()
@property (nonatomic, strong) ATProtoConnectionManagerSerial *connectionManager;
@property (nonatomic, strong) ATProtoDatabaseQueryRunner *queryRunner;
@end

@implementation PDSSQLiteSessionStorage

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _connectionManager = [[ATProtoConnectionManagerSerial alloc] initWithLabel:@"com.atproto.pds.session.storage"];
        NSError *error = nil;
        if (![_connectionManager openWithPath:path config:ATProtoDBConfigDefault error:&error]) {
            GZ_LOG_AUTH_ERROR(@"Failed to open session database: %@", error);
            return nil;
        }
        _queryRunner = [[ATProtoDatabaseQueryRunner alloc] initWithConnectionManager:_connectionManager
                                                                         errorDomain:@"com.atproto.pds.session.storage"];
        if (![self createSchema:&error]) {
            GZ_LOG_AUTH_ERROR(@"Failed to create sessions table: %@", error);
            [_connectionManager close];
            return nil;
        }
    }
    return self;
}

- (BOOL)createSchema:(NSError **)error {
    NSArray<NSString *> *statements = @[
        @"CREATE TABLE IF NOT EXISTS sessions ("
        @"  session_id TEXT PRIMARY KEY,"
        @"  did TEXT NOT NULL,"
        @"  handle TEXT NOT NULL,"
        @"  scope TEXT NOT NULL,"
        @"  access_token TEXT UNIQUE NOT NULL,"
        @"  refresh_token TEXT UNIQUE,"
        @"  access_token_expires_at REAL NOT NULL,"
        @"  refresh_token_expires_at REAL,"
        @"  dpop_key_thumbprint TEXT,"
        @"  token_type TEXT DEFAULT 'Bearer',"
        @"  created_at REAL NOT NULL"
        @")",
        @"CREATE INDEX IF NOT EXISTS idx_sessions_did ON sessions(did)",
        @"CREATE INDEX IF NOT EXISTS idx_sessions_access_token ON sessions(access_token)",
        @"CREATE INDEX IF NOT EXISTS idx_sessions_refresh_token ON sessions(refresh_token)",
    ];
    for (NSString *sql in statements) {
        if ([_queryRunner executeUpdate:sql params:nil error:error] < 0) {
            return NO;
        }
    }
    return YES;
}

- (void)dealloc {
    [_connectionManager close];
}

- (BOOL)saveSession:(Session *)session error:(NSError **)error {
    NSString *sql = @"INSERT INTO sessions (session_id, did, handle, scope, access_token, refresh_token, access_token_expires_at, refresh_token_expires_at, dpop_key_thumbprint, token_type, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(session_id) DO UPDATE SET did=excluded.did, handle=excluded.handle, scope=excluded.scope, access_token=excluded.access_token, refresh_token=excluded.refresh_token, access_token_expires_at=excluded.access_token_expires_at, refresh_token_expires_at=excluded.refresh_token_expires_at, dpop_key_thumbprint=excluded.dpop_key_thumbprint, token_type=excluded.token_type, created_at=excluded.created_at";
    NSArray *params = @[
        session.sessionID ?: [NSNull null],
        session.did ?: [NSNull null],
        session.handle ?: [NSNull null],
        session.scope ?: [NSNull null],
        session.accessToken ?: [NSNull null],
        session.refreshToken ?: [NSNull null],
        @(session.accessTokenExpiresAt.timeIntervalSince1970),
        session.refreshTokenExpiresAt ? @(session.refreshTokenExpiresAt.timeIntervalSince1970) : [NSNull null],
        session.dpopKeyThumbprint ?: [NSNull null],
        session.tokenType ?: [NSNull null],
        @(session.createdAt.timeIntervalSince1970),
    ];
    return [_queryRunner executeUpdate:sql params:params error:NULL] >= 0;
}

- (nullable Session *)sessionFromRow:(NSDictionary<NSString *, id> *)row {
    id did = row[@"did"], handle = row[@"handle"], scope = row[@"scope"], accessToken = row[@"access_token"];
    if (![did isKindOfClass:[NSString class]] || ![handle isKindOfClass:[NSString class]] ||
        ![scope isKindOfClass:[NSString class]] || ![accessToken isKindOfClass:[NSString class]]) {
        return nil;
    }

    id refreshToken = row[@"refresh_token"];
    NSDate *accessExpiry = [NSDate dateWithTimeIntervalSince1970:[row[@"access_token_expires_at"] doubleValue]];
    id refreshExpiryValue = row[@"refresh_token_expires_at"];
    NSDate *refreshExpiry = [refreshExpiryValue isKindOfClass:[NSNumber class]]
        ? [NSDate dateWithTimeIntervalSince1970:[refreshExpiryValue doubleValue]] : nil;

    Session *session = [[Session alloc] initWithDID:did
                                             handle:handle
                                              scope:scope
                                        accessToken:accessToken
                                       refreshToken:[refreshToken isKindOfClass:[NSString class]] ? refreshToken : nil
                                   accessTokenExpiry:accessExpiry
                                  refreshTokenExpiry:refreshExpiry];

    id sessionID = row[@"session_id"];
    if ([sessionID isKindOfClass:[NSString class]]) session.sessionID = sessionID;
    id dpop = row[@"dpop_key_thumbprint"];
    if ([dpop isKindOfClass:[NSString class]]) session.dpopKeyThumbprint = dpop;
    id type = row[@"token_type"];
    if ([type isKindOfClass:[NSString class]]) session.tokenType = type;

    return session;
}

- (nullable Session *)getSessionByAccessToken:(NSString *)token error:(NSError **)error {
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [_queryRunner executeQuery:@"SELECT * FROM sessions WHERE access_token = ?" params:@[token ?: [NSNull null]] error:NULL];
    return rows.count > 0 ? [self sessionFromRow:rows.firstObject] : nil;
}

- (nullable Session *)getSessionByRefreshToken:(NSString *)token error:(NSError **)error {
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [_queryRunner executeQuery:@"SELECT * FROM sessions WHERE refresh_token = ?" params:@[token ?: [NSNull null]] error:NULL];
    return rows.count > 0 ? [self sessionFromRow:rows.firstObject] : nil;
}

- (nullable Session *)getSessionByID:(NSString *)sessionID error:(NSError **)error {
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [_queryRunner executeQuery:@"SELECT * FROM sessions WHERE session_id = ?" params:@[sessionID ?: [NSNull null]] error:NULL];
    return rows.count > 0 ? [self sessionFromRow:rows.firstObject] : nil;
}

- (BOOL)revokeSessionByID:(NSString *)sessionID error:(NSError **)error {
    // Returns YES only when a row was actually deleted (sqlite3_changes > 0), so revoking
    // a missing session id reports NO.
    return [_queryRunner executeUpdate:@"DELETE FROM sessions WHERE session_id = ?"
                                params:@[sessionID ?: [NSNull null]]
                                 error:NULL] > 0;
}

- (NSArray<Session *> *)getSessionsForDID:(NSString *)did error:(NSError **)error {
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [_queryRunner executeQuery:@"SELECT * FROM sessions WHERE did = ?" params:@[did ?: [NSNull null]] error:NULL];
    return [self sessionsFromRows:rows];
}

- (NSArray<Session *> *)allActiveSessions:(NSError **)error {
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [_queryRunner executeQuery:@"SELECT * FROM sessions WHERE access_token_expires_at > ?"
                            params:@[@([[NSDate date] timeIntervalSince1970])]
                             error:NULL];
    return [self sessionsFromRows:rows];
}

- (NSArray<Session *> *)sessionsFromRows:(NSArray<NSDictionary<NSString *, id> *> *)rows {
    NSMutableArray<Session *> *sessions = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *row in rows) {
        Session *s = [self sessionFromRow:row];
        if (s) [sessions addObject:s];
    }
    return sessions;
}

@end

@interface SessionStore ()
@property (nonatomic, strong) id<PDSSessionStorage> storage;
@property (nonatomic, assign) NSTimeInterval clockSkew;
@end

@implementation SessionStore

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
    return [self initWithDatabasePath:nil];
}

- (instancetype)initWithDatabasePath:(nullable NSString *)path {
    self = [super init];
    if (self) {
        if (path) {
            _storage = [[PDSSQLiteSessionStorage alloc] initWithPath:path];
        } else {
            _storage = [[PDSMemorySessionStorage alloc] init];
        }
        
        if (!_storage) {
            return nil;
        }
        
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

    if (![self.storage saveSession:session error:error]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:SessionErrorDomain
                                         code:SessionErrorInvalidSession
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to persist session"}];
        }
        return nil;
    }

    return session;
}

- (nullable Session *)createSessionForDID:(NSString *)did
                                    handle:(NSString *)handle
                                     scope:(NSString *)scope
                                   dpopJWK:(nullable NSDictionary *)dpopJWK {
    return [self createSessionForDID:did handle:handle scope:scope dpopJWK:dpopJWK error:nil];
}

- (nullable Session *)getSessionByAccessToken:(NSString *)accessToken error:(NSError **)error {
    Session *session = [self.storage getSessionByAccessToken:accessToken error:error];

    if (!session) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:SessionErrorDomain
                                         code:SessionErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid or expired access token"}];
        }
        return nil;
    }
    
    session.minter = self.minter;

    if ([session.accessTokenExpiresAt timeIntervalSinceNow] < -self.clockSkew) {
        // ... unchanged ...
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
    Session *session = [self.storage getSessionByRefreshToken:refreshToken error:error];

    if (!session) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:SessionErrorDomain
                                         code:SessionErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid refresh token"}];
        }
        return nil;
    }
    
    session.minter = self.minter;

    if (![session isRefreshTokenValid]) {
        // ... unchanged ...
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
    Session *session = [self.storage getSessionByID:sessionID error:error];
    
    if (!session) {
        if (error && !*error) {
           *error = [NSError errorWithDomain:SessionErrorDomain
                                        code:SessionErrorSessionNotFound
                                    userInfo:@{NSLocalizedDescriptionKey: @"Session not found"}];
        }
        return nil;
    }
    
    session.minter = self.minter;

    return session;
}

- (BOOL)revokeSession:(NSString *)sessionID error:(NSError **)error {
    if (![self.storage revokeSessionByID:sessionID error:error]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:SessionErrorDomain
                                         code:SessionErrorSessionNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Session not found"}];
        }
        return NO;
    }
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

    // Delete old session
    [self.storage revokeSessionByID:sessionID error:nil];

    // Create new session
    Session *refreshedSession = [self createSessionForDID:existingSession.did
                                                   handle:existingSession.handle
                                                    scope:finalScope
                                                  dpopJWK:dpopJWK];

    if (newSession) {
        *newSession = refreshedSession;
    }

    return (refreshedSession != nil);
}

- (NSArray<Session *> *)getSessionsForDID:(NSString *)did error:(NSError **)error {
    NSArray<Session *> *sessions = [self.storage getSessionsForDID:did error:error];
    for (Session *session in sessions) {
        session.minter = self.minter;
    }
    return sessions;
}

- (NSArray<Session *> *)allActiveSessions:(NSError **)error {
    NSArray<Session *> *sessions = [self.storage allActiveSessions:error];
    for (Session *session in sessions) {
        session.minter = self.minter;
    }
    return sessions;
}

- (NSTimeInterval)clockSkew {
    return _clockSkew;
}

- (void)setClockSkew:(NSTimeInterval)clockSkew {
    _clockSkew = clockSkew;
}

@end
