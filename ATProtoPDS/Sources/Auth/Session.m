/*!
 @file Session.m

 @abstract Session and SessionToken management for authenticated users.

 @discussion This file implements session lifecycle management including token
 minting, validation, storage, and refresh. Sessions are created with both
 access tokens (short-lived) and refresh tokens (long-lived).

 @copyright Copyright (c) 2024 Jack Myers
 */

#import "Auth/Session.h"
#import "Auth/JWT.h"
#import "Auth/KeyManager.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"
#import "Database/Utils/PDSSQLiteUtils.h"
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
@property (nonatomic, strong) KeyManager *keyManager;
@end

@implementation Session

@synthesize minter = _minter;

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
        _keyManager = [[KeyManager alloc] init];
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
                                    dpopKeyThumbprint:self.dpopKeyThumbprint
                                                 error:&error];
        if (jwt) {
            accessTokenValue = [jwt encodedToken];
            self.tokenType = @"DPoP"; // Standard for ATProto
        } else {
            PDS_LOG_AUTH_WARN(@"Failed to mint JWT access token (falling back to UUID): %@", error);
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

    self.refreshToken = [[NSUUID UUID] UUIDString];
    self.refreshTokenData = nil;

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
@property (nonatomic, assign) sqlite3 *db;
@end

@implementation PDSSQLiteSessionStorage

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        int rc = sqlite3_open(path.UTF8String, &_db);
        if (rc != SQLITE_OK) {
            PDS_LOG_AUTH_ERROR(@"Failed to open session database: %s", sqlite3_errmsg(_db));
            return nil;
        }
        sqlite3_exec(_db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
        
        const char *createSQL =
            "CREATE TABLE IF NOT EXISTS sessions ("
            "  session_id TEXT PRIMARY KEY,"
            "  did TEXT NOT NULL,"
            "  handle TEXT NOT NULL,"
            "  scope TEXT NOT NULL,"
            "  access_token TEXT UNIQUE NOT NULL,"
            "  refresh_token TEXT UNIQUE,"
            "  access_token_expires_at REAL NOT NULL,"
            "  refresh_token_expires_at REAL,"
            "  dpop_key_thumbprint TEXT,"
            "  token_type TEXT DEFAULT 'Bearer',"
            "  created_at REAL NOT NULL"
            ");"
            "CREATE INDEX IF NOT EXISTS idx_sessions_did ON sessions(did);"
            "CREATE INDEX IF NOT EXISTS idx_sessions_access_token ON sessions(access_token);"
            "CREATE INDEX IF NOT EXISTS idx_sessions_refresh_token ON sessions(refresh_token);";
            
        char *errMsg = NULL;
        if (sqlite3_exec(_db, createSQL, NULL, NULL, &errMsg) != SQLITE_OK) {
            PDS_LOG_AUTH_ERROR(@"Failed to create sessions table: %s", errMsg);
            sqlite3_free(errMsg);
            sqlite3_close(_db);
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (_db) {
        sqlite3_close(_db);
        _db = NULL;
    }
}

- (BOOL)saveSession:(Session *)session error:(NSError **)error {
    const char *sql = "INSERT OR REPLACE INTO sessions (session_id, did, handle, scope, access_token, refresh_token, access_token_expires_at, refresh_token_expires_at, dpop_key_thumbprint, token_type, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return NO;
    
    sqlite3_bind_text(stmt, 1, session.sessionID.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, session.did.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, session.handle.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, session.scope.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 5, session.accessToken.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (session.refreshToken) sqlite3_bind_text(stmt, 6, session.refreshToken.UTF8String, -1, SQLITE_TRANSIENT);
    else sqlite3_bind_null(stmt, 6);
    
    sqlite3_bind_double(stmt, 7, session.accessTokenExpiresAt.timeIntervalSince1970);
    
    if (session.refreshTokenExpiresAt) sqlite3_bind_double(stmt, 8, session.refreshTokenExpiresAt.timeIntervalSince1970);
    else sqlite3_bind_null(stmt, 8);
    
    if (session.dpopKeyThumbprint) sqlite3_bind_text(stmt, 9, session.dpopKeyThumbprint.UTF8String, -1, SQLITE_TRANSIENT);
    else sqlite3_bind_null(stmt, 9);
    
    sqlite3_bind_text(stmt, 10, session.tokenType.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 11, session.createdAt.timeIntervalSince1970);
    
    return sqlite3_step(stmt) == SQLITE_DONE;
}

- (Session *)sessionFromStatement:(sqlite3_stmt *)stmt {
    const char *did = (const char *)sqlite3_column_text(stmt, 1);
    const char *handle = (const char *)sqlite3_column_text(stmt, 2);
    const char *scope = (const char *)sqlite3_column_text(stmt, 3);
    const char *accessToken = (const char *)sqlite3_column_text(stmt, 4);
    const char *refreshToken = (const char *)sqlite3_column_text(stmt, 5);
    
    if (!did || !handle || !scope || !accessToken) return nil;
    
    NSDate *accessExpiry = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, 6)];
    NSDate *refreshExpiry = sqlite3_column_type(stmt, 7) != SQLITE_NULL ? [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, 7)] : nil;
    
    Session *session = [[Session alloc] initWithDID:[NSString stringWithUTF8String:did]
                                             handle:[NSString stringWithUTF8String:handle]
                                              scope:[NSString stringWithUTF8String:scope]
                                        accessToken:[NSString stringWithUTF8String:accessToken]
                                       refreshToken:refreshToken ? [NSString stringWithUTF8String:refreshToken] : nil
                                   accessTokenExpiry:accessExpiry
                                  refreshTokenExpiry:refreshExpiry];
                                  
    session.sessionID = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
    
    const char *dpop = (const char *)sqlite3_column_text(stmt, 8);
    if (dpop) session.dpopKeyThumbprint = [NSString stringWithUTF8String:dpop];
    
    const char *type = (const char *)sqlite3_column_text(stmt, 9);
    if (type) session.tokenType = [NSString stringWithUTF8String:type];
    
    return session;
}

