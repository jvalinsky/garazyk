/*!
 @file TutorialSQLiteHelper.m

 @abstract Thread-safe SQLite wrapper implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "TutorialSQLiteHelper.h"

NSString * const TutorialSQLiteErrorDomain = @"com.atproto.tutorial.sqlite";

@interface TutorialSQLiteHelper ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) sqlite3 *db;
@end

@implementation TutorialSQLiteHelper

- (nullable instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _databasePath = [path copy];
        _queue = dispatch_queue_create("com.atproto.tutorial.sqlite", DISPATCH_QUEUE_SERIAL);

        int result = sqlite3_open_v2([path UTF8String], &_db,
                                     SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
        if (result != SQLITE_OK) {
            NSLog(@"Failed to open database at %@: %s", path, sqlite3_errmsg(_db));
            sqlite3_close(_db);
            _db = NULL;
            return nil;
        }

        // Enable WAL mode for better concurrent read performance
        char *errMsg = NULL;
        sqlite3_exec(_db, "PRAGMA journal_mode=WAL", NULL, NULL, &errMsg);
        if (errMsg) {
            NSLog(@"WAL mode warning: %s", errMsg);
            sqlite3_free(errMsg);
        }

        // Enable foreign keys
        sqlite3_exec(_db, "PRAGMA foreign_keys=ON", NULL, NULL, &errMsg);
        if (errMsg) {
            NSLog(@"Foreign keys warning: %s", errMsg);
            sqlite3_free(errMsg);
        }
    }
    return self;
}

- (void)dealloc {
    if (_db) {
        sqlite3_close(_db);
    }
}

- (BOOL)executeSync:(NSError **)error
             block:(void (^)(sqlite3 *db))block {
    if (!block) return NO;

    __block BOOL success = YES;
    __block NSError *blockError = nil;
    dispatch_sync(self.queue, ^{
        @try {
            block(self->_db);
        } @catch (NSException *exception) {
            success = NO;
            blockError = [NSError errorWithDomain:TutorialSQLiteErrorDomain
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown error"}];
        }
    });
    if (!success && error) *error = blockError;
    return success;
}

- (nullable id)executeQuery:(NSError **)error
                      block:(id _Nullable (^)(sqlite3 *db))block {
    if (!block) return nil;

    __block id result = nil;
    __block NSError *blockError = nil;
    dispatch_sync(self.queue, ^{
        @try {
            result = block(self->_db);
        } @catch (NSException *exception) {
            blockError = [NSError errorWithDomain:TutorialSQLiteErrorDomain
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown error"}];
        }
    });
    if (!result && blockError && error) *error = blockError;
    return result;
}

- (BOOL)executeUpdate:(NSError **)error
                  sql:(NSString *)sql, ... {
    va_list args;
    va_start(args, sql);
    NSString *formatted = [[NSString alloc] initWithFormat:sql arguments:args];
    va_end(args);

    __block BOOL success = YES;
    __block NSError *blockError = nil;
    dispatch_sync(self.queue, ^{
        char *errMsg = NULL;
        int result = sqlite3_exec(self->_db, [formatted UTF8String], NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            success = NO;
            NSString *message = errMsg ? [NSString stringWithUTF8String:errMsg] : @"Unknown SQL error";
            blockError = [NSError errorWithDomain:TutorialSQLiteErrorDomain
                                            code:result
                                        userInfo:@{NSLocalizedDescriptionKey: message}];
            if (errMsg) sqlite3_free(errMsg);
        }
    });
    if (!success && error) *error = blockError;
    return success;
}

@end
