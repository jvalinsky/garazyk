// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/Pool/ATProtoConnectionPool.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"
#import <sqlite3.h>

// Queue-specific key for re-entrancy detection in dealloc
static void * const kConnectionPoolQueueKey = (void *)&kConnectionPoolQueueKey;

static BOOL ATProtoConnectionPoolApplyCustomPragma(sqlite3 *db,
                                                   NSString *name,
                                                   NSString *value) {
    if (!db || name.length == 0 || value.length == 0) {
        return NO;
    }

    NSString *sql = [NSString stringWithFormat:@"PRAGMA %@ = %@", name, value];
    char *errMsg = NULL;
    int rc = sqlite3_exec(db, sql.UTF8String, NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        if (errMsg) {
            GZ_LOG_DB_WARN(@"Failed to set %@: %s", name, errMsg);
            sqlite3_free(errMsg);
        }
        return NO;
    }
    return YES;
}

@interface ATProtoConnectionPool ()
// Pool state
@property (nonatomic, strong) NSMutableArray<NSValue *> *availablePool;  // sqlite3* as NSValue (pointer)
@property (nonatomic, strong) NSMutableSet<NSValue *> *inUsePool;
@property (nonatomic, assign) NSUInteger peakConnCount;
@property (nonatomic, strong) NSDate *lastPruneTime;

// Thread safety
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t poolQueue;
@property (nonatomic, PDS_GCD_STRONG) dispatch_semaphore_t connectionSemaphore;

// Connection metadata
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSDate *> *connectionLastUsed;

@end

@implementation ATProtoConnectionPool

- (instancetype)initWithPath:(NSString *)path {
    return [self initWithPath:path minConnections:2 maxConnections:32];
}

- (instancetype)initWithPath:(NSString *)path
              minConnections:(NSUInteger)minConnections
              maxConnections:(NSUInteger)maxConnections {
    if ((self = [super init])) {
        // Validate inputs
        if (!path || path.length == 0) {
            GZ_LOG_DB_ERROR(@"Connection pool initialized with empty path");
            return nil;
        }
        if (minConnections > maxConnections) {
            GZ_LOG_DB_ERROR(@"minConnections (%lu) > maxConnections (%lu)",
                            (unsigned long)minConnections, (unsigned long)maxConnections);
            return nil;
        }

        _databasePath = [path copy];
        _minConnections = minConnections;
        _maxConnections = maxConnections;

        // Default configuration
        _idleTimeout = 60.0;  // 60 seconds
        _busyTimeout = 5000;  // 5 seconds
        _journalMode = @"WAL";
        _synchronousMode = @"NORMAL";

        // Initialize pool state
        _availablePool = [NSMutableArray array];
        _inUsePool = [NSMutableSet set];
        _connectionLastUsed = [NSMutableDictionary dictionary];
        _lastPruneTime = [NSDate date];

        // Thread safety
        _poolQueue = dispatch_queue_create("com.atproto.pds.connectionpool",
                                          DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_poolQueue, kConnectionPoolQueueKey, kConnectionPoolQueueKey, NULL);
        _connectionSemaphore = dispatch_semaphore_create((NSInteger)maxConnections);

        // Create minimum connections
        for (NSUInteger i = 0; i < minConnections; i++) {
            sqlite3 *conn = [self createNewConnection];
            if (conn) {
                NSValue *connValue = [NSValue valueWithPointer:conn];
                [_availablePool addObject:connValue];
                _connectionLastUsed[connValue] = [NSDate date];
            }
        }

        GZ_LOG_DB_INFO(@"Connection pool created: path=%@, min=%lu, max=%lu",
                       path, (unsigned long)minConnections, (unsigned long)maxConnections);
    }
    return self;
}

- (void)dealloc {
    if (dispatch_get_specific(kConnectionPoolQueueKey)) {
        // Already on pool queue — close connections directly to avoid deadlock
        [self closeAllConnectionsNoSync];
    } else {
        [self closeAllConnections];
    }
}

#pragma mark - Connection Management

- (sqlite3 *)acquireConnection {
    return [self acquireConnectionWithTimeout:30.0];
}

- (sqlite3 *)acquireConnectionWithTimeout:(NSTimeInterval)timeoutSeconds {
    // Wait for semaphore (max connections limit)
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW,
                                           (int64_t)(timeoutSeconds * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(self.connectionSemaphore, timeout) != 0) {
        GZ_LOG_DB_WARN(@"Connection pool exhausted, timeout after %.1fs", timeoutSeconds);
        return NULL;
    }

    __block sqlite3 *connection = NULL;

    dispatch_sync(self.poolQueue, ^{
        // Try to get an available connection
        if (self.availablePool.count > 0) {
            NSValue *connValue = self.availablePool.lastObject;
            [self.availablePool removeLastObject];
            connection = [connValue pointerValue];
            [self.inUsePool addObject:connValue];
            self.connectionLastUsed[connValue] = [NSDate date];
        } else {
            // Create new connection
            connection = [self createNewConnection];
            if (connection) {
                NSValue *connValue = [NSValue valueWithPointer:connection];
                [self.inUsePool addObject:connValue];
                self.connectionLastUsed[connValue] = [NSDate date];

                // Update peak
                NSUInteger total = self.availablePool.count + self.inUsePool.count;
                if (total > self.peakConnCount) {
                    self.peakConnCount = total;
                }
            }
        }
    });

    // If we got a connection but it failed, release semaphore
    if (!connection) {
        dispatch_semaphore_signal(self.connectionSemaphore);
        GZ_LOG_DB_ERROR(@"Failed to acquire connection from pool");
    }

    return connection;
}

