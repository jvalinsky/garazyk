#import "PDSDatabase.h"
#import "Schema.h"

NSString * const PDSDatabaseErrorDomain = @"com.atproto.pds.database";

static NSDateFormatter * _iso8601Formatter(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
        [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    });
    return formatter;
}

@interface PDSDatabase ()

@property (nonatomic, readwrite) NSURL *databaseURL;
@property (nonatomic, readwrite) BOOL isOpen;
@property (nonatomic, assign) sqlite3 *db;

@end

@implementation PDSDatabase

+ (instancetype)databaseAtURL:(NSURL *)url {
    PDSDatabase *database = [[PDSDatabase alloc] init];
    database.databaseURL = url;
    database.isOpen = NO;
    database.db = NULL;
    return database;
}

- (BOOL)openWithError:(NSError **)error {
    if (self.isOpen) {
        return YES;
    }

    int rc = sqlite3_open(self.databaseURL.path.fileSystemRepresentation, &_db);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorNotOpen
                                     userInfo:@{NSLocalizedDescriptionKey: @(sqlite3_errmsg(_db))}];
        }
        return NO;
    }

    [self setWalMode:error];
    [self createSchema:error];

    self.isOpen = (rc == SQLITE_OK);
    return self.isOpen;
}

- (void)close {
    if (!self.isOpen) return;
    sqlite3_close(_db);
    _db = NULL;
    self.isOpen = NO;
}

- (void)dealloc {
    [self close];
}

- (BOOL)setWalMode:(NSError **)error {
    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, "PRAGMA journal_mode=WAL", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorQueryFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @(errMsg)}];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }
    return YES;
}

- (BOOL)createSchema:(NSError **)error {
    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, [kPDSAccountTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSRepoTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSBlockTableCreateSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSIndexBlocksRepoDidSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    rc = sqlite3_exec(_db, [kPDSIndexAccountsHandleSQL UTF8String], NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorMigrationFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    return YES;
}

- (BOOL)executeRawSQL:(NSString *)sql error:(NSError **)error {
    if (!self.isOpen) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorNotOpen
                                     userInfo:@{NSLocalizedDescriptionKey:@"Database is not open"}];
        }
        return NO;
    }

    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, sql.UTF8String, NULL, NULL, &errMsg);

    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }

    return YES;
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql error:(NSError **)error {
    if (!self.isOpen) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorNotOpen
                                     userInfo:@{NSLocalizedDescriptionKey:@"Database is not open"}];
        }
        return @[];
    }

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);

    if (rc != SQLITE_OK) {
        if (error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        }
        return @[];
    }

    NSMutableArray *results = [NSMutableArray array];
    int columnCount = sqlite3_column_count(stmt);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        for (int i = 0; i < columnCount; i++) {
            NSString *columnName = @(sqlite3_column_name(stmt, i));
            id value = [self valueFromStatement:stmt columnIndex:i];
            if (value) {
                row[columnName] = value;
            }
        }
        [results addObject:row];
    }

    sqlite3_finalize(stmt);
    return results;
}

- (id)valueFromStatement:(sqlite3_stmt *)stmt columnIndex:(int)colIndex {
    int type = sqlite3_column_type(stmt, colIndex);
    switch (type) {
        case SQLITE_INTEGER:
            return @(sqlite3_column_int64(stmt, colIndex));
        case SQLITE_FLOAT:
            return @(sqlite3_column_double(stmt, colIndex));
        case SQLITE_BLOB: {
            const void *bytes = sqlite3_column_blob(stmt, colIndex);
            int size = sqlite3_column_bytes(stmt, colIndex);
            return [NSData dataWithBytes:bytes length:size];
        }
        case SQLITE_TEXT: {
            const unsigned char *text = sqlite3_column_text(stmt, colIndex);
            return @((const char *)text);
        }
        case SQLITE_NULL:
        default:
            return nil;
    }
}

