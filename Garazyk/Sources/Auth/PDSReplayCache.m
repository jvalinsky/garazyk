// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/PDSReplayCache.h"
#import "Database/Connection/ATProtoConnectionManagerSerial.h"
#import "Database/Utils/ATProtoDatabaseQueryRunner.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Debug/GZLogger.h"

static NSString * const PDSReplayCacheErrorDomain = @"com.garazyk.auth.replay-cache";

@implementation PDSReplayCache {
    ATProtoConnectionManagerSerial *_connectionManager;
    ATProtoDatabaseQueryRunner *_queryRunner;
    dispatch_source_t _cleanupTimer;
    dispatch_queue_t _timerQueue;
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
        _connectionManager = [[ATProtoConnectionManagerSerial alloc] initWithLabel:@"com.garazyk.auth.replay-cache.database"];
        NSError *error = nil;
        if (![_connectionManager openWithPath:(path ?: @":memory:")
                                       config:ATProtoDBConfigDefault
                                        error:&error]) {
            GZ_LOG_AUTH_ERROR(@"Failed to open replay cache database: %@", error);
            return nil;
        }
        _queryRunner = [[ATProtoDatabaseQueryRunner alloc] initWithConnectionManager:_connectionManager
                                                                         errorDomain:PDSReplayCacheErrorDomain];
        if (![self createSchema:&error]) {
            GZ_LOG_AUTH_ERROR(@"Failed to create jti_cache table: %@", error);
            [_connectionManager close];
            return nil;
        }

        // Periodic cleanup via a dispatch_source on a dedicated timer queue. The handler
        // routes cleanup through the connection manager's own serial queue, so it never
        // blocks on the queue it is firing on.
        _timerQueue = dispatch_queue_create("com.garazyk.auth.replay-cache.timer", DISPATCH_QUEUE_SERIAL);
        _cleanupTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _timerQueue);
        if (_cleanupTimer) {
            dispatch_source_set_timer(_cleanupTimer,
                                      dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_SEC),
                                      300 * NSEC_PER_SEC,
                                      0);
            __weak typeof(self) weakSelf = self;
            dispatch_source_set_event_handler(_cleanupTimer, ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf cleanup];
                }
            });
            dispatch_resume(_cleanupTimer);
        }
    }
    return self;
}

- (BOOL)createSchema:(NSError **)error {
    if ([_queryRunner executeUpdate:@"CREATE TABLE IF NOT EXISTS jti_cache (jti TEXT PRIMARY KEY, expires_at REAL NOT NULL)"
                             params:nil
                              error:error] < 0) {
        return NO;
    }
    if ([_queryRunner executeUpdate:@"CREATE INDEX IF NOT EXISTS idx_jti_cache_expires_at ON jti_cache(expires_at)"
                             params:nil
                              error:error] < 0) {
        return NO;
    }
    return YES;
}

- (void)invalidate {
    if (_cleanupTimer) {
        dispatch_source_cancel(_cleanupTimer);
        _cleanupTimer = nil;
    }
    [_connectionManager close];
    _connectionManager = nil;
}

- (void)dealloc {
    [self invalidate];
}

- (BOOL)checkAndAddJTI:(NSString *)jti expiration:(NSDate *)expiration {
    if (!jti || !expiration) return NO;

    NSTimeInterval expiresAt = [expiration timeIntervalSince1970];
    __block BOOL result = NO;
    NSError *error = nil;

    // Atomic check-and-add inside one transaction (the connection manager is serial, so
    // concurrent callers cannot interleave). Returning YES commits; NO rolls back. The
    // caller-facing answer travels in `result`, independent of the commit/rollback flag.
    [_queryRunner performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

        NSArray<NSDictionary<NSString *, id> *> *rows =
            [tx executeQuery:@"SELECT expires_at FROM jti_cache WHERE jti = ?" params:@[jti] error:innerError];
        if (!rows) {
            return NO;  // query failed -> roll back; result stays NO
        }
        if (rows.count > 0 && [rows.firstObject[@"expires_at"] doubleValue] >= now) {
            return YES;  // replay: a non-expired entry exists. Commit; leave result NO.
        }

        // New JTI, or a stale (expired) one being reused.
        if (![tx executeUpdate:@"INSERT OR REPLACE INTO jti_cache (jti, expires_at) VALUES (?, ?)"
                        params:@[jti, @(expiresAt)]
                         error:innerError]) {
            return NO;  // insert failed -> roll back; result stays NO
        }
        result = YES;
        return YES;
    } error:&error];

    return result;
}

- (void)cleanup {
    [_queryRunner executeUpdate:@"DELETE FROM jti_cache WHERE expires_at < ?"
                         params:@[@([[NSDate date] timeIntervalSince1970])]
                          error:NULL];
}

@end
