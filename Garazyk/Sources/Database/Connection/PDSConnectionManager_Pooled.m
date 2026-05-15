// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/Connection/PDSConnectionManager_Pooled.h"
#import "Database/Pool/PDSConnectionPool.h"

@interface PDSConnectionManager_Pooled ()
@property (nonatomic, readwrite, getter=isOpen) BOOL open;
@property (nonatomic, readwrite, copy) NSString *databasePath;
@property (nonatomic, strong) PDSConnectionPool *pool;
@end

@implementation PDSConnectionManager_Pooled

- (instancetype)initWithPool:(PDSConnectionPool *)pool {
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

- (BOOL)openWithPath:(NSString *)path config:(PDSDBConfig)config error:(NSError **)error {
    if (error) {
        *error = PDSDBError(PDSDBErrorDomain,
                            @"PDSConnectionManager_Pooled requires initWithPool:",
                            PDSDBErrorQueryFailed);
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
            *error = PDSDBError(PDSDBErrorDomain,
                                @"Pool not available", PDSDBErrorNotOpen);
        }
        return NO;
    }

    sqlite3 *db = [self.pool acquireConnection];
    if (!db) {
        if (error) {
            *error = PDSDBError(PDSDBErrorDomain,
                                @"Failed to acquire connection from pool",
                                PDSDBErrorNotOpen);
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
            *error = PDSDBError(PDSDBErrorDomain,
                                @"Pool not available", PDSDBErrorNotOpen);
        }
        return NO;
    }

    sqlite3 *db = [self.pool acquireConnection];
    if (!db) {
        if (error) {
            *error = PDSDBError(PDSDBErrorDomain,
                                @"Failed to acquire connection from pool",
                                PDSDBErrorNotOpen);
        }
        return NO;
    }

    char *errMsg = NULL;
    int rc = sqlite3_exec(db, "BEGIN", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = PDSDBSQLError(PDSDBErrorDomain, db, PDSDBErrorQueryFailed);
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
            *error = PDSDBError(PDSDBErrorDomain,
                                @"Transaction rolled back",
                                PDSDBErrorQueryFailed);
        }
        return NO;
    }

    rc = sqlite3_exec(db, "COMMIT", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = PDSDBSQLError(PDSDBErrorDomain, db, PDSDBErrorQueryFailed);
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