- (NSError *)errorWithMessage:(const char *)message code:(NSInteger)code {
    NSString *msg = message ? @(message) : @"Unknown error";
    return [NSError errorWithDomain:PDSDatabaseErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: msg}];
}

#pragma mark - Accounts

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    NSString *sql = @"INSERT INTO accounts (did, handle, email, password_hash, access_jwt, refresh_jwt, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    sqlite3_bind_text(stmt, 1, account.did.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, account.handle.UTF8String, -1, SQLITE_STATIC);
    if (account.email) {
        sqlite3_bind_text(stmt, 3, account.email.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    [self bindData:account.passwordHash toStatement:stmt index:4];
    [self bindData:account.accessJwt toStatement:stmt index:5];
    [self bindData:account.refreshJwt toStatement:stmt index:6];
    sqlite3_bind_text(stmt, 7, [self iso8601StringFromDate:account.createdAt].UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 8, [self iso8601StringFromDate:account.updatedAt].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        return NO;
    }

    return YES;
}

- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error {
    NSString *sql = @"UPDATE accounts SET handle = ?, email = ?, password_hash = ?, access_jwt = ?, refresh_jwt = ?, updated_at = ? WHERE did = ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    sqlite3_bind_text(stmt, 1, account.handle.UTF8String, -1, SQLITE_STATIC);
    if (account.email) {
        sqlite3_bind_text(stmt, 2, account.email.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 2);
    }
    [self bindData:account.passwordHash toStatement:stmt index:3];
    [self bindData:account.accessJwt toStatement:stmt index:4];
    [self bindData:account.refreshJwt toStatement:stmt index:5];
    sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:account.updatedAt].UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 7, account.did.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        return NO;
    }

    return YES;
}

- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT * FROM accounts WHERE did = ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return nil;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [self accountFromStatement:stmt];
    }

    sqlite3_finalize(stmt);
    return account;
}

- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error {
    NSString *sql = @"SELECT * FROM accounts WHERE handle = ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return nil;
    }

    sqlite3_bind_text(stmt, 1, handle.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseAccount *account = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        account = [self accountFromStatement:stmt];
    }

    sqlite3_finalize(stmt);
    return account;
}

- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error {
    NSString *sql = @"SELECT * FROM accounts ORDER BY created_at DESC";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return @[];
    }

    NSMutableArray *accounts = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseAccount *account = [self accountFromStatement:stmt];
        if (account) {
            [accounts addObject:account];
        }
    }

    sqlite3_finalize(stmt);
    return accounts;
}

- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error {
    NSString *sql = @"DELETE FROM accounts WHERE did = ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    return YES;
}

- (PDSDatabaseAccount *)accountFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @((const char *)sqlite3_column_text(stmt, 0));
    account.handle = @((const char *)sqlite3_column_text(stmt, 1));
    
    const char *emailText = (const char *)sqlite3_column_text(stmt, 2);
    if (emailText) {
        account.email = @(emailText);
    }
    
    int blobBytes = sqlite3_column_bytes(stmt, 3);
    if (blobBytes > 0) {
        account.passwordHash = [NSData dataWithBytes:sqlite3_column_blob(stmt, 3) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 4);
    if (blobBytes > 0) {
        account.accessJwt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 4) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 5);
    if (blobBytes > 0) {
        account.refreshJwt = [NSData dataWithBytes:sqlite3_column_blob(stmt, 5) length:blobBytes];
    }
    
    account.createdAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 6))];
    account.updatedAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 7))];
    
    return account;
}

#pragma mark - Repos

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error {
    NSString *sql = @"INSERT INTO repos (owner_did, root_cid, collection_data, created_at, updated_at) VALUES (?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    sqlite3_bind_text(stmt, 1, repo.ownerDid.UTF8String, -1, SQLITE_STATIC);
    [self bindData:repo.rootCid toStatement:stmt index:2];
    [self bindData:repo.collectionData toStatement:stmt index:3];
    sqlite3_bind_text(stmt, 4, [self iso8601StringFromDate:repo.createdAt].UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 5, [self iso8601StringFromDate:repo.updatedAt].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        return NO;
    }

    return YES;
}

