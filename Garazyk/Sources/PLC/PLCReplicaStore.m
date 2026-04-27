#import "PLCReplicaStore.h"
#import "PLCPersistentStoreInternal.h"

NSString * const PLCReplicaStoreErrorDomain = @"com.atproto.pds.plc.replicastore";

static NSString * const kCreateSyncStateTableSQL =
    @"CREATE TABLE IF NOT EXISTS plc_sync_state ("
    @"  key TEXT PRIMARY KEY,"
    @"  value TEXT,"
    @"  updated_at INTEGER"
    @");";

static NSString * const kUpsertSyncStateSQL =
    @"INSERT INTO plc_sync_state (key, value, updated_at) VALUES (?, ?, ?) "
    @"ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;";

static NSString * const kSelectSyncStateSQL =
    @"SELECT value FROM plc_sync_state WHERE key = ?;";

static NSString * const kCountOperationsSQL =
    @"SELECT COUNT(*) FROM plc_operations;";

static NSString * const kCountUniqueDIDsSQL =
    @"SELECT COUNT(DISTINCT did) FROM plc_operations;";

@interface PLCReplicaStore ()

@property (nonatomic, assign) BOOL syncStateTableCreated;

@end

@implementation PLCReplicaStore

- (BOOL)openWithError:(NSError **)error {
    if (![super openWithError:error]) {
        return NO;
    }
    
    if (!self.open) {
        return NO;
    }
    
    return [self createSyncStateTableIfNeeded:error];
}

- (BOOL)createSyncStateTableIfNeeded:(NSError **)error {
    if (self.syncStateTableCreated) {
        return YES;
    }
    
    __block BOOL success = NO;
    __block NSError *blockError = nil;
    
    dispatch_sync(self.transactionQueue, ^{
        char *errMsg = NULL;
        int result = sqlite3_exec(self.db, kCreateSyncStateTableSQL.UTF8String, NULL, NULL, &errMsg);
        
        if (result == SQLITE_OK) {
            success = YES;
            self.syncStateTableCreated = YES;
        } else {
            if (errMsg) {
                blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                                 code:PLCPersistentStoreErrorInvalidOperation
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg]}];
                sqlite3_free(errMsg);
            }
        }
    });
    
    if (error && blockError) {
        *error = blockError;
    }
    
    return success;
}

- (BOOL)updateSyncStateValue:(NSString *)key value:(NSString *)value error:(NSError **)error {
    if (!self.open) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                         code:PLCPersistentStoreErrorDatabaseClosed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Database is closed"}];
        }
        return NO;
    }
    
    if (![self createSyncStateTableIfNeeded:error]) {
        return NO;
    }
    
    __block BOOL success = NO;
    __block NSError *blockError = nil;
    NSInteger now = (NSInteger)[[NSDate date] timeIntervalSince1970];
    
    dispatch_sync(self.transactionQueue, ^{
        sqlite3_stmt *stmt = [self prepareStatement:kUpsertSyncStateSQL error:&blockError];
        if (!stmt) {
            return;
        }
        
        sqlite3_bind_text(stmt, 1, key.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, value.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 3, now);
        
        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        } else {
            blockError = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                            code:PLCPersistentStoreErrorInvalidOperation
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to update sync state"}];
        }
        
        sqlite3_reset(stmt);
    });
    
    if (error && blockError) {
        *error = blockError;
    }
    
    return success;
}

- (nullable NSString *)getSyncStateValue:(NSString *)key error:(NSError **)error {
    if (!self.open) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                         code:PLCPersistentStoreErrorDatabaseClosed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Database is closed"}];
        }
        return nil;
    }
    
    __block NSString *value = nil;
    __block NSError *blockError = nil;
    
    dispatch_sync(self.transactionQueue, ^{
        sqlite3_stmt *stmt = [self prepareStatement:kSelectSyncStateSQL error:&blockError];
        if (!stmt) {
            return;
        }
        
        sqlite3_bind_text(stmt, 1, key.UTF8String, -1, SQLITE_TRANSIENT);
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *text = (const char *)sqlite3_column_text(stmt, 0);
            if (text) {
                value = [NSString stringWithUTF8String:text];
            }
        }
        
        sqlite3_reset(stmt);
    });
    
    if (error && blockError) {
        *error = blockError;
    }
    
    return value;
}