- (nullable Session *)getSessionByAccessToken:(NSString *)token error:(NSError **)error {
    const char *sql = "SELECT * FROM sessions WHERE access_token = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return nil;
    
    sqlite3_bind_text(stmt, 1, token.UTF8String, -1, SQLITE_TRANSIENT);
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        return [self sessionFromStatement:stmt];
    }
    return nil;
}

- (nullable Session *)getSessionByRefreshToken:(NSString *)token error:(NSError **)error {
    const char *sql = "SELECT * FROM sessions WHERE refresh_token = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return nil;
    
    sqlite3_bind_text(stmt, 1, token.UTF8String, -1, SQLITE_TRANSIENT);
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        return [self sessionFromStatement:stmt];
    }
    return nil;
}

- (nullable Session *)getSessionByID:(NSString *)sessionID error:(NSError **)error {
    const char *sql = "SELECT * FROM sessions WHERE session_id = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return nil;
    
    sqlite3_bind_text(stmt, 1, sessionID.UTF8String, -1, SQLITE_TRANSIENT);
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        return [self sessionFromStatement:stmt];
    }
    return nil;
}

- (BOOL)revokeSessionByID:(NSString *)sessionID error:(NSError **)error {
    const char *sql = "DELETE FROM sessions WHERE session_id = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return NO;
    
    sqlite3_bind_text(stmt, 1, sessionID.UTF8String, -1, SQLITE_TRANSIENT);
    if (sqlite3_step(stmt) == SQLITE_DONE) {
        return sqlite3_changes(_db) > 0;
    }
    return NO;
}

- (NSArray<Session *> *)getSessionsForDID:(NSString *)did error:(NSError **)error {
    const char *sql = "SELECT * FROM sessions WHERE did = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return @[];
    
    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    NSMutableArray *sessions = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        Session *s = [self sessionFromStatement:stmt];
        if (s) [sessions addObject:s];
    }
    return sessions;
}

- (NSArray<Session *> *)allActiveSessions:(NSError **)error {
    const char *sql = "SELECT * FROM sessions WHERE access_token_expires_at > ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) return @[];
    
    sqlite3_bind_double(stmt, 1, [[NSDate date] timeIntervalSince1970]);
    NSMutableArray *sessions = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        Session *s = [self sessionFromStatement:stmt];
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