- (BOOL)updateRepoRoot:(NSString *)ownerDid rootCid:(NSData *)rootCid error:(NSError **)error {
    NSString *sql = @"UPDATE repos SET root_cid = ?, updated_at = ? WHERE owner_did = ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    [self bindData:rootCid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, [self iso8601StringFromDate:[NSDate date]].UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, ownerDid.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        }
        return NO;
    }

    return YES;
}

- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT * FROM repos WHERE owner_did = ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return nil;
    }

    sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseRepo *repo = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        repo = [self repoFromStatement:stmt];
    }

    sqlite3_finalize(stmt);
    return repo;
}

- (NSArray<PDSDatabaseRepo *> *)getAllReposWithError:(NSError **)error {
    NSString *sql = @"SELECT * FROM repos ORDER BY updated_at DESC";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return @[];
    }

    NSMutableArray *repos = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseRepo *repo = [self repoFromStatement:stmt];
        if (repo) {
            [repos addObject:repo];
        }
    }

    sqlite3_finalize(stmt);
    return repos;
}

- (BOOL)deleteRepo:(NSString *)ownerDid error:(NSError **)error {
    NSString *sql = @"DELETE FROM repos WHERE owner_did = ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    sqlite3_bind_text(stmt, 1, ownerDid.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    return YES;
}

- (PDSDatabaseRepo *)repoFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = @((const char *)sqlite3_column_text(stmt, 0));
    
    int blobBytes = sqlite3_column_bytes(stmt, 1);
    if (blobBytes > 0) {
        repo.rootCid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 1) length:blobBytes];
    }
    
    blobBytes = sqlite3_column_bytes(stmt, 2);
    if (blobBytes > 0) {
        repo.collectionData = [NSData dataWithBytes:sqlite3_column_blob(stmt, 2) length:blobBytes];
    }
    
    repo.createdAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 3))];
    repo.updatedAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 4))];
    
    return repo;
}

#pragma mark - Blocks

- (BOOL)saveBlock:(PDSDatabaseBlock *)block error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, content_type, size, created_at) VALUES (?, ?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    [self bindData:block.cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, block.repoDid.UTF8String, -1, SQLITE_STATIC);
    [self bindData:block.blockData toStatement:stmt index:3];
    if (block.contentType) {
        sqlite3_bind_text(stmt, 4, block.contentType.UTF8String, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    sqlite3_bind_int64(stmt, 5, block.size);
    sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:block.createdAt].UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        if (error) {
            NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
            *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
        }
        return NO;
    }

    return YES;
}

- (BOOL)saveBlocks:(NSArray<PDSDatabaseBlock *> *)blocks error:(NSError **)error {
    if (blocks.count == 0) {
        return YES;
    }

    NSString *sql = @"INSERT OR REPLACE INTO blocks (cid, repo_did, block_data, content_type, size, created_at) VALUES (?, ?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    for (PDSDatabaseBlock *block in blocks) {
        [self bindData:block.cid toStatement:stmt index:1];
        sqlite3_bind_text(stmt, 2, block.repoDid.UTF8String, -1, SQLITE_STATIC);
        [self bindData:block.blockData toStatement:stmt index:3];
        if (block.contentType) {
            sqlite3_bind_text(stmt, 4, block.contentType.UTF8String, -1, SQLITE_STATIC);
        } else {
            sqlite3_bind_null(stmt, 4);
        }
        sqlite3_bind_int64(stmt, 5, block.size);
        sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:block.createdAt].UTF8String, -1, SQLITE_STATIC);

        rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE) {
            sqlite3_finalize(stmt);
            if (error) {
                NSInteger errorCode = (rc == SQLITE_CONSTRAINT) ? PDSDatabaseErrorConstraintViolation : PDSDatabaseErrorQueryFailed;
                *error = [self errorWithMessage:sqlite3_errmsg(_db) code:errorCode];
            }
            return NO;
        }

        sqlite3_reset(stmt);
    }

    sqlite3_finalize(stmt);
    return YES;
}

