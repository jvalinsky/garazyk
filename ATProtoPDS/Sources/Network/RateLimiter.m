#import "Network/RateLimiter.h"
#import "Compat/PDSTypes.h"
#import "Network/HttpResponse.h"
#import "Debug/PDSLogger.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG
static BOOL _rateLimiterDisabledGlobally = YES;
#else
static BOOL _rateLimiterDisabledGlobally = NO;
#endif

void RateLimiterSetDisabledGlobally(BOOL disabled) {
    _rateLimiterDisabledGlobally = disabled;
}

BOOL RateLimiterIsDisabledGlobally(void) {
    return _rateLimiterDisabledGlobally;
}

@implementation RateLimitResult

+ (instancetype)resultAllowed:(BOOL)allowed
                        limit:(NSInteger)limit
                    remaining:(NSInteger)remaining
                  resetSeconds:(NSTimeInterval)resetSeconds
                   retryAfter:(NSTimeInterval)retryAfter {
    RateLimitResult *result = [[RateLimitResult alloc] init];
    result.allowed = allowed;
    result.limit = limit;
    result.remaining = remaining;
    result.resetSeconds = resetSeconds;
    result.retryAfter = retryAfter;
    return result;
}

@end

@interface RateLimiter ()

@property (nonatomic, copy) NSString *databasePath;
@property (nonatomic, assign) sqlite3 *db;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t dbQueue;

@end

@implementation RateLimiter

+ (instancetype)sharedLimiter {
    static RateLimiter *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[RateLimiter alloc] initWithDatabasePath:nil];
        PDS_LOG_HTTP_DEBUG(@"RateLimiter singleton created (enabled=%@)", @(sharedInstance.isEnabled));
    });
    return sharedInstance;
}

- (instancetype)init {
    return [self initWithDatabasePath:nil];
}

- (instancetype)initWithDatabasePath:(nullable NSString *)path {
    self = [super init];
    if (self) {
        _didLimit = 5000;
        _didWindowSeconds = 3600;
        _ipLimit = 100;
        _ipWindowSeconds = 60;
        _blobLimit = 50;
        _blobWindowSeconds = 3600;
        _enabled = !_rateLimiterDisabledGlobally;
        PDS_LOG_HTTP_DEBUG(@"RateLimiter init (enabled=%@, global_disabled=%@)",
                           @(_enabled),
                           @(_rateLimiterDisabledGlobally));
        
        _dbQueue = dispatch_queue_create("com.atproto.ratelimiter.db", DISPATCH_QUEUE_SERIAL);
        
        if (path) {
            _databasePath = [path copy];
        } else {
            NSString *appSupport = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
            NSString *appDir = [appSupport stringByAppendingPathComponent:@"ATProtoPDS"];
            [[NSFileManager defaultManager] createDirectoryAtPath:appDir withIntermediateDirectories:YES attributes:nil error:nil];
            _databasePath = [appDir stringByAppendingPathComponent:@"ratelimits.db"];
        }
        
        [self initializeDatabase];
    }
    return self;
}

