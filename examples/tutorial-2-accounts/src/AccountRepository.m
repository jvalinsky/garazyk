#import <Foundation/Foundation.h>
#import "AccountRepository.h"
#import "Account.h"
#import "TutorialSQLiteHelper.h"

@interface AccountRepository ()
@property (nonatomic, strong) TutorialSQLiteHelper *db;
@end

@implementation AccountRepository

- (instancetype)initWithDatabasePath:(NSString *)path {
    self = [super init];
    if (!self) return nil;

    // Create directory if needed
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSString *parentDir = [path stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:parentDir]) {
        [fm createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSString *dbPath = [path stringByAppendingPathComponent:@"accounts.db"];
    _db = [[TutorialSQLiteHelper alloc] initWithPath:dbPath];
    if (!_db) return nil;

    [self createTablesIfNeeded];
    return self;
}

- (void)createTablesIfNeeded {
    NSError *error = nil;
    [self.db executeUpdate:&error sql:@"CREATE TABLE IF NOT EXISTS accounts ("
        @"did TEXT PRIMARY KEY, "
        @"handle TEXT UNIQUE NOT NULL, "
        @"email TEXT UNIQUE NOT NULL, "
        @"password_hash BLOB NOT NULL, "
        @"password_salt BLOB NOT NULL, "
        @"access_jwt TEXT, "
        @"refresh_jwt TEXT, "
        @"created_at REAL NOT NULL"
        @")"];
    if (error) {
        NSLog(@"Warning: table creation error: %@", error.localizedDescription);
    }
}

- (BOOL)saveAccount:(Account *)account error:(NSError **)error {
    __block NSError *blockError = nil;
    [self.db executeSync:&blockError block:^(sqlite3 *db) {
        const char *sql = "INSERT OR REPLACE INTO accounts "
            "(did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
            return;
        }

        sqlite3_bind_text(stmt, 1, [account.did UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [account.handle UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, [account.email UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 4, account.passwordHash.bytes, (int)account.passwordHash.length, SQLITE_TRANSIENT);
        sqlite3_bind_blob(stmt, 5, account.passwordSalt.bytes, (int)account.passwordSalt.length, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 6, [account.accessJwt UTF8String] ?: "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 7, [account.refreshJwt UTF8String] ?: "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 8, account.createdAt);

        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        if (rc != SQLITE_DONE) {
            blockError = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
    }];
    if (blockError) {
        if (error) *error = blockError;
        return NO;
    }
    return YES;
}

- (nullable Account *)accountForHandle:(NSString *)handle error:(NSError **)error {
    return [self accountWhere:@"handle" equals:handle error:error];
}

- (nullable Account *)accountForEmail:(NSString *)email error:(NSError **)error {
    return [self accountWhere:@"email" equals:email error:error];
}

- (nullable Account *)accountForDid:(NSString *)did error:(NSError **)error {
    return [self accountWhere:@"did" equals:did error:error];
}

#pragma mark - Private

- (nullable Account *)accountWhere:(NSString *)column equals:(NSString *)value error:(NSError **)error {
    __block NSError *blockError = nil;
    Account *result = [self.db executeQuery:&blockError block:^id _Nullable(sqlite3 *db) {
        NSString *sql = [NSString stringWithFormat:
            @"SELECT did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at "
            @"FROM accounts WHERE %@ = ?", column];
        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(db, [sql UTF8String], -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            blockError = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
            return nil;
        }

        sqlite3_bind_text(stmt, 1, [value UTF8String], -1, SQLITE_TRANSIENT);

        Account *account = nil;
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            account = [self accountFromStatement:stmt];
        }

        sqlite3_finalize(stmt);
        return account;
    }];
    if (!result && blockError && error) *error = blockError;
    return result;
}

- (Account *)accountFromStatement:(sqlite3_stmt *)stmt {
    Account *account = [[Account alloc] init];
    account.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
    account.handle = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
    account.email = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
    account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, 3)
                                          length:sqlite3_column_bytes(stmt, 3)];
    account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 4)
                                          length:sqlite3_column_bytes(stmt, 4)];
    const char *accessJwt = (const char *)sqlite3_column_text(stmt, 5);
    account.accessJwt = accessJwt ? [NSString stringWithUTF8String:accessJwt] : nil;
    const char *refreshJwt = (const char *)sqlite3_column_text(stmt, 6);
    account.refreshJwt = refreshJwt ? [NSString stringWithUTF8String:refreshJwt] : nil;
    account.createdAt = sqlite3_column_double(stmt, 7);
    return account;
}

@end
