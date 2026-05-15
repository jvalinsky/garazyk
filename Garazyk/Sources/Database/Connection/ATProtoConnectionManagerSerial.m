// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/Connection/ATProtoConnectionManagerSerial.h"
#import "Compat/PDSTypes.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@interface ATProtoConnectionManagerSerial ()
@property (nonatomic, readwrite, getter=isOpen) BOOL open;
@property (nonatomic, readwrite, copy) NSString *databasePath;
@property (nonatomic, readwrite) sqlite3 *db;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@end

@implementation ATProtoConnectionManagerSerial

- (instancetype)initWithLabel:(NSString *)label {
    if ((self = [super init])) {
        _queue = dispatch_queue_create(label.UTF8String ?: "com.garazyk.db.serial",
                                       DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self close];
}

- (BOOL)openWithPath:(NSString *)path config:(ATProtoDBConfig)config error:(NSError **)error {
    __block BOOL result = NO;
    dispatch_sync(self.queue, ^{
        if (self.db) {
            self.open = NO;
            sqlite3_close_v2(self.db);
            self.db = NULL;
        }

        int rc = sqlite3_open(path.fileSystemRepresentation, &_db);
        if (rc != SQLITE_OK) {
            if (error) {
                *error = ATProtoDBSQLError(ATProtoDBErrorDomain, _db, ATProtoDBErrorNotOpen);
            }
            if (_db) {
                sqlite3_close_v2(_db);
                _db = NULL;
            }
            result = NO;
            return;
        }

        if (!ATProtoDBConfigurePragmas(_db, config)) {
            if (error) {
                *error = ATProtoDBError(ATProtoDBErrorDomain,
                                    @"Failed to configure database pragmas",
                                    ATProtoDBErrorQueryFailed);
            }
            sqlite3_close_v2(_db);
            _db = NULL;
            result = NO;
            return;
        }

        self.databasePath = [path copy];
        self.open = YES;
        result = YES;
    });
    return result;
}

- (void)close {
    dispatch_sync(self.queue, ^{
        if (self.db) {
            sqlite3_close_v2(self.db);
            self.db = NULL;
        }
        self.open = NO;
        self.databasePath = nil;
    });
}

- (BOOL)execute:(void(^)(sqlite3 *db))block error:(NSError **)error {
    if (!block) return NO;
    if (!self.db) {
        if (error) {
            *error = ATProtoDBError(ATProtoDBErrorDomain,
                                @"Database not open", ATProtoDBErrorNotOpen);
        }
        return NO;
    }

    __block BOOL result = NO;
    dispatch_sync(self.queue, ^{
        if (!self.db) {
            result = NO;
            return;
        }
        block(self.db);
        result = YES;
    });
    return result;
}

- (BOOL)transact:(void(^)(sqlite3 *db, BOOL *rollback))block error:(NSError **)error {
    if (!block) return NO;
    if (!self.db) {
        if (error) {
            *error = ATProtoDBError(ATProtoDBErrorDomain,
                                @"Database not open", ATProtoDBErrorNotOpen);
        }
        return NO;
    }

    __block BOOL result = NO;
    dispatch_sync(self.queue, ^{
        if (!self.db) {
            result = NO;
            return;
        }

        char *errMsg = NULL;
        int rc = sqlite3_exec(self.db, "BEGIN", NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            if (error) {
                *error = ATProtoDBSQLError(ATProtoDBErrorDomain, self.db,
                                       ATProtoDBErrorQueryFailed);
            }
            sqlite3_free(errMsg);
            result = NO;
            return;
        }

        BOOL rollback = NO;
        block(self.db, &rollback);

        if (rollback) {
            sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
            if (error) {
                *error = ATProtoDBError(ATProtoDBErrorDomain,
                                    @"Transaction rolled back",
                                    ATProtoDBErrorQueryFailed);
            }
            result = NO;
        } else {
            rc = sqlite3_exec(self.db, "COMMIT", NULL, NULL, &errMsg);
            if (rc != SQLITE_OK) {
                if (error) {
                    *error = ATProtoDBSQLError(ATProtoDBErrorDomain, self.db,
                                           ATProtoDBErrorQueryFailed);
                }
                sqlite3_free(errMsg);
                sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
                result = NO;
            } else {
                result = YES;
            }
        }
    });
    return result;
}

@end

#pragma clang diagnostic pop