- (void)initializeDatabase {
    dispatch_sync(self.dbQueue, ^{
        int result = sqlite3_open(self.databasePath.UTF8String, &_db);
        if (result != SQLITE_OK) {
            PDS_LOG_DB_ERROR(@"Failed to open rate limit database: %s (SQLite code: %d)",
                             sqlite3_errmsg(_db), result);
            return;
        }
        
        NSString *createTableSQL = @"CREATE TABLE IF NOT EXISTS rate_limits ("
            @"id INTEGER PRIMARY KEY AUTOINCREMENT, "
            @"identifier TEXT NOT NULL, "
            @"type INTEGER NOT NULL, "
            @"request_count INTEGER NOT NULL DEFAULT 0, "
            @"window_start INTEGER NOT NULL, "
            @"UNIQUE(identifier, type)"
            @")";
        
        char *errMsg = NULL;
        result = sqlite3_exec(_db, createTableSQL.UTF8String, NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            PDS_LOG_DB_ERROR(@"Failed to create rate limit table: %s (SQLite code: %d)",
                             errMsg, result);
            sqlite3_free(errMsg);
        }
        
        NSString *createIndexSQL = @"CREATE INDEX IF NOT EXISTS idx_rate_limits_identifier ON rate_limits(identifier)";
        sqlite3_exec(_db, createIndexSQL.UTF8String, NULL, NULL, NULL);
        
        NSString *createBlobTableSQL = @"CREATE TABLE IF NOT EXISTS blob_rate_limits ("
            @"id INTEGER PRIMARY KEY AUTOINCREMENT, "
            @"did TEXT NOT NULL, "
            @"upload_count INTEGER NOT NULL DEFAULT 0, "
            @"window_start INTEGER NOT NULL, "
            @"UNIQUE(did)"
            @")";
        
        result = sqlite3_exec(_db, createBlobTableSQL.UTF8String, NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            PDS_LOG_DB_ERROR(@"Failed to create blob rate limit table: %s (SQLite code: %d)",
                             errMsg, result);
            sqlite3_free(errMsg);
        }
    });
}

- (RateLimitResult *)checkRateLimitForDid:(NSString *)did {
    if (!self.isEnabled) {
        return [RateLimitResult resultAllowed:YES limit:self.didLimit remaining:self.didLimit resetSeconds:0 retryAfter:0];
    }
    if (!did || did.length == 0) {
        return [RateLimitResult resultAllowed:YES limit:self.didLimit remaining:self.didLimit resetSeconds:0 retryAfter:0];
    }
    
    __block RateLimitResult *result;
    dispatch_sync(self.dbQueue, ^{
        result = [self checkRateLimitInternalForIdentifier:did type:RateLimitTypeDID limit:self.didLimit windowSeconds:self.didWindowSeconds];
    });
    return result;
}

- (RateLimitResult *)checkRateLimitForIP:(NSString *)ip {
    if (!self.isEnabled || _rateLimiterDisabledGlobally) {
        return [RateLimitResult resultAllowed:YES limit:self.ipLimit remaining:self.ipLimit resetSeconds:0 retryAfter:0];
    }
    if (!ip || ip.length == 0) {
        return [RateLimitResult resultAllowed:YES limit:self.ipLimit remaining:self.ipLimit resetSeconds:0 retryAfter:0];
    }
    
    __block RateLimitResult *result;
    dispatch_sync(self.dbQueue, ^{
        result = [self checkRateLimitInternalForIdentifier:ip type:RateLimitTypeIP limit:self.ipLimit windowSeconds:self.ipWindowSeconds];
    });
    return result;
}

- (RateLimitResult *)checkBlobUploadRateLimitForDid:(NSString *)did {
    if (!self.isEnabled) {
        return [RateLimitResult resultAllowed:YES limit:self.blobLimit remaining:self.blobLimit resetSeconds:0 retryAfter:0];
    }
    if (!did || did.length == 0) {
        return [RateLimitResult resultAllowed:YES limit:self.blobLimit remaining:self.blobLimit resetSeconds:0 retryAfter:0];
    }
    
    __block RateLimitResult *result;
    dispatch_sync(self.dbQueue, ^{
        result = [self checkBlobRateLimitInternalForDid:did limit:self.blobLimit windowSeconds:self.blobWindowSeconds];
    });
    return result;
}

