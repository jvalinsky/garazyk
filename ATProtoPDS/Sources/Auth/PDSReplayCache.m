#import "Auth/PDSReplayCache.h"
#import "Debug/PDSLogger.h"
#import <sqlite3.h>

@implementation PDSReplayCache {
    sqlite3 *_db;
}

+ (instancetype)sharedCache {
    static PDSReplayCache *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSReplayCache alloc] init];
    });
    return shared;
}

- (instancetype)init {
    return [self initWithDatabasePath:nil];
}

- (instancetype)initWithDatabasePath:(NSString *)path {
    self = [super init];
    if (self) {
        const char *dbPath = path ? path.UTF8String : ":memory:";
        int rc = sqlite3_open(dbPath, &_db);
        if (rc != SQLITE_OK) {
            PDS_LOG_AUTH_ERROR(@"Failed to open replay cache database: %s", sqlite3_errmsg(_db));
            return nil;
        }
        sqlite3_exec(_db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);

        const char *createSQL =
            "CREATE TABLE IF NOT EXISTS jti_cache ("
            "  jti TEXT PRIMARY KEY,"
            "  expires_at REAL NOT NULL"
            ");"
            "CREATE INDEX IF NOT EXISTS idx_jti_cache_expires_at ON jti_cache(expires_at);";

        char *errMsg = NULL;
        if (sqlite3_exec(_db, createSQL, NULL, NULL, &errMsg) != SQLITE_OK) {
            PDS_LOG_AUTH_ERROR(@"Failed to create jti_cache table: %s", errMsg);
            sqlite3_free(errMsg);
            sqlite3_close(_db);
            return nil;
        }

        // Setup periodic cleanup
        NSTimer *timer = [NSTimer timerWithTimeInterval:300 target:self selector:@selector(cleanup) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)dealloc {
    if (_db) {
        sqlite3_close(_db);
        _db = NULL;
    }
}

- (BOOL)checkAndAddJTI:(NSString *)jti expiration:(NSDate *)expiration {
    if (!jti || !expiration) return NO;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval expiresAt = [expiration timeIntervalSince1970];

    // Check if a non-expired entry exists
    const char *selectSQL = "SELECT expires_at FROM jti_cache WHERE jti = ?";
    sqlite3_stmt *selectStmt = NULL;
    if (sqlite3_prepare_v2(_db, selectSQL, -1, &selectStmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(selectStmt, 1, jti.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(selectStmt) == SQLITE_ROW) {
            double existingExpiry = sqlite3_column_double(selectStmt, 0);
            if (existingExpiry >= now) {
                // Non-expired entry exists — replay detected
                sqlite3_finalize(selectStmt);
                return NO;
            }
        }
    }
    sqlite3_finalize(selectStmt);

    // Insert or replace (new or expired entry)
    const char *insertSQL = "INSERT OR REPLACE INTO jti_cache (jti, expires_at) VALUES (?, ?)";
    sqlite3_stmt *insertStmt = NULL;
    if (sqlite3_prepare_v2(_db, insertSQL, -1, &insertStmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(insertStmt, 1, jti.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(insertStmt, 2, expiresAt);
        sqlite3_step(insertStmt);
    }
    sqlite3_finalize(insertStmt);

    return YES;
}

- (void)cleanup {
    const char *deleteSQL = "DELETE FROM jti_cache WHERE expires_at < ?";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, deleteSQL, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_double(stmt, 1, [[NSDate date] timeIntervalSince1970]);
        sqlite3_step(stmt);
    }
    sqlite3_finalize(stmt);
}

@end
