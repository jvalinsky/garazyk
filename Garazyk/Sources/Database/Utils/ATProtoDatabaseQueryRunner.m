// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Database/Utils/ATProtoDatabaseQueryRunner.h"
#import "Database/Connection/ATProtoConnectionManager.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Database/Utils/PDSSQLiteUtils.h"

@interface ATProtoDatabaseQueryRunner ()
@property (nonatomic, strong) id<ATProtoConnectionManager> connectionManager;
@property (nonatomic, copy) ATProtoDatabaseQueryRunnerErrorFactory errorFactory;

// Core prepare/bind/step mechanics against an already-open connection, shared by the
// self-managing methods (which obtain the connection from the ConnectionManager) and the
// transaction-scoped transactor (which binds the in-flight transaction's connection).
- (nullable NSArray<NSDictionary<NSString *, id> *> *)queryOnConnection:(sqlite3 *)db
                                                                   sql:(NSString *)sql
                                                                params:(nullable NSArray *)params
                                                                 error:(NSError **)error;
- (NSInteger)updateOnConnection:(sqlite3 *)db
                            sql:(NSString *)sql
                         params:(nullable NSArray *)params
                          error:(NSError **)error;
@end

/// Private transactor: binds the runner's prepare/bind/step mechanics to one transaction's
/// connection, so a -performWriteTransaction: block receives read/write verbs instead of a
/// raw sqlite3 *. Short-lived — created and used entirely within the transaction block.
@interface ATProtoDatabaseQueryRunnerTransactor : NSObject <ATProtoDatabaseTransactor>
- (instancetype)initWithRunner:(ATProtoDatabaseQueryRunner *)runner connection:(sqlite3 *)db;
@end

@implementation ATProtoDatabaseQueryRunner

- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)connectionManager
                              errorDomain:(NSString *)errorDomain {
    NSString *domain = [errorDomain copy];
    ATProtoDatabaseQueryRunnerErrorFactory factory =
        ^NSError *(sqlite3 *db, NSInteger code, NSString *fallback) {
            if (db) {
                return ATProtoDBSQLError(domain, db, code);
            }
            return ATProtoDBError(domain, fallback ?: @"SQLite error", code);
        };
    return [self initWithConnectionManager:connectionManager errorFactory:factory];
}

- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)connectionManager
                             errorFactory:(ATProtoDatabaseQueryRunnerErrorFactory)errorFactory {
    self = [super init];
    if (!self) return nil;
    _connectionManager = connectionManager;
    _errorFactory = [errorFactory copy];
    return self;
}

- (nullable NSArray<NSDictionary<NSString *, id> *> *)executeQuery:(NSString *)sql
                                                            params:(nullable NSArray *)params
                                                             error:(NSError **)error {
    __block NSArray<NSDictionary<NSString *, id> *> *result = nil;
    __block NSError *innerError = nil;
    NSError *managerError = nil;
    BOOL executed = [self.connectionManager execute:^(sqlite3 *db) {
        result = [self queryOnConnection:db sql:sql params:params error:&innerError];
    } error:&managerError];

    if (!executed || !result) {
        if (error) *error = innerError ?: [self errorFromManagerError:managerError fallback:@"Failed to execute query"];
        return nil;
    }
    return result;
}

- (NSInteger)executeUpdate:(NSString *)sql
                    params:(nullable NSArray *)params
                     error:(NSError **)error {
    __block NSInteger changes = -1;
    __block NSError *innerError = nil;
    NSError *managerError = nil;
    BOOL executed = [self.connectionManager execute:^(sqlite3 *db) {
        changes = [self updateOnConnection:db sql:sql params:params error:&innerError];
    } error:&managerError];

    if (!executed || changes < 0) {
        if (error) *error = innerError ?: [self errorFromManagerError:managerError fallback:@"Failed to execute update"];
        return -1;
    }
    return changes;
}