- (RateLimitResult *)checkRateLimitInternalForIdentifier:(NSString *)identifier
                                                     type:(RateLimitType)type
                                                    limit:(NSInteger)limit
                                              windowSeconds:(NSTimeInterval)windowSeconds {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval windowStart = now - windowSeconds;
    
    NSString *selectSQL = @"SELECT request_count, window_start FROM rate_limits WHERE identifier = ? AND type = ? AND window_start > ?";
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt;
    int result = sqlite3_prepare_v2(_db, selectSQL.UTF8String, -1, &stmt, NULL);
    if (result != SQLITE_OK) {
        return [RateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:0 retryAfter:0];
    }
    
    sqlite3_bind_text(stmt, 1, identifier.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 2, type);
    sqlite3_bind_double(stmt, 3, windowStart);
    
    NSInteger requestCount = 0;
    NSTimeInterval existingWindowStart = 0;
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        requestCount = sqlite3_column_int(stmt, 0);
        existingWindowStart = sqlite3_column_double(stmt, 1);
    }
    
    if (requestCount >= limit) {
        NSTimeInterval resetSeconds = (existingWindowStart + windowSeconds) - now;
        return [RateLimitResult resultAllowed:NO limit:limit remaining:0 resetSeconds:resetSeconds retryAfter:resetSeconds];
    }
    
    NSString *upsertSQL = @"INSERT INTO rate_limits (identifier, type, request_count, window_start) "
                          @"VALUES (?, ?, ?, ?) "
                          @"ON CONFLICT(identifier, type) DO UPDATE SET "
                          @"request_count = request_count + 1, window_start = CASE WHEN window_start > ? THEN window_start ELSE ? END";
    
    // We need a new statement variable since the previous one is autoreleased only at scope exit
    // However, declaring another PDS_SQLITE_AUTORELEASE_STMT in the same scope with same name is tricky.
    // It's better to wrap this in a block or use a different name.
    // Let's use a different name "upsertStmt".
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *upsertStmt;
    result = sqlite3_prepare_v2(_db, upsertSQL.UTF8String, -1, &upsertStmt, NULL);
    if (result != SQLITE_OK) {
        return [RateLimitResult resultAllowed:YES limit:limit remaining:(limit - requestCount - 1) resetSeconds:0 retryAfter:0];
    }
    
    sqlite3_bind_text(upsertStmt, 1, identifier.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(upsertStmt, 2, type);
    sqlite3_bind_int(upsertStmt, 3, 1);
    sqlite3_bind_double(upsertStmt, 4, now);
    sqlite3_bind_double(upsertStmt, 5, windowStart);
    sqlite3_bind_double(upsertStmt, 6, now);
    
    result = sqlite3_step(upsertStmt);

    if (result != SQLITE_DONE && result != SQLITE_CONSTRAINT) {
        PDS_LOG_DB_ERROR(@"Failed to update rate limit: %s (SQLite code: %d)",
                         sqlite3_errmsg(_db), result);
    }

    return [RateLimitResult resultAllowed:YES
                                    limit:limit
                                remaining:(limit - requestCount - 1)
                              resetSeconds:windowSeconds
                               retryAfter:0];
}

- (RateLimitResult *)currentRateLimitForIdentifier:(NSString *)identifier
                                              type:(RateLimitType)type
                                             limit:(NSInteger)limit
                                      windowSeconds:(NSTimeInterval)windowSeconds {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval windowStart = now - windowSeconds;
    NSString *selectSQL = @"SELECT request_count, window_start FROM rate_limits WHERE identifier = ? AND type = ? AND window_start > ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt;
    int result = sqlite3_prepare_v2(_db, selectSQL.UTF8String, -1, &stmt, NULL);
    if (result != SQLITE_OK) {
        return [RateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:windowSeconds retryAfter:0];
    }

    sqlite3_bind_text(stmt, 1, identifier.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 2, type);
    sqlite3_bind_double(stmt, 3, windowStart);

    NSInteger requestCount = 0;
    NSTimeInterval existingWindowStart = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        requestCount = sqlite3_column_int(stmt, 0);
        existingWindowStart = sqlite3_column_double(stmt, 1);
    }

    BOOL allowed = requestCount < limit;
    NSTimeInterval resetSeconds = 0;
    if (existingWindowStart > 0) {
        resetSeconds = (existingWindowStart + windowSeconds) - now;
        if (resetSeconds < 0) {
            resetSeconds = 0;
        }
    } else {
        resetSeconds = windowSeconds;
    }

    NSInteger remaining = allowed ? (limit - requestCount) : 0;
    return [RateLimitResult resultAllowed:allowed
                                    limit:limit
                                remaining:remaining
                              resetSeconds:resetSeconds
                               retryAfter:(allowed ? 0 : resetSeconds)];
}

