#import <Foundation/Foundation.h>
#import "AccountRepository.h"
#import <sqlite3.h>

@interface AccountRepository ()
@property (nonatomic, assign) sqlite3 *database;
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
    
    NSString *dbPath = [path stringByAppendingPathComponent:@"accounts.db"];
    int rc = sqlite3_open([dbPath UTF8String], &_database);
    
    if (rc != SQLITE_OK) {
        NSLog(@"Failed to open database: %s", sqlite3_errmsg(_database));
        return nil;
    }
    
    [self createTablesIfNeeded];
    
    return self;
}

- (void)createTablesIfNeeded {
    const char *sql = "CREATE TABLE IF NOT EXISTS accounts ("
        "did TEXT PRIMARY KEY,"
        "handle TEXT UNIQUE NOT NULL,"
        "email TEXT UNIQUE NOT NULL,"
        "password_hash BLOB NOT NULL,"
        "password_salt BLOB NOT NULL,"
        "access_jwt TEXT,"
        "refresh_jwt TEXT,"
        "created_at REAL NOT NULL"
        ");";
    
    char *errMsg = NULL;
    int rc = sqlite3_exec(_database, sql, NULL, NULL, &errMsg);
    
    if (rc != SQLITE_OK) {
        NSLog(@"Failed to create table: %s", errMsg);
        sqlite3_free(errMsg);
    }
}

- (BOOL)saveAccount:(Account *)account error:(NSError **)error {
    const char *sql = "INSERT OR REPLACE INTO accounts "
        "(did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    sqlite3_bind_text(stmt, 1, [account.did UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [account.handle UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, [account.email UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_blob(stmt, 4, account.passwordHash.bytes, (int)account.passwordHash.length, SQLITE_TRANSIENT);
    sqlite3_bind_blob(stmt, 5, account.passwordSalt.bytes, (int)account.passwordSalt.length, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 6, [account.accessJwt UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 7, [account.refreshJwt UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 8, account.createdAt);
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return NO;
    }
    
    return YES;
}

- (nullable Account *)accountForHandle:(NSString *)handle error:(NSError **)error {
    const char *sql = "SELECT did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at "
        "FROM accounts WHERE handle = ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return nil;
    }
    
    sqlite3_bind_text(stmt, 1, [handle UTF8String], -1, SQLITE_TRANSIENT);
    
    Account *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [[Account alloc] init];
        account.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        account.handle = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        account.email = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, 3) length:sqlite3_column_bytes(stmt, 3)];
        account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 4) length:sqlite3_column_bytes(stmt, 4)];
        account.accessJwt = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 5)];
        account.refreshJwt = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 6)];
        account.createdAt = sqlite3_column_double(stmt, 7);
    }
    
    sqlite3_finalize(stmt);
    return account;
}

- (nullable Account *)accountForEmail:(NSString *)email error:(NSError **)error {
    const char *sql = "SELECT did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at "
        "FROM accounts WHERE email = ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return nil;
    }
    
    sqlite3_bind_text(stmt, 1, [email UTF8String], -1, SQLITE_TRANSIENT);
    
    Account *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [[Account alloc] init];
        account.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        account.handle = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        account.email = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, 3) length:sqlite3_column_bytes(stmt, 3)];
        account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 4) length:sqlite3_column_bytes(stmt, 4)];
        account.accessJwt = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 5)];
        account.refreshJwt = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 6)];
        account.createdAt = sqlite3_column_double(stmt, 7);
    }
    
    sqlite3_finalize(stmt);
    return account;
}

- (nullable Account *)accountForDid:(NSString *)did error:(NSError **)error {
    const char *sql = "SELECT did, handle, email, password_hash, password_salt, access_jwt, refresh_jwt, created_at "
        "FROM accounts WHERE did = ?";
    
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(_database, sql, -1, &stmt, NULL);
    
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"Database" code:rc userInfo:nil];
        }
        return nil;
    }
    
    sqlite3_bind_text(stmt, 1, [did UTF8String], -1, SQLITE_TRANSIENT);
    
    Account *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [[Account alloc] init];
        account.did = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
        account.handle = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        account.email = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, 3) length:sqlite3_column_bytes(stmt, 3)];
        account.passwordSalt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 4) length:sqlite3_column_bytes(stmt, 4)];
        account.accessJwt = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 5)];
        account.refreshJwt = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 6)];
        account.createdAt = sqlite3_column_double(stmt, 7);
    }
    
    sqlite3_finalize(stmt);
    return account;
}

- (void)dealloc {
    if (_database) {
        sqlite3_close(_database);
    }
}

@end
