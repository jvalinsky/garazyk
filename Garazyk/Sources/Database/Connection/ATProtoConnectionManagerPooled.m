// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/Connection/ATProtoConnectionManagerPooled.h"
#import "Database/Pool/ATProtoConnectionPool.h"

@interface ATProtoConnectionManagerPooled ()
@property (nonatomic, readwrite, getter=isOpen) BOOL open;
@property (nonatomic, readwrite, copy) NSString *databasePath;
@property (nonatomic, strong) ATProtoConnectionPool *pool;
@end

@implementation ATProtoConnectionManagerPooled

- (instancetype)initWithPool:(ATProtoConnectionPool *)pool {
    if ((self = [super init])) {
        _pool = pool;
        _databasePath = [pool.databasePath copy];
        _open = YES;
    }
    return self;
}

- (void)dealloc {
    [self close];
}

- (BOOL)openWithPath:(NSString *)path config:(ATProtoDBConfig)config error:(NSError **)error {
    (void)path;
    (void)config;
    if (error) {
        *error = ATProtoDBError(ATProtoDBErrorDomain,
                            @"ATProtoConnectionManagerPooled requires initWithPool:",
                            ATProtoDBErrorQueryFailed);
    }
    return NO;
}

- (void)close {
    [self.pool closeAllConnections];
    self.open = NO;
}

- (BOOL)execute:(void(^)(sqlite3 *db))block error:(NSError **)error {
    if (!block) return NO;
    if (!self.pool) {
        if (error) {
            *error = ATProtoDBError(ATProtoDBErrorDomain,
                                @"Pool not available", ATProtoDBErrorNotOpen);
        }
        return NO;
    }

    sqlite3 *db = [self.pool acquireConnection];
    if (!db) {
        if (error) {
            *error = ATProtoDBError(ATProtoDBErrorDomain,
                                @"Failed to acquire connection from pool",
                                ATProtoDBErrorNotOpen);
        }
        return NO;
    }

    block(db);
    [self.pool releaseConnection:db];
    return YES;
}

- (BOOL)transact:(void(^)(sqlite3 *db, BOOL *rollback))block error:(NSError **)error {
    if (!block) return NO;
    if (!self.pool) {
        if (error) {
            *error = ATProtoDBError(ATProtoDBErrorDomain,
                                @"Pool not available", ATProtoDBErrorNotOpen);
        }
        return NO;
    }

    sqlite3 *db = [self.pool acquireConnection];
    if (!db) {
        if (error) {
            *error = ATProtoDBError(ATProtoDBErrorDomain,
                                @"Failed to acquire connection from pool",
                                ATProtoDBErrorNotOpen);
        }
        return NO;
    }

    char *errMsg = NULL;
    int rc = sqlite3_exec(db, "BEGIN IMMEDIATE", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = ATProtoDBSQLError(ATProtoDBErrorDomain, db, ATProtoDBErrorQueryFailed);
        }
        sqlite3_free(errMsg);
        [self.pool releaseConnection:db];
        return NO;
    }

    BOOL rollback = NO;
    block(db, &rollback);

    if (rollback) {
        sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
        [self.pool releaseConnection:db];
        if (error) {
            *error = ATProtoDBError(ATProtoDBErrorDomain,
                                @"Transaction rolled back",
                                ATProtoDBErrorQueryFailed);
        }
        return NO;
    }

    rc = sqlite3_exec(db, "COMMIT", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = ATProtoDBSQLError(ATProtoDBErrorDomain, db, ATProtoDBErrorQueryFailed);
        }
        sqlite3_free(errMsg);
        sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
        [self.pool releaseConnection:db];
        return NO;
    }

    [self.pool releaseConnection:db];
    return YES;
}

@end