- (RateLimitResult *)checkBlobRateLimitInternalForDid:(NSString *)did
                                                 limit:(NSInteger)limit
                                           windowSeconds:(NSTimeInterval)windowSeconds {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval windowStart = now - windowSeconds;
    
    NSString *selectSQL = @"SELECT upload_count, window_start FROM blob_rate_limits WHERE did = ? AND window_start > ?";
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt;
    int result = sqlite3_prepare_v2(_db, selectSQL.UTF8String, -1, &stmt, NULL);
    if (result != SQLITE_OK) {
        return [RateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:0 retryAfter:0];
    }
    
    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 2, windowStart);
    
    NSInteger uploadCount = 0;
    NSTimeInterval existingWindowStart = 0;
    
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        uploadCount = sqlite3_column_int(stmt, 0);
        existingWindowStart = sqlite3_column_double(stmt, 1);
    }
    
    if (uploadCount >= limit) {
        NSTimeInterval resetSeconds = (existingWindowStart + windowSeconds) - now;
        return [RateLimitResult resultAllowed:NO limit:limit remaining:0 resetSeconds:resetSeconds retryAfter:resetSeconds];
    }
    
    NSString *upsertSQL = @"INSERT INTO blob_rate_limits (did, upload_count, window_start) "
                          @"VALUES (?, ?, ?) "
                          @"ON CONFLICT(did) DO UPDATE SET "
                          @"upload_count = upload_count + 1, window_start = CASE WHEN window_start > ? THEN window_start ELSE ? END";
    
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *upsertStmt;
    result = sqlite3_prepare_v2(_db, upsertSQL.UTF8String, -1, &upsertStmt, NULL);
    if (result != SQLITE_OK) {
        return [RateLimitResult resultAllowed:YES limit:limit remaining:(limit - uploadCount - 1) resetSeconds:0 retryAfter:0];
    }
    
    sqlite3_bind_text(upsertStmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(upsertStmt, 2, 1);
    sqlite3_bind_double(upsertStmt, 3, now);
    sqlite3_bind_double(upsertStmt, 4, windowStart);
    sqlite3_bind_double(upsertStmt, 5, now);

    result = sqlite3_step(upsertStmt);

    if (result != SQLITE_DONE && result != SQLITE_CONSTRAINT) {
        PDS_LOG_DB_ERROR(@"Failed to update blob rate limit: %s (SQLite code: %d)",
                         sqlite3_errmsg(_db), result);
    }

    return [RateLimitResult resultAllowed:YES
                                    limit:limit
                                remaining:(limit - uploadCount - 1)
                              resetSeconds:windowSeconds
                               retryAfter:0];
}

- (RateLimitResult *)currentBlobRateLimitForDid:(NSString *)did
                                          limit:(NSInteger)limit
                                   windowSeconds:(NSTimeInterval)windowSeconds {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval windowStart = now - windowSeconds;
    NSString *selectSQL = @"SELECT upload_count, window_start FROM blob_rate_limits WHERE did = ? AND window_start > ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt;
    int result = sqlite3_prepare_v2(_db, selectSQL.UTF8String, -1, &stmt, NULL);
    if (result != SQLITE_OK) {
        return [RateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:windowSeconds retryAfter:0];
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 2, windowStart);

    NSInteger uploadCount = 0;
    NSTimeInterval existingWindowStart = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        uploadCount = sqlite3_column_int(stmt, 0);
        existingWindowStart = sqlite3_column_double(stmt, 1);
    }

    BOOL allowed = uploadCount < limit;
    NSTimeInterval resetSeconds = 0;
    if (existingWindowStart > 0) {
        resetSeconds = (existingWindowStart + windowSeconds) - now;
        if (resetSeconds < 0) {
            resetSeconds = 0;
        }
    } else {
        resetSeconds = windowSeconds;
    }

    NSInteger remaining = allowed ? (limit - uploadCount) : 0;
    return [RateLimitResult resultAllowed:allowed
                                    limit:limit
                                remaining:remaining
                              resetSeconds:resetSeconds
                               retryAfter:(allowed ? 0 : resetSeconds)];
}