#pragma mark - Connection-scoped mechanics (shared with the transactor)

- (nullable NSArray<NSDictionary<NSString *, id> *> *)queryOnConnection:(sqlite3 *)db
                                                                   sql:(NSString *)sql
                                                                params:(nullable NSArray *)params
                                                                 error:(NSError **)error {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = self.errorFactory(db, rc, @"Failed to prepare query");
        return nil;
    }
    ATProtoDBBindParams(stmt, params ?: @[]);

    NSMutableArray<NSDictionary<NSString *, id> *> *rows = [NSMutableArray array];
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        NSMutableDictionary<NSString *, id> *row = [NSMutableDictionary dictionary];
        int count = sqlite3_column_count(stmt);
        for (int i = 0; i < count; i++) {
            const char *name = sqlite3_column_name(stmt, i);
            if (!name) continue;
            row[[NSString stringWithUTF8String:name]] = ATProtoDBColumnValue(stmt, i) ?: [NSNull null];
        }
        [rows addObject:row];
    }

    if (rc != SQLITE_DONE) {
        if (error) *error = self.errorFactory(db, rc, @"Failed to execute query");
        return nil;
    }
    return [rows copy];
}

- (NSInteger)updateOnConnection:(sqlite3 *)db
                            sql:(NSString *)sql
                         params:(nullable NSArray *)params
                          error:(NSError **)error {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = self.errorFactory(db, rc, @"Failed to prepare update");
        return -1;
    }
    ATProtoDBBindParams(stmt, params ?: @[]);

    rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        if (error) *error = self.errorFactory(db, rc, @"Failed to execute update");
        return -1;
    }
    return sqlite3_changes(db);
}

- (BOOL)performWriteTransaction:(BOOL (^)(id<ATProtoDatabaseTransactor> tx, NSError **error))block
                          error:(NSError **)error {
    __block NSError *innerError = nil;
    NSError *managerError = nil;
    BOOL ok = [self.connectionManager transact:^(sqlite3 *db, BOOL *rollback) {
        ATProtoDatabaseQueryRunnerTransactor *tx =
            [[ATProtoDatabaseQueryRunnerTransactor alloc] initWithRunner:self connection:db];
        BOOL blockOK = block(tx, &innerError);
        *rollback = !blockOK;
    } error:&managerError];

    if (!ok && error) {
        *error = innerError ?: [self errorFromManagerError:managerError fallback:@"Transaction failed"];
    }
    return ok;
}

- (NSError *)errorFromManagerError:(NSError *)managerError fallback:(NSString *)fallback {
    if (managerError) {
        return self.errorFactory(nil, managerError.code, managerError.localizedDescription ?: fallback);
    }
    return self.errorFactory(nil, SQLITE_ERROR, fallback);
}

@end

@implementation ATProtoDatabaseQueryRunnerTransactor {
    ATProtoDatabaseQueryRunner *_runner;
    sqlite3 *_db;
}

- (instancetype)initWithRunner:(ATProtoDatabaseQueryRunner *)runner connection:(sqlite3 *)db {
    self = [super init];
    if (self) {
        _runner = runner;
        _db = db;
    }
    return self;
}

- (nullable NSArray<NSDictionary<NSString *, id> *> *)executeQuery:(NSString *)sql
                                                            params:(nullable NSArray *)params
                                                             error:(NSError **)error {
    return [_runner queryOnConnection:_db sql:sql params:params error:error];
}

- (BOOL)executeUpdate:(NSString *)sql
               params:(nullable NSArray *)params
                error:(NSError **)error {
    // updateOnConnection: returns the affected-row count (>= 0) or -1 on failure (with *error
    // set). Collapse to BOOL success — a transaction caller rolls back on the error, and a
    // successful zero-row write is still success, matching the old connection: variant.
    return [_runner updateOnConnection:_db sql:sql params:params error:error] >= 0;
}

@end