- (nullable PDSDatabaseBlock *)getBlockWithCid:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    NSString *sql = @"SELECT * FROM blocks WHERE cid = ? AND repo_did = ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return nil;
    }

    [self bindData:cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, repoDid.UTF8String, -1, SQLITE_STATIC);

    PDSDatabaseBlock *block = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        block = [self blockFromStatement:stmt];
    }

    sqlite3_finalize(stmt);
    return block;
}

- (NSArray<PDSDatabaseBlock *> *)getBlocksForRepo:(NSString *)repoDid limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error {
    NSString *sql = @"SELECT * FROM blocks WHERE repo_did = ? ORDER BY created_at ASC LIMIT ? OFFSET ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return @[];
    }

    sqlite3_bind_text(stmt, 1, repoDid.UTF8String, -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 2, limit);
    sqlite3_bind_int64(stmt, 3, offset);

    NSMutableArray *blocks = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        PDSDatabaseBlock *block = [self blockFromStatement:stmt];
        if (block) {
            [blocks addObject:block];
        }
    }

    sqlite3_finalize(stmt);
    return blocks;
}

- (NSInteger)getBlockCountForRepo:(NSString *)repoDid error:(NSError **)error {
    NSString *sql = @"SELECT COUNT(*) FROM blocks WHERE repo_did = ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return 0;
    }

    sqlite3_bind_text(stmt, 1, repoDid.UTF8String, -1, SQLITE_STATIC);

    NSInteger count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int64(stmt, 0);
    }

    sqlite3_finalize(stmt);
    return count;
}

- (BOOL)deleteBlock:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error {
    NSString *sql = @"DELETE FROM blocks WHERE cid = ? AND repo_did = ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    [self bindData:cid toStatement:stmt index:1];
    sqlite3_bind_text(stmt, 2, repoDid.UTF8String, -1, SQLITE_STATIC);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(_db) code:PDSDatabaseErrorQueryFailed];
        return NO;
    }

    return YES;
}

- (PDSDatabaseBlock *)blockFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    
    int blobBytes = sqlite3_column_bytes(stmt, 0);
    if (blobBytes > 0) {
        block.cid = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) length:blobBytes];
    }
    
    block.repoDid = @((const char *)sqlite3_column_text(stmt, 1));
    
    blobBytes = sqlite3_column_bytes(stmt, 2);
    if (blobBytes > 0) {
        block.blockData = [NSData dataWithBytes:sqlite3_column_blob(stmt, 2) length:blobBytes];
    }
    
    const char *contentTypeText = (const char *)sqlite3_column_text(stmt, 3);
    if (contentTypeText) {
        block.contentType = @(contentTypeText);
    }
    
    block.size = sqlite3_column_int64(stmt, 4);
    block.createdAt = [self dateFromISO8601String:@((const char *)sqlite3_column_text(stmt, 5))];
    
    return block;
}

#pragma mark - Transactions

- (BOOL)beginTransactionWithError:(NSError **)error {
    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, "BEGIN TRANSACTION", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }
    return YES;
}

- (BOOL)commitTransactionWithError:(NSError **)error {
    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, "COMMIT", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }
    return YES;
}

- (BOOL)rollbackTransactionWithError:(NSError **)error {
    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, "ROLLBACK", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK) {
        NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
        sqlite3_free(errMsg);
        if (error) *error = e;
        return NO;
    }
    return YES;
}

#pragma mark - Helpers

- (void)bindData:(nullable NSData *)data toStatement:(sqlite3_stmt *)stmt index:(int)index {
    if (data && data.length > 0) {
        sqlite3_bind_blob(stmt, index, data.bytes, (int)data.length, SQLITE_STATIC);
    } else {
        sqlite3_bind_null(stmt, index);
    }
}

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    return [_iso8601Formatter() stringFromDate:date];
}

- (NSDate *)dateFromISO8601String:(NSString *)string {
    return [_iso8601Formatter() dateFromString:string];
}

@end