#pragma mark - Public Sync State Methods

- (BOOL)updateSyncCursor:(NSInteger)cursor error:(NSError **)error {
    return [self updateSyncStateValue:@"last_cursor" value:[NSString stringWithFormat:@"%ld", (long)cursor] error:error];
}

- (NSInteger)lastSyncCursorWithError:(NSError **)error {
    NSString *value = [self getSyncStateValue:@"last_cursor" error:error];
    if (value) {
        return value.integerValue;
    }
    return 0;
}

- (BOOL)updateLastSyncTimestamp:(NSDate *)timestamp error:(NSError **)error {
    NSInteger ts = (NSInteger)[timestamp timeIntervalSince1970];
    return [self updateSyncStateValue:@"last_sync_timestamp" value:[NSString stringWithFormat:@"%ld", (long)ts] error:error];
}

- (nullable NSDate *)lastSyncTimestampWithError:(NSError **)error {
    NSString *value = [self getSyncStateValue:@"last_sync_timestamp" error:error];
    if (value) {
        return [NSDate dateWithTimeIntervalSince1970:value.doubleValue];
    }
    return nil;
}

- (BOOL)updateUpstreamURL:(NSString *)url error:(NSError **)error {
    return [self updateSyncStateValue:@"upstream_url" value:url error:error];
}

- (nullable NSString *)upstreamURLWithError:(NSError **)error {
    return [self getSyncStateValue:@"upstream_url" error:error];
}

- (BOOL)updateSyncState:(NSString *)state error:(NSError **)error {
    return [self updateSyncStateValue:@"sync_state" value:state error:error];
}

- (nullable NSString *)syncStateWithError:(NSError **)error {
    return [self getSyncStateValue:@"sync_state" error:error];
}

- (BOOL)updateLatestIngestedCursor:(NSInteger)cursor error:(NSError **)error {
    return [self updateSyncStateValue:@"latest_ingested_cursor" value:[NSString stringWithFormat:@"%ld", (long)cursor] error:error];
}

- (NSInteger)latestIngestedCursorWithError:(NSError **)error {
    NSString *value = [self getSyncStateValue:@"latest_ingested_cursor" error:error];
    if (value) {
        return value.integerValue;
    }
    return 0;
}

- (NSUInteger)totalOperationCountWithError:(NSError **)error {
    if (!self.open) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                         code:PLCPersistentStoreErrorDatabaseClosed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Database is closed"}];
        }
        return 0;
    }
    
    __block NSUInteger count = 0;
    __block NSError *blockError = nil;
    
    dispatch_sync(self.transactionQueue, ^{
        sqlite3_stmt *stmt = [self prepareStatement:kCountOperationsSQL error:&blockError];
        if (!stmt) {
            return;
        }
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            count = (NSUInteger)sqlite3_column_int64(stmt, 0);
        }
        
        sqlite3_reset(stmt);
    });
    
    if (error && blockError) {
        *error = blockError;
    }
    
    return count;
}

- (NSUInteger)uniqueDIDCountWithError:(NSError **)error {
    if (!self.open) {
        if (error) {
            *error = [NSError errorWithDomain:PLCPersistentStoreErrorDomain
                                         code:PLCPersistentStoreErrorDatabaseClosed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Database is closed"}];
        }
        return 0;
    }
    
    __block NSUInteger count = 0;
    __block NSError *blockError = nil;
    
    dispatch_sync(self.transactionQueue, ^{
        sqlite3_stmt *stmt = [self prepareStatement:kCountUniqueDIDsSQL error:&blockError];
        if (!stmt) {
            return;
        }
        
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            count = (NSUInteger)sqlite3_column_int64(stmt, 0);
        }
        
        sqlite3_reset(stmt);
    });
    
    if (error && blockError) {
        *error = blockError;
    }
    
    return count;
}

@end