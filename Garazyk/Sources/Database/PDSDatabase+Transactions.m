// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Transactions.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>

@implementation PDSDatabase (Transactions)

#pragma mark - Transactions

- (BOOL)performTransaction:(BOOL (^)(PDSDatabase *db, NSError **error))block error:(NSError **)error {
    if (![self beginTransactionWithError:error]) {
        return NO;
    }

    NSError *localError = nil;
    BOOL success = block(self, &localError);

    if (success) {
        if (![self commitTransactionWithError:error]) {
            [self rollbackTransactionWithError:nil];
            return NO;
        }
        return YES;
    } else {
        [self rollbackTransactionWithError:nil];
        if (error) *error = localError;
        return NO;
    }
}

- (BOOL)beginTransactionWithError:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!self.isOpen || !self.db) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot begin transaction: database is not open"
                                           code:PDSDatabaseErrorNotOpen];
        }
        result = NO;
        return;
    }
    if (sqlite3_get_autocommit(self.db) == 0) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot begin transaction: transaction already active; use transactWithBlock:error: for nested work"
                                           code:PDSDatabaseErrorQueryFailed];
        }
        result = NO;
        return;
    }

    char *errMsg = NULL;
    int rc = sqlite3_exec(self.db, "BEGIN TRANSACTION", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }
    result = YES;
    return;
    }];
    return result;
}

- (BOOL)commitTransactionWithError:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!self.isOpen || !self.db) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot commit transaction: database is not open"
                                           code:PDSDatabaseErrorNotOpen];
        }
        result = NO;
        return;
    }
    if (sqlite3_get_autocommit(self.db) != 0) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot commit transaction: no active transaction"
                                           code:PDSDatabaseErrorQueryFailed];
        }
        result = NO;
        return;
    }

    char *errMsg = NULL;
    int rc = sqlite3_exec(self.db, "COMMIT", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }
    result = YES;
    return;
    }];
    return result;
}

- (BOOL)rollbackTransactionWithError:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!self.isOpen || !self.db) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot roll back transaction: database is not open"
                                           code:PDSDatabaseErrorNotOpen];
        }
        result = NO;
        return;
    }
    if (sqlite3_get_autocommit(self.db) != 0) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot roll back transaction: no active transaction"
                                           code:PDSDatabaseErrorQueryFailed];
        }
        result = NO;
        return;
    }

    char *errMsg = NULL;
    int rc = sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }
    result = YES;
    return;
    }];
    return result;
}

- (BOOL)transactWithBlock:(void (^)(NSError **error))block error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!block) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                          code:PDSDatabaseErrorQueryFailed
                                      userInfo:@{NSLocalizedDescriptionKey: @"Block cannot be nil"}];
        }
        result = NO;
        return;
    }

    if (!self.isOpen || !self.db) {
        if (error) {
            *error = [self errorWithDescription:@"Cannot start transaction: database is not open"
                                           code:PDSDatabaseErrorNotOpen];
        }
        result = NO;
        return;
    }

    BOOL useSavepoint = (sqlite3_get_autocommit(self.db) == 0);
    NSString *savepointName = nil;
    NSString *beginSQL = @"BEGIN TRANSACTION";
    if (useSavepoint) {
        savepointName = [[NSString stringWithFormat:@"pds_tx_%@", NSUUID.UUID.UUIDString]
                         stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
        beginSQL = [NSString stringWithFormat:@"SAVEPOINT %@", savepointName];
    }

    char *errMsg = NULL;
    int rc = sqlite3_exec(self.db, beginSQL.UTF8String, NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        result = NO;
        return;
    }

    @try {
        NSError *blockError = nil;
        block(&blockError);

        if (blockError) {
            if (useSavepoint) {
                NSString *rollbackSQL = [NSString stringWithFormat:@"ROLLBACK TO %@", savepointName];
                NSString *releaseSQL = [NSString stringWithFormat:@"RELEASE %@", savepointName];
                sqlite3_exec(self.db, rollbackSQL.UTF8String, NULL, NULL, NULL);
                sqlite3_exec(self.db, releaseSQL.UTF8String, NULL, NULL, NULL);
            } else if (sqlite3_get_autocommit(self.db) == 0) {
                sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
            }
            if (error) *error = blockError;
            result = NO;
            return;
        }

        if (sqlite3_get_autocommit(self.db) != 0) {
            if (error) {
                NSString *message = useSavepoint
                    ? @"Cannot release transaction savepoint: enclosing transaction was closed inside transaction block"
                    : @"Cannot commit transaction: transaction was closed inside transaction block";
                *error = [self errorWithDescription:message code:PDSDatabaseErrorQueryFailed];
            }
            result = NO;
            return;
        }

        NSString *finishSQL = useSavepoint ? [NSString stringWithFormat:@"RELEASE %@", savepointName] : @"COMMIT";
        errMsg = NULL;
        rc = sqlite3_exec(self.db, finishSQL.UTF8String, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            NSError *commitError = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
            sqlite3_free(errMsg);
            if (useSavepoint) {
                NSString *rollbackSQL = [NSString stringWithFormat:@"ROLLBACK TO %@", savepointName];
                NSString *releaseSQL = [NSString stringWithFormat:@"RELEASE %@", savepointName];
                sqlite3_exec(self.db, rollbackSQL.UTF8String, NULL, NULL, NULL);
                sqlite3_exec(self.db, releaseSQL.UTF8String, NULL, NULL, NULL);
            } else if (sqlite3_get_autocommit(self.db) == 0) {
                sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
            }
            if (error) *error = commitError;
            result = NO;
            return;
        }
        result = YES;
        return;
    } @catch (NSException *exception) {
        if (useSavepoint) {
            NSString *rollbackSQL = [NSString stringWithFormat:@"ROLLBACK TO %@", savepointName];
            NSString *releaseSQL = [NSString stringWithFormat:@"RELEASE %@", savepointName];
            sqlite3_exec(self.db, rollbackSQL.UTF8String, NULL, NULL, NULL);
            sqlite3_exec(self.db, releaseSQL.UTF8String, NULL, NULL, NULL);
        } else if (sqlite3_get_autocommit(self.db) == 0) {
            sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
        }
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                          code:PDSDatabaseErrorQueryFailed
                                      userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Transaction failed"}];
        }
        result = NO;
        return;
    }
    }];
    return result;
}

- (NSString *)expandPlaceholdersForArray:(NSArray *)values {
    return [self parameterPlaceholdersForCount:values.count];
}

- (NSString *)parameterPlaceholdersForCount:(NSUInteger)count {
    if (count == 0) return @"";
    NSMutableArray *placeholders = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        [placeholders addObject:@"?"];
    }
    return [placeholders componentsJoinedByString:@", "];
}

@end