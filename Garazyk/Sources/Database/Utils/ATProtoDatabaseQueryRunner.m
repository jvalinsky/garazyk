// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Database/Utils/ATProtoDatabaseQueryRunner.h"
#import "Database/Connection/ATProtoConnectionManager.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Database/Utils/PDSSQLiteUtils.h"

@interface ATProtoDatabaseQueryRunner ()
@property (nonatomic, strong) id<ATProtoConnectionManager> connectionManager;
@property (nonatomic, copy) ATProtoDatabaseQueryRunnerErrorFactory errorFactory;
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
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            innerError = self.errorFactory(db, rc, @"Failed to prepare query");
            return;
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
            innerError = self.errorFactory(db, rc, @"Failed to execute query");
            return;
        }
        result = [rows copy];
    } error:&managerError];

    if (!executed || !result) {
        if (error) *error = innerError ?: [self errorFromManagerError:managerError fallback:@"Failed to execute query"];
        return nil;
    }
    return result;
}

- (BOOL)executeUpdate:(NSString *)sql
               params:(nullable NSArray *)params
           connection:(sqlite3 *)db
                error:(NSError **)error {
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = self.errorFactory(db, rc, @"Failed to prepare update");
        return NO;
    }
    ATProtoDBBindParams(stmt, params ?: @[]);

    rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        if (error) *error = self.errorFactory(db, rc, @"Failed to execute update");
        return NO;
    }
    return YES;
}

- (BOOL)performWriteTransaction:(BOOL (^)(sqlite3 *db, NSError **error))block
                          error:(NSError **)error {
    __block NSError *innerError = nil;
    NSError *managerError = nil;
    BOOL ok = [self.connectionManager transact:^(sqlite3 *db, BOOL *rollback) {
        BOOL blockOK = block(db, &innerError);
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
