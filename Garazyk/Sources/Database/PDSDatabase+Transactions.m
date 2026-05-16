// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Transactions.h"
#import "Database/PDSDatabase+Private.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
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
            if (error) *error = [self errorWithDescription:@"Cannot begin transaction: database is not open" code:PDSDatabaseErrorNotOpen];
            return;
        }
        if (sqlite3_get_autocommit(self.db) == 0) {
            if (error) *error = [self errorWithDescription:@"Cannot begin transaction: transaction already active" code:PDSDatabaseErrorQueryFailed];
            return;
        }

        char *errMsg = NULL;
        if (sqlite3_exec(self.db, "BEGIN TRANSACTION", NULL, NULL, &errMsg) != SQLITE_OK) {
            if (error) *error = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
            sqlite3_free(errMsg);
            return;
        }
        result = YES;
    }];
    return result;
}

- (BOOL)commitTransactionWithError:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{
        if (!self.isOpen || !self.db) {
            if (error) *error = [self errorWithDescription:@"Cannot commit transaction: database is not open" code:PDSDatabaseErrorNotOpen];
            return;
        }
        if (sqlite3_get_autocommit(self.db) != 0) {
            if (error) *error = [self errorWithDescription:@"Cannot commit transaction: no active transaction" code:PDSDatabaseErrorQueryFailed];
            return;
        }

        char *errMsg = NULL;
        if (sqlite3_exec(self.db, "COMMIT", NULL, NULL, &errMsg) != SQLITE_OK) {
            if (error) *error = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
            sqlite3_free(errMsg);
            return;
        }
        result = YES;
    }];
    return result;
}

- (BOOL)rollbackTransactionWithError:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{
        if (!self.isOpen || !self.db) {
            if (error) *error = [self errorWithDescription:@"Cannot roll back transaction: database is not open" code:PDSDatabaseErrorNotOpen];
            return;
        }
        if (sqlite3_get_autocommit(self.db) != 0) {
            if (error) *error = [self errorWithDescription:@"Cannot roll back transaction: no active transaction" code:PDSDatabaseErrorQueryFailed];
            return;
        }

        char *errMsg = NULL;
        if (sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, &errMsg) != SQLITE_OK) {
            if (error) *error = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
            sqlite3_free(errMsg);
            return;
        }
        result = YES;
    }];
    return result;
}

- (BOOL)transactWithBlock:(void (^)(NSError **error))block error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{
        if (!block) {
            if (error) *error = [self errorWithDescription:@"Block cannot be nil" code:PDSDatabaseErrorQueryFailed];
            return;
        }

        if (!self.isOpen || !self.db) {
            if (error) *error = [self errorWithDescription:@"Cannot start transaction: database is not open" code:PDSDatabaseErrorNotOpen];
            return;
        }

        BOOL useSavepoint = (sqlite3_get_autocommit(self.db) == 0);
        NSString *savepointName = nil;
        NSString *beginSQL = @"BEGIN TRANSACTION";
        if (useSavepoint) {
            savepointName = [[NSString stringWithFormat:@"pds_tx_%@", NSUUID.UUID.UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
            beginSQL = [NSString stringWithFormat:@"SAVEPOINT %@", savepointName];
        }

        char *errMsg = NULL;
        if (sqlite3_exec(self.db, beginSQL.UTF8String, NULL, NULL, &errMsg) != SQLITE_OK) {
            if (error) *error = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
            sqlite3_free(errMsg);
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
                return;
            }

            NSString *finishSQL = useSavepoint ? [NSString stringWithFormat:@"RELEASE %@", savepointName] : @"COMMIT";
            errMsg = NULL;
            if (sqlite3_exec(self.db, finishSQL.UTF8String, NULL, NULL, &errMsg) != SQLITE_OK) {
                if (error) *error = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
                sqlite3_free(errMsg);
                if (useSavepoint) {
                    NSString *rollbackSQL = [NSString stringWithFormat:@"ROLLBACK TO %@", savepointName];
                    sqlite3_exec(self.db, rollbackSQL.UTF8String, NULL, NULL, NULL);
                    sqlite3_exec(self.db, finishSQL.UTF8String, NULL, NULL, NULL);
                } else {
                    sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
                }
                return;
            }
            result = YES;
        } @catch (NSException *exception) {
            if (useSavepoint) {
                NSString *rollbackSQL = [NSString stringWithFormat:@"ROLLBACK TO %@", savepointName];
                NSString *releaseSQL = [NSString stringWithFormat:@"RELEASE %@", savepointName];
                sqlite3_exec(self.db, rollbackSQL.UTF8String, NULL, NULL, NULL);
                sqlite3_exec(self.db, releaseSQL.UTF8String, NULL, NULL, NULL);
            } else if (sqlite3_get_autocommit(self.db) == 0) {
                sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
            }
            if (error) *error = [self errorWithDescription:exception.reason ?: @"Transaction failed" code:PDSDatabaseErrorQueryFailed];
        }
    }];
    return result;
}

@end
