// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoRateLimiter.m

 @abstract Implements request rate-limiting policy enforcement for protected operations.

 @discussion Tracks request activity and evaluates limits to prevent abuse or overload according to configured policy thresholds. Enforces control decisions while leaving authentication and business outcomes to callers.
 */

#import "Network/RateLimiter.h"
#import "Compat/PDSTypes.h"
#import "Network/HttpResponse.h"
#import "Core/ATProtoDataPaths.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Debug/GZLogger.h"
#import "Metrics/GZMetrics.h"

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

static RateLimiterStorageFactory _rateLimiterStorageFactory = nil;

void RateLimiterSetStorageFactory(RateLimiterStorageFactory _Nullable factory) {
    _rateLimiterStorageFactory = [factory copy];
}

@implementation ATProtoRateLimiterStorageHandle

- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)connectionManager
                              queryRunner:(id<ATProtoQueryRunning>)queryRunner {
    self = [super init];
    if (self) {
        _connectionManager = connectionManager;
        _queryRunner = queryRunner;
    }
    return self;
}

@end

@implementation ATProtoRateLimitResult

+ (instancetype)resultAllowed:(BOOL)allowed
                        limit:(NSInteger)limit
                    remaining:(NSInteger)remaining
                  resetSeconds:(NSTimeInterval)resetSeconds
                   retryAfter:(NSTimeInterval)retryAfter {
    ATProtoRateLimitResult *result = [[ATProtoRateLimitResult alloc] init];
    result.allowed = allowed;
    result.limit = limit;
    result.remaining = remaining;
    result.resetSeconds = resetSeconds;
    result.retryAfter = retryAfter;
    return result;
}

@end

@interface ATProtoRateLimiter ()

@property (nonatomic, copy, nullable) NSString *databasePath;
@property (nonatomic, strong, nullable) ATProtoRateLimiterStorageHandle *storageHandle;

@end

@implementation ATProtoRateLimiter

+ (instancetype)sharedLimiter {
    static ATProtoRateLimiter *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ATProtoRateLimiter alloc] initWithDatabasePath:nil];
        GZ_LOG_HTTP_DEBUG(@"RateLimiter singleton created (enabled=%@)", @(sharedInstance.isEnabled));
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

        // Let ATProtoServiceConfiguration (which reads config file + env vars) override
        ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
        if (config && !config.rateLimitEnabled) {
            _enabled = NO;
        }

        GZ_LOG_HTTP_DEBUG(@"RateLimiter init (enabled=%@, global_disabled=%@, config_enabled=%@)",
                           @(_enabled),
                           @(_rateLimiterDisabledGlobally),
                           @(config.rateLimitEnabled));
        
        if (path) {
            _databasePath = [path copy];
        } else {
            _databasePath = nil; // Will be determined on-demand
        }
    }
    return self;
}

- (void)reconfigureDatabasePath:(nullable NSString *)path {
    NSString *normalizedPath = path.length > 0 ? [path copy] : nil;
    @synchronized(self) {
        if (_storageHandle) {
            [_storageHandle.connectionManager close];
            _storageHandle = nil;
        }
        _databasePath = normalizedPath;
    }
}