- (NSDictionary<NSString *, NSString *> *)rateLimitHeadersForDid:(NSString *)did {
    if (!did || did.length == 0) {
        return [self headersFromResult:[RateLimitResult resultAllowed:YES limit:self.didLimit remaining:self.didLimit resetSeconds:self.didWindowSeconds retryAfter:0]];
    }

    __block RateLimitResult *result = nil;
    dispatch_sync(self.dbQueue, ^{
        result = [self currentRateLimitForIdentifier:did type:RateLimitTypeDID limit:self.didLimit windowSeconds:self.didWindowSeconds];
    });
    return [self headersFromResult:result];
}

- (NSDictionary<NSString *, NSString *> *)rateLimitHeadersForIP:(NSString *)ip {
    if (!ip || ip.length == 0) {
        return [self headersFromResult:[RateLimitResult resultAllowed:YES limit:self.ipLimit remaining:self.ipLimit resetSeconds:self.ipWindowSeconds retryAfter:0]];
    }

    __block RateLimitResult *result = nil;
    dispatch_sync(self.dbQueue, ^{
        result = [self currentRateLimitForIdentifier:ip type:RateLimitTypeIP limit:self.ipLimit windowSeconds:self.ipWindowSeconds];
    });
    return [self headersFromResult:result];
}

- (NSDictionary<NSString *, NSString *> *)blobRateLimitHeadersForDid:(NSString *)did {
    if (!did || did.length == 0) {
        return [self headersFromResult:[RateLimitResult resultAllowed:YES limit:self.blobLimit remaining:self.blobLimit resetSeconds:self.blobWindowSeconds retryAfter:0]];
    }

    __block RateLimitResult *result = nil;
    dispatch_sync(self.dbQueue, ^{
        result = [self currentBlobRateLimitForDid:did limit:self.blobLimit windowSeconds:self.blobWindowSeconds];
    });
    return [self headersFromResult:result];
}

- (NSDictionary<NSString *, NSString *> *)headersFromResult:(RateLimitResult *)result {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    
    [headers setObject:[NSString stringWithFormat:@"%ld", (long)result.limit] forKey:@"X-RateLimit-Limit"];
    [headers setObject:[NSString stringWithFormat:@"%ld", (long)result.remaining] forKey:@"X-RateLimit-Remaining"];
    [headers setObject:[NSString stringWithFormat:@"%.0f", result.resetSeconds] forKey:@"X-RateLimit-Reset"];
    
    if (!result.allowed) {
        [headers setObject:[NSString stringWithFormat:@"%.0f", result.retryAfter] forKey:@"Retry-After"];
    }
    
    return [headers copy];
}

- (void)applyRateLimitHeadersToResponse:(HttpResponse *)response
                                  forDid:(nullable NSString *)did
                                    ip:(nullable NSString *)ip {
    if (did) {
        NSDictionary *didHeaders = [self rateLimitHeadersForDid:did];
        [didHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            [response setHeader:value forKey:(NSString *)key];
        }];
    }
    
    if (ip) {
        NSDictionary *ipHeaders = [self rateLimitHeadersForIP:ip];
        [ipHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            [response setHeader:value forKey:(NSString *)key];
        }];
    }
}

- (void)dealloc {
    if (_db) {
        sqlite3_close(_db);
    }
}

@end

NS_ASSUME_NONNULL_END
