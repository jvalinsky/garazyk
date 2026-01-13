#import "Network/RateLimiter.h"
#import "Network/HttpResponse.h"
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

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
@property (nonatomic, strong) dispatch_queue_t dbQueue;

@end

@implementation RateLimiter

+ (instancetype)sharedLimiter {
    static RateLimiter *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[RateLimiter alloc] initWithDatabasePath:nil];
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
            NSLog(@"Failed to open rate limit database: %s", sqlite3_errmsg(_db));
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
            NSLog(@"Failed to create rate limit table: %s", errMsg);
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
            NSLog(@"Failed to create blob rate limit table: %s", errMsg);
            sqlite3_free(errMsg);
        }
    });
}

- (RateLimitResult *)checkRateLimitForDid:(NSString *)did {
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
    
    sqlite3_stmt *stmt;
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
    sqlite3_finalize(stmt);
    
    if (requestCount >= limit) {
        NSTimeInterval resetSeconds = (existingWindowStart + windowSeconds) - now;
        return [RateLimitResult resultAllowed:NO limit:limit remaining:0 resetSeconds:resetSeconds retryAfter:resetSeconds];
    }
    
    NSString *upsertSQL = @"INSERT INTO rate_limits (identifier, type, request_count, window_start) "
                          @"VALUES (?, ?, ?, ?) "
                          @"ON CONFLICT(identifier, type) DO UPDATE SET "
                          @"request_count = request_count + 1, window_start = CASE WHEN window_start > ? THEN window_start ELSE ? END";
    
    result = sqlite3_prepare_v2(_db, upsertSQL.UTF8String, -1, &stmt, NULL);
    if (result != SQLITE_OK) {
        return [RateLimitResult resultAllowed:YES limit:limit remaining:(limit - requestCount - 1) resetSeconds:0 retryAfter:0];
    }
    
    sqlite3_bind_text(stmt, 1, identifier.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 2, type);
    sqlite3_bind_int(stmt, 3, 1);
    sqlite3_bind_double(stmt, 4, now);
    sqlite3_bind_double(stmt, 5, windowStart);
    sqlite3_bind_double(stmt, 6, now);
    
    result = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (result != SQLITE_DONE && result != SQLITE_CONSTRAINT) {
        NSLog(@"Failed to update rate limit: %s", sqlite3_errmsg(_db));
    }
    
    return [RateLimitResult resultAllowed:YES
                                    limit:limit
                                remaining:(limit - requestCount - 1)
                              resetSeconds:windowSeconds
                               retryAfter:0];
}

- (RateLimitResult *)checkBlobRateLimitInternalForDid:(NSString *)did
                                                 limit:(NSInteger)limit
                                           windowSeconds:(NSTimeInterval)windowSeconds {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval windowStart = now - windowSeconds;
    
    NSString *selectSQL = @"SELECT upload_count, window_start FROM blob_rate_limits WHERE did = ? AND window_start > ?";
    
    sqlite3_stmt *stmt;
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
    sqlite3_finalize(stmt);
    
    if (uploadCount >= limit) {
        NSTimeInterval resetSeconds = (existingWindowStart + windowSeconds) - now;
        return [RateLimitResult resultAllowed:NO limit:limit remaining:0 resetSeconds:resetSeconds retryAfter:resetSeconds];
    }
    
    NSString *upsertSQL = @"INSERT INTO blob_rate_limits (did, upload_count, window_start) "
                          @"VALUES (?, ?, ?) "
                          @"ON CONFLICT(did) DO UPDATE SET "
                          @"upload_count = upload_count + 1, window_start = CASE WHEN window_start > ? THEN window_start ELSE ? END";
    
    result = sqlite3_prepare_v2(_db, upsertSQL.UTF8String, -1, &stmt, NULL);
    if (result != SQLITE_OK) {
        return [RateLimitResult resultAllowed:YES limit:limit remaining:(limit - uploadCount - 1) resetSeconds:0 retryAfter:0];
    }
    
    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 2, 1);
    sqlite3_bind_double(stmt, 3, now);
    sqlite3_bind_double(stmt, 4, windowStart);
    sqlite3_bind_double(stmt, 5, now);
    
    result = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (result != SQLITE_DONE && result != SQLITE_CONSTRAINT) {
        NSLog(@"Failed to update blob rate limit: %s", sqlite3_errmsg(_db));
    }
    
    return [RateLimitResult resultAllowed:YES
                                    limit:limit
                                remaining:(limit - uploadCount - 1)
                              resetSeconds:windowSeconds
                               retryAfter:0];
}

- (NSDictionary<NSString *, NSString *> *)rateLimitHeadersForDid:(NSString *)did {
    RateLimitResult *result = [self checkRateLimitForDid:did];
    return [self headersFromResult:result];
}

- (NSDictionary<NSString *, NSString *> *)rateLimitHeadersForIP:(NSString *)ip {
    RateLimitResult *result = [self checkRateLimitForIP:ip];
    return [self headersFromResult:result];
}

- (NSDictionary<NSString *, NSString *> *)blobRateLimitHeadersForDid:(NSString *)did {
    RateLimitResult *result = [self checkBlobUploadRateLimitForDid:did];
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