- (BOOL)ensureDatabaseOpened {
    @synchronized(self) {
        if (self.storageHandle && self.storageHandle.connectionManager.isOpen) {
            return YES;
        }

        if (!self.databasePath) {
            ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
            NSString *baseDir = config ? config.dataPaths.serviceDirectory
                                       : [ATProtoDataPaths pathsForBaseDirectory:[ATProtoServiceConfiguration defaultDataDirectory]].serviceDirectory;
            [[NSFileManager defaultManager] createDirectoryAtPath:baseDir withIntermediateDirectories:YES attributes:nil error:nil];
            self.databasePath = [baseDir stringByAppendingPathComponent:@"ratelimits.db"];
        }

        NSString *dbDirectory = [self.databasePath stringByDeletingLastPathComponent];
        if (dbDirectory.length > 0) {
            [[NSFileManager defaultManager] createDirectoryAtPath:dbDirectory
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
        }

        if (!_rateLimiterStorageFactory) {
            GZ_LOG_DB_ERROR(@"RateLimiter: no storage factory registered — cannot open rate limit database");
            return NO;
        }

        // Keep the transport-owned fallback local.  The Storage default is
        // intentionally not linked into ATProtoTransport, and the registered
        // factory may still apply its own process-specific configuration.
        ATProtoDBConfig dbConfig = {
            .flags = ATProtoDBConfigFlagWAL
                   | ATProtoDBConfigFlagSynchronousNormal
                   | ATProtoDBConfigFlagForeignKeys
                   | ATProtoDBConfigFlagTempStoreMemory
        };
        NSError *openError = nil;
        ATProtoRateLimiterStorageHandle *handle = _rateLimiterStorageFactory(self.databasePath, dbConfig, &openError);
        if (!handle) {
            GZ_LOG_DB_ERROR(@"Failed to open rate limit database at path %@: %@", self.databasePath, openError);
            return NO;
        }
        self.storageHandle = handle;

        [self initializeDatabase];
        return self.storageHandle.connectionManager.isOpen;
    }
}

- (void)initializeDatabase {
    NSString *createTableSQL = @"CREATE TABLE IF NOT EXISTS rate_limits ("
        @"id INTEGER PRIMARY KEY AUTOINCREMENT, "
        @"identifier TEXT NOT NULL, "
        @"type INTEGER NOT NULL, "
        @"request_count INTEGER NOT NULL DEFAULT 0, "
        @"window_start INTEGER NOT NULL, "
        @"UNIQUE(identifier, type)"
        @")";
    [self.storageHandle.queryRunner executeUpdate:createTableSQL params:nil error:nil];

    NSString *createIndexSQL = @"CREATE INDEX IF NOT EXISTS idx_rate_limits_identifier ON rate_limits(identifier)";
    [self.storageHandle.queryRunner executeUpdate:createIndexSQL params:nil error:nil];

    NSString *createBlobTableSQL = @"CREATE TABLE IF NOT EXISTS blob_rate_limits ("
        @"id INTEGER PRIMARY KEY AUTOINCREMENT, "
        @"did TEXT NOT NULL, "
        @"upload_count INTEGER NOT NULL DEFAULT 0, "
        @"window_start INTEGER NOT NULL, "
        @"UNIQUE(did)"
        @")";
    [self.storageHandle.queryRunner executeUpdate:createBlobTableSQL params:nil error:nil];
}

- (ATProtoRateLimitResult *)checkRateLimitForDid:(NSString *)did {
    if (!self.isEnabled) {
        return [ATProtoRateLimitResult resultAllowed:YES limit:self.didLimit remaining:self.didLimit resetSeconds:0 retryAfter:0];
    }
    if (!did || did.length == 0) {
        return [ATProtoRateLimitResult resultAllowed:YES limit:self.didLimit remaining:self.didLimit resetSeconds:0 retryAfter:0];
    }
    return [self checkRateLimitInternalForIdentifier:did type:RateLimitTypeDID limit:self.didLimit windowSeconds:self.didWindowSeconds];
}

- (ATProtoRateLimitResult *)checkRateLimitForIP:(NSString *)ip {
    if (!self.isEnabled || _rateLimiterDisabledGlobally) {
        return [ATProtoRateLimitResult resultAllowed:YES limit:self.ipLimit remaining:self.ipLimit resetSeconds:0 retryAfter:0];
    }
    if (!ip || ip.length == 0) {
        return [ATProtoRateLimitResult resultAllowed:YES limit:self.ipLimit remaining:self.ipLimit resetSeconds:0 retryAfter:0];
    }
    return [self checkRateLimitInternalForIdentifier:ip type:RateLimitTypeIP limit:self.ipLimit windowSeconds:self.ipWindowSeconds];
}

- (ATProtoRateLimitResult *)checkBlobUploadRateLimitForDid:(NSString *)did {
    if (!self.isEnabled) {
        return [ATProtoRateLimitResult resultAllowed:YES limit:self.blobLimit remaining:self.blobLimit resetSeconds:0 retryAfter:0];
    }
    if (!did || did.length == 0) {
        return [ATProtoRateLimitResult resultAllowed:YES limit:self.blobLimit remaining:self.blobLimit resetSeconds:0 retryAfter:0];
    }
    return [self checkBlobRateLimitInternalForDid:did limit:self.blobLimit windowSeconds:self.blobWindowSeconds];
}

- (ATProtoRateLimitResult *)checkRateLimitForKey:(NSString *)key limit:(NSInteger)limit windowSeconds:(NSTimeInterval)windowSeconds {
    if (!self.isEnabled) {
        return [ATProtoRateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:0 retryAfter:0];
    }
    if (!key || key.length == 0) {
        return [ATProtoRateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:0 retryAfter:0];
    }
    return [self checkRateLimitInternalForIdentifier:key type:RateLimitTypeCustom limit:limit windowSeconds:windowSeconds];
}

- (ATProtoRateLimitResult *)checkRateLimitInternalForIdentifier:(NSString *)identifier
                                                    type:(RateLimitType)type
                                                   limit:(NSInteger)limit
                                             windowSeconds:(NSTimeInterval)windowSeconds {
    if (![self ensureDatabaseOpened]) {
        return [ATProtoRateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:0 retryAfter:0];
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval windowStart = now - windowSeconds;

    __block ATProtoRateLimitResult *outResult = nil;
    __block NSInteger requestCount = 0;

    [self.storageHandle.queryRunner performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **error) {
        NSString *selectSQL = @"SELECT request_count, window_start FROM rate_limits WHERE identifier = ? AND type = ? AND window_start > ?";
        NSArray *rows = [tx executeQuery:selectSQL params:@[identifier, @(type), @(windowStart)] error:error];
        NSTimeInterval existingWindowStart = 0;
        if (rows.count > 0) {
            NSDictionary *row = rows.firstObject;
            requestCount = [row[@"request_count"] integerValue];
            existingWindowStart = [row[@"window_start"] doubleValue];
        }

        if (requestCount >= limit) {
            NSTimeInterval resetSeconds = (existingWindowStart + windowSeconds) - now;
            if (resetSeconds < 0) resetSeconds = 0;
            [[GZMetrics sharedMetrics] incrementRateLimitRejection:
                (type == RateLimitTypeDID ? @"did" :
                 type == RateLimitTypeIP ? @"ip" : @"custom")];
            outResult = [ATProtoRateLimitResult resultAllowed:NO limit:limit remaining:0 resetSeconds:resetSeconds retryAfter:resetSeconds];
            return NO;
        }

        NSString *upsertSQL = @"INSERT INTO rate_limits (identifier, type, request_count, window_start) "
                              @"VALUES (?, ?, ?, ?) "
                              @"ON CONFLICT(identifier, type) DO UPDATE SET "
                              @"request_count = CASE WHEN window_start > ? THEN request_count + 1 ELSE 1 END, "
                              @"window_start = CASE WHEN window_start > ? THEN window_start ELSE ? END";

        BOOL success = [tx executeUpdate:upsertSQL
                                  params:@[identifier, @(type), @(1), @(now), @(windowStart), @(windowStart), @(now)]
                                   error:error];
        if (!success) {
            return NO;
        }

        outResult = [ATProtoRateLimitResult resultAllowed:YES
                                             limit:limit
                                         remaining:(limit - requestCount - 1)
                                       resetSeconds:windowSeconds
                                        retryAfter:0];
        return YES;
    } error:nil];

    if (outResult) {
        return outResult;
    }
    return [ATProtoRateLimitResult resultAllowed:YES
                                    limit:limit
                                remaining:(limit - requestCount - 1)
                              resetSeconds:0
                               retryAfter:0];
}

- (ATProtoRateLimitResult *)currentRateLimitForIdentifier:(NSString *)identifier
                                              type:(RateLimitType)type
                                             limit:(NSInteger)limit
                                     windowSeconds:(NSTimeInterval)windowSeconds {
    if (![self ensureDatabaseOpened]) {
        return [ATProtoRateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:windowSeconds retryAfter:0];
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval windowStart = now - windowSeconds;
    NSString *selectSQL = @"SELECT request_count, window_start FROM rate_limits WHERE identifier = ? AND type = ? AND window_start > ?";

    NSArray *rows = [self.storageHandle.queryRunner executeQuery:selectSQL params:@[identifier, @(type), @(windowStart)] error:nil];
    NSInteger requestCount = 0;
    NSTimeInterval existingWindowStart = 0;
    if (rows.count > 0) {
        NSDictionary *row = rows.firstObject;
        requestCount = [row[@"request_count"] integerValue];
        existingWindowStart = [row[@"window_start"] doubleValue];
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
    return [ATProtoRateLimitResult resultAllowed:allowed
                                    limit:limit
                                remaining:remaining
                              resetSeconds:resetSeconds
                               retryAfter:(allowed ? 0 : resetSeconds)];
}

- (ATProtoRateLimitResult *)checkBlobRateLimitInternalForDid:(NSString *)did
                                                limit:(NSInteger)limit
                                          windowSeconds:(NSTimeInterval)windowSeconds {
    if (![self ensureDatabaseOpened]) {
        return [ATProtoRateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:windowSeconds retryAfter:0];
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval windowStart = now - windowSeconds;

    __block ATProtoRateLimitResult *outResult = nil;
    __block NSInteger uploadCount = 0;

    [self.storageHandle.queryRunner performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **error) {
        NSString *selectSQL = @"SELECT upload_count, window_start FROM blob_rate_limits WHERE did = ? AND window_start > ?";
        NSArray *rows = [tx executeQuery:selectSQL params:@[did, @(windowStart)] error:error];
        NSTimeInterval existingWindowStart = 0;
        if (rows.count > 0) {
            NSDictionary *row = rows.firstObject;
            uploadCount = [row[@"upload_count"] integerValue];
            existingWindowStart = [row[@"window_start"] doubleValue];
        }

        if (uploadCount >= limit) {
            NSTimeInterval resetSeconds = (existingWindowStart + windowSeconds) - now;
            if (resetSeconds < 0) resetSeconds = 0;
            [[GZMetrics sharedMetrics] incrementRateLimitRejection:@"blob"];
            outResult = [ATProtoRateLimitResult resultAllowed:NO limit:limit remaining:0 resetSeconds:resetSeconds retryAfter:resetSeconds];
            return NO;
        }

        NSString *upsertSQL = @"INSERT INTO blob_rate_limits (did, upload_count, window_start) "
                              @"VALUES (?, ?, ?) "
                              @"ON CONFLICT(did) DO UPDATE SET "
                              @"upload_count = CASE WHEN window_start > ? THEN upload_count + 1 ELSE 1 END, "
                              @"window_start = CASE WHEN window_start > ? THEN window_start ELSE ? END";

        BOOL success = [tx executeUpdate:upsertSQL
                                  params:@[did, @(1), @(now), @(windowStart), @(windowStart), @(now)]
                                   error:error];
        if (!success) {
            return NO;
        }

        outResult = [ATProtoRateLimitResult resultAllowed:YES
                                             limit:limit
                                         remaining:(limit - uploadCount - 1)
                                       resetSeconds:windowSeconds
                                        retryAfter:0];
        return YES;
    } error:nil];

    if (outResult) {
        return outResult;
    }
    return [ATProtoRateLimitResult resultAllowed:YES
                                    limit:limit
                                remaining:(limit - uploadCount - 1)
                              resetSeconds:0
                               retryAfter:0];
}

- (ATProtoRateLimitResult *)currentBlobRateLimitForDid:(NSString *)did
                                          limit:(NSInteger)limit
                                   windowSeconds:(NSTimeInterval)windowSeconds {
    if (![self ensureDatabaseOpened]) {
        return [ATProtoRateLimitResult resultAllowed:YES limit:limit remaining:limit resetSeconds:windowSeconds retryAfter:0];
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval windowStart = now - windowSeconds;
    NSString *selectSQL = @"SELECT upload_count, window_start FROM blob_rate_limits WHERE did = ? AND window_start > ?";

    NSArray *rows = [self.storageHandle.queryRunner executeQuery:selectSQL params:@[did, @(windowStart)] error:nil];
    NSInteger uploadCount = 0;
    NSTimeInterval existingWindowStart = 0;
    if (rows.count > 0) {
        NSDictionary *row = rows.firstObject;
        uploadCount = [row[@"upload_count"] integerValue];
        existingWindowStart = [row[@"window_start"] doubleValue];
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
    return [ATProtoRateLimitResult resultAllowed:allowed
                                    limit:limit
                                remaining:remaining
                              resetSeconds:resetSeconds
                               retryAfter:(allowed ? 0 : resetSeconds)];
}

- (NSDictionary<NSString *, NSString *> *)rateLimitHeadersForDid:(NSString *)did {
    if (!did || did.length == 0) {
        return [self headersFromResult:[ATProtoRateLimitResult resultAllowed:YES limit:self.didLimit remaining:self.didLimit resetSeconds:self.didWindowSeconds retryAfter:0]];
    }

    ATProtoRateLimitResult *result = [self currentRateLimitForIdentifier:did type:RateLimitTypeDID limit:self.didLimit windowSeconds:self.didWindowSeconds];
    return [self headersFromResult:result];
}

- (NSDictionary<NSString *, NSString *> *)rateLimitHeadersForIP:(NSString *)ip {
    if (!ip || ip.length == 0) {
        return [self headersFromResult:[ATProtoRateLimitResult resultAllowed:YES limit:self.ipLimit remaining:self.ipLimit resetSeconds:self.ipWindowSeconds retryAfter:0]];
    }

    ATProtoRateLimitResult *result = [self currentRateLimitForIdentifier:ip type:RateLimitTypeIP limit:self.ipLimit windowSeconds:self.ipWindowSeconds];
    return [self headersFromResult:result];
}

- (NSDictionary<NSString *, NSString *> *)blobRateLimitHeadersForDid:(NSString *)did {
    if (!did || did.length == 0) {
        return [self headersFromResult:[ATProtoRateLimitResult resultAllowed:YES limit:self.blobLimit remaining:self.blobLimit resetSeconds:self.blobWindowSeconds retryAfter:0]];
    }

    ATProtoRateLimitResult *result = [self currentBlobRateLimitForDid:did limit:self.blobLimit windowSeconds:self.blobWindowSeconds];
    return [self headersFromResult:result];
}

- (NSDictionary<NSString *, NSString *> *)headersFromResult:(ATProtoRateLimitResult *)result {
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    
    [headers setObject:[NSString stringWithFormat:@"%ld", (long)result.limit] forKey:@"X-RateLimit-Limit"];
    [headers setObject:[NSString stringWithFormat:@"%ld", (long)result.remaining] forKey:@"X-RateLimit-Remaining"];
    [headers setObject:[NSString stringWithFormat:@"%.0f", result.resetSeconds] forKey:@"X-RateLimit-Reset"];
    
    if (!result.allowed) {
        [headers setObject:[NSString stringWithFormat:@"%.0f", result.retryAfter] forKey:@"Retry-After"];
    }
    
    return [headers copy];
}

- (void)applyRateLimitHeadersToResponse:(ATProtoHttpResponse *)response
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
    [_storageHandle.connectionManager close];
}

- (NSArray<NSDictionary *> *)getTopLimitedIdentifiers:(NSInteger)limit {
    if (![self ensureDatabaseOpened]) return @[];
    if (limit <= 0) limit = 20;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval windowStart = now - self.didWindowSeconds;

    NSString *sql = @"SELECT identifier, type, SUM(request_count) as total_count, "
                     @"MAX(window_start) as last_window "
                     @"FROM rate_limits WHERE window_start > ? "
                     @"GROUP BY identifier, type ORDER BY total_count DESC LIMIT ?";

    NSArray *rows = [self.storageHandle.queryRunner executeQuery:sql params:@[@(windowStart), @(limit)] error:nil];
    if (!rows) return @[];

    NSMutableArray *entries = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        [entries addObject:@{
            @"identifier": row[@"identifier"] ?: @"",
            @"type": [NSString stringWithFormat:@"%@", row[@"type"] ?: @""],
            @"requestCount": row[@"total_count"] ?: @0,
            @"windowStart": row[@"last_window"] ?: @0
        }];
    }
    return [entries copy];
}

- (NSInteger)clearRateLimitForIdentifier:(NSString *)identifier type:(NSString *)type {
    if (!identifier || ![self ensureDatabaseOpened]) return 0;

    NSString *sql;
    NSArray *params;
    if ([type isEqualToString:@"blob"]) {
        sql = @"DELETE FROM blob_rate_limits WHERE did = ?";
        params = @[identifier];
    } else {
        sql = @"DELETE FROM rate_limits WHERE identifier = ? AND type = ?";
        params = @[identifier, type];
    }

    NSInteger changes = [self.storageHandle.queryRunner executeUpdate:sql params:params error:nil];
    return changes < 0 ? 0 : changes;
}

@end

NS_ASSUME_NONNULL_END
