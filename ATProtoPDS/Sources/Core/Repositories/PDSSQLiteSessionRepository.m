#import "PDSSQLiteSessionRepository.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import <sqlite3.h>

@implementation PDSSQLiteSessionRepository {
    PDSDatabasePool *_servicePool;
}

- (instancetype)initWithServicePool:(PDSDatabasePool *)servicePool {
    self = [super init];
    if (self) {
        _servicePool = servicePool;
    }
    return self;
}

#pragma mark - PDSSessionRepository

- (BOOL)storeRefreshToken:(NSString *)refreshToken forAccountDid:(NSString *)did error:(NSError **)error {
    __block BOOL success = NO;
    [_servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"INSERT INTO refresh_tokens (token, account_did, created_at) VALUES (?, ?, ?)";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, refreshToken.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 3, [NSDate date].timeIntervalSince1970);

        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        }
        [store finalizeStatement:stmt];
    } error:error];
    return success;
}

- (nullable NSString *)accountDidForRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    __block NSString *did = nil;
    [_servicePool readWithDid:@"__service__" block:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)reader;
        NSString *sql = @"SELECT account_did FROM refresh_tokens WHERE token = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, refreshToken.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *didStr = (const char *)sqlite3_column_text(stmt, 0);
            if (didStr) {
                did = [NSString stringWithUTF8String:didStr];
            }
        }
        [store finalizeStatement:stmt];
    } error:error];
    return did;
}

- (BOOL)revokeRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    __block BOOL success = NO;
    [_servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"DELETE FROM refresh_tokens WHERE token = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, refreshToken.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        }
        [store finalizeStatement:stmt];
    } error:error];
    return success;
}

- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)did error:(NSError **)error {
    __block BOOL success = NO;
    [_servicePool transactWithDid:@"__service__" block:^(id<PDSActorStoreTransactor> transactor, NSError **blockError) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        NSString *sql = @"DELETE FROM refresh_tokens WHERE account_did = ?";
        sqlite3_stmt *stmt = [store prepareStatement:sql error:blockError];
        if (!stmt) return;

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        }
        [store finalizeStatement:stmt];
    } error:error];
    return success;
}

@end