- (void)releaseConnection:(sqlite3 *)connection {
    if (!connection) return;

    NSValue *connValue = [NSValue valueWithPointer:connection];

    dispatch_sync(self.poolQueue, ^{
        if ([self.inUsePool containsObject:connValue]) {
            [self.inUsePool removeObject:connValue];
            [self.availablePool addObject:connValue];
            self.connectionLastUsed[connValue] = [NSDate date];

            // Signal that a connection is available
            dispatch_semaphore_signal(self.connectionSemaphore);
        }
    });
}

- (void)invalidateConnection:(sqlite3 *)connection {
    if (!connection) return;

    NSValue *connValue = [NSValue valueWithPointer:connection];

    dispatch_sync(self.poolQueue, ^{
        [self.inUsePool removeObject:connValue];
        [self.availablePool removeObject:connValue];
        [self.connectionLastUsed removeObjectForKey:connValue];

        // Close the connection
        sqlite3_exec(connection, "PRAGMA optimize", NULL, NULL, NULL);
        sqlite3_close(connection);

        // Signal that connection is no longer in use
        dispatch_semaphore_signal(self.connectionSemaphore);
    });

    GZ_LOG_DB_WARN(@"Connection invalidated and closed");
}

#pragma mark - Connection Creation

- (sqlite3 *)createNewConnection {
    sqlite3 *db = NULL;
    int result = sqlite3_open(self.databasePath.UTF8String, &db);

    if (result != SQLITE_OK) {
        GZ_LOG_DB_ERROR(@"Failed to open database: %s", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return NULL;
    }

    ATProtoDBConfig config = {
        .flags = ATProtoDBConfigFlagForeignKeys,
        .busyTimeout = (int)self.busyTimeout,
        .cacheSize = -8000,
        .walAutocheckpoint = 5000,
        .journalSizeLimit = 16777216,
        .mmapSize = 0,
        .pageSize = 0,
    };
    if ([self.journalMode caseInsensitiveCompare:@"WAL"] == NSOrderedSame) {
        config.flags |= ATProtoDBConfigFlagWAL;
    }
    if ([self.synchronousMode caseInsensitiveCompare:@"NORMAL"] == NSOrderedSame) {
        config.flags |= ATProtoDBConfigFlagSynchronousNormal;
    }

    if (!ATProtoDBConfigurePragmas(db, config)) {
        GZ_LOG_DB_ERROR(@"Failed to configure connection pragmas for %@", self.databasePath);
        sqlite3_close(db);
        return NULL;
    }

    if ((config.flags & ATProtoDBConfigFlagWAL) == 0) {
        ATProtoConnectionPoolApplyCustomPragma(db, @"journal_mode", self.journalMode);
    }
    if ((config.flags & ATProtoDBConfigFlagSynchronousNormal) == 0) {
        ATProtoConnectionPoolApplyCustomPragma(db, @"synchronous", self.synchronousMode);
    }

    return db;
}

#pragma mark - Pool Statistics

- (NSUInteger)availableConnections {
    __block NSUInteger count = 0;
    dispatch_sync(self.poolQueue, ^{
        count = self.availablePool.count;
    });
    return count;
}

- (NSUInteger)totalConnections {
    __block NSUInteger count = 0;
    dispatch_sync(self.poolQueue, ^{
        count = self.availablePool.count + self.inUsePool.count;
    });
    return count;
}

- (NSUInteger)activeConnections {
    __block NSUInteger count = 0;
    dispatch_sync(self.poolQueue, ^{
        count = self.inUsePool.count;
    });
    return count;
}

- (NSUInteger)peakConnections {
    return self.peakConnCount;
}

#pragma mark - Pool Maintenance

- (void)pruneIdleConnections {
    NSDate *now = [NSDate date];

    dispatch_sync(self.poolQueue, ^{
        // Only prune if idle timeout expired
        if ([now timeIntervalSinceDate:self.lastPruneTime] < self.idleTimeout) {
            return;
        }

        NSUInteger toRemove = 0;
        if (self.availablePool.count > self.minConnections) {
            toRemove = self.availablePool.count - self.minConnections;
        }

        if (toRemove > 0) {
            GZ_LOG_DB_INFO(@"Pruning %lu idle connections", (unsigned long)toRemove);

            for (NSUInteger i = 0; i < toRemove; i++) {
                NSValue *connValue = self.availablePool.lastObject;
                [self.availablePool removeLastObject];

                sqlite3 *conn = [connValue pointerValue];
                sqlite3_close(conn);

                [self.connectionLastUsed removeObjectForKey:connValue];
            }
        }

        self.lastPruneTime = now;
    });
}

- (void)closeAllConnections {
    dispatch_sync(self.poolQueue, ^{
        [self closeAllConnectionsNoSync];
    });
}

/// Close all connections without synchronizing on poolQueue.
/// Must be called with poolQueue already held, or from dealloc when
/// re-entrancy is detected via dispatch_get_specific.
- (void)closeAllConnectionsNoSync {
    GZ_LOG_DB_INFO(@"Closing all connections (available: %lu, in use: %lu)",
                   (unsigned long)self.availablePool.count,
                   (unsigned long)self.inUsePool.count);

    // Close available connections
    for (NSValue *connValue in self.availablePool) {
        sqlite3 *conn = [connValue pointerValue];
        sqlite3_close(conn);
    }
    [self.availablePool removeAllObjects];

    // Close in-use connections (they may be in the middle of operations)
    for (NSValue *connValue in self.inUsePool) {
        sqlite3 *conn = [connValue pointerValue];
        sqlite3_close(conn);
    }
    [self.inUsePool removeAllObjects];
    [self.connectionLastUsed removeAllObjects];
}

@end
