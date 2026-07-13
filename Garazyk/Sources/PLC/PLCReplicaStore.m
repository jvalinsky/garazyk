// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLCReplicaStore.h"
#import "PLCPersistentStoreInternal.h"
#import "Database/Utils/ATProtoDatabaseQueryRunner.h"

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
    
    if ([self.queryRunner executeUpdate:kCreateSyncStateTableSQL params:nil error:error] < 0) {
        return NO;
    }
    self.syncStateTableCreated = YES;
    return YES;
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
    
    NSInteger now = (NSInteger)[[NSDate date] timeIntervalSince1970];
    return [self.queryRunner executeUpdate:kUpsertSyncStateSQL
                                    params:@[key, value, @(now)]
                                     error:error] >= 0;
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
    
    NSArray<NSDictionary<NSString *, id> *> *rows = [self.queryRunner executeQuery:kSelectSyncStateSQL
                                                                            params:@[key]
                                                                             error:error];
    if (rows.count > 0) {
        id val = rows.firstObject[@"value"];
        if ([val isKindOfClass:[NSString class]]) {
            return val;
        }
    }
    return nil;
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
    
    NSArray<NSDictionary<NSString *, id> *> *rows = [self.queryRunner executeQuery:kCountOperationsSQL
                                                                            params:nil
                                                                             error:error];
    if (rows.count > 0) {
        id countVal = rows.firstObject.allValues.firstObject;
        if ([countVal respondsToSelector:@selector(unsignedIntegerValue)]) {
            return [countVal unsignedIntegerValue];
        }
    }
    return 0;
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
    
    NSArray<NSDictionary<NSString *, id> *> *rows = [self.queryRunner executeQuery:kCountUniqueDIDsSQL
                                                                            params:nil
                                                                             error:error];
    if (rows.count > 0) {
        id countVal = rows.firstObject.allValues.firstObject;
        if ([countVal respondsToSelector:@selector(unsignedIntegerValue)]) {
            return [countVal unsignedIntegerValue];
        }
    }
    return 0;
}

@end