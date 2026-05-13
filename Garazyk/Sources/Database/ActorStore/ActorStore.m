// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "ActorStore.h"
#import "Core/ATProtoError.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Compat/PDSTypes.h"
#if defined(GNUSTEP)
#import "Auth/PDSOpenSSLKeyManager.h"
#else
#import "Auth/PDSAppleActorKeyManager.h"
#endif
#if !defined(GNUSTEP)
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>
#endif
#import "Database/PDSDatabase.h"
#import "Database/Schema/PDSSchemaManager.h"
#import "Database/Migrations/PDSMigrationManager.h"
#import "Auth/Secp256k1.h"
#import "Security/PDSKeyEnvelope.h"
#import "Debug/GZLogger.h"
#import "PDSActorStoreInternal.h"
#import "PDSActorStore+Account.h"
#import "PDSActorStore+Blob.h"
#import "Auth/CryptoUtils.h"
#import "App/PDSConfiguration.h"
#import <sqlite3.h>

extern void PDSActorStoreLinkAccountCategory(void);
extern void PDSActorStoreLinkBlobCategory(void);

NSString * const PDSActorStoreErrorDomain = @"com.atproto.pds.actorstore";
NSString * const PDSServiceStoreDID = @"__service__";

/// Extracts the base directory path from a database path.
static NSString *PDSActorStoreBaseDirectoryFromDBPath(NSString *dbPath) {
    return [dbPath stringByDeletingLastPathComponent];
}

static inline void PDSActorStoreEnsureCategoryObjectsLinked(void) {
    PDSActorStoreLinkAccountCategory();
    PDSActorStoreLinkBlobCategory();
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"

#if !defined(GNUSTEP)
@interface PDSActorStore () <PDSAppleActorKeyManagerDelegate>
#else
@interface PDSActorStore ()
#endif

- (BOOL)addColumnIfNeeded:(NSString *)tableName column:(NSString *)columnName type:(NSString *)type;

@end

@implementation PDSActorStore

- (nullable sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error {
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2((sqlite3 *)self.database.internalSQLiteHandle, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:PDSActorStoreErrorDomain
                                         code:rc
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @(sqlite3_errmsg((sqlite3 *)self.database.internalSQLiteHandle))
                                     }];
        }
        return NULL;
    }
    return stmt;
}

- (void)finalizeStatement:(sqlite3_stmt *)stmt {
    if (stmt) {
        sqlite3_finalize(stmt);
    }
}

+ (instancetype)storeWithDid:(NSString *)did
                    dbPath:(NSString *)dbPath
                      error:(NSError **)error {
    PDSActorStore *store = [[PDSActorStore alloc] initWithDid:did dbPath:dbPath];
    if (![store openWithError:error]) {
        return nil;
    }
    return store;
}

const void * const kPDSActorStoreQueueKey = &kPDSActorStoreQueueKey;

- (instancetype)initWithDid:(NSString *)did dbPath:(NSString *)dbPath {
    PDSActorStoreEnsureCategoryObjectsLinked();
    self = [super init];
    if (self) {
        _did = [did copy];
        _dbPath = [dbPath copy];
#if defined(GNUSTEP)
        NSString *baseDir = PDSActorStoreBaseDirectoryFromDBPath(dbPath);
        NSString *keystorePath = [[baseDir stringByAppendingPathComponent:@"keys"] copy];
        _keyManager = [[PDSOpenSSLKeyManager alloc] initWithDid:did keystorePath:keystorePath];
#else
        _keyManager = [[PDSAppleActorKeyManager alloc] initWithDid:did];
        if ([_keyManager isKindOfClass:[PDSAppleActorKeyManager class]]) {
            ((PDSAppleActorKeyManager *)_keyManager).delegate = self;
        }
#endif
        _database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
        _open = NO;
        _transactionQueue = dispatch_queue_create("com.atproto.pds.actorstore.transaction", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_transactionQueue, kPDSActorStoreQueueKey, (void *)kPDSActorStoreQueueKey, NULL);
        _blobCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    [self close];
}

#pragma mark - Database Lifecycle

- (BOOL)openWithError:(NSError **)error {
    if (self.open) return YES;
    if (![self.database openWithError:error]) return NO;
    if (![self createSchema:error]) {
        [self.database close];
        return NO;
    }
    self.open = YES;
    return YES;
}

- (BOOL)createSchema:(NSError **)error {
    PDSMigrationManager *migrationManager;
    if ([self.did isEqualToString:PDSServiceStoreDID]) {
        migrationManager = [PDSMigrationManager serviceDatabaseMigrationManager];
    } else {
        migrationManager = [PDSMigrationManager actorStoreMigrationManager];
    }

    NSString *checkMigrationsSQL = @"SELECT name FROM sqlite_master WHERE type='table' AND name='_migrations'";
    NSArray *results = [self.database executeParameterizedQuery:checkMigrationsSQL params:@[] error:nil];
    BOOL hasMigrationsTable = (results.count > 0);

    if (!hasMigrationsTable) {
        NSString *checkTablesSQL = @"SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%%' AND name != '_migrations' LIMIT 1";
        NSArray *tableResults = [self.database executeParameterizedQuery:checkTablesSQL params:@[] error:nil];
        BOOL hasNonMigrationTables = (tableResults.count > 0);

        if (hasNonMigrationTables) {
            NSString *createMigrationsSQL =
                @"CREATE TABLE IF NOT EXISTS _migrations ("
                "version INTEGER PRIMARY KEY, "
                "name TEXT NOT NULL, "
                "applied_at INTEGER NOT NULL DEFAULT (strftime('%%s','now'))"
                ")";
            if (![self.database executeParameterizedUpdate:createMigrationsSQL params:@[] error:error]) return NO;
            GZ_LOG_DB_INFO(@"Bootstrapped _migrations table for existing database");
        }
    }

    return [migrationManager migrateDatabase:(sqlite3 *)self.database.internalSQLiteHandle error:error];
}

- (void)close {
    if (!self.open) return;
    [self.blobCache removeAllObjects];
    [self.database close];
    self.open = NO;
}

#pragma mark - Error Handling

- (NSError *)errorWithSQLiteResult:(int)result message:(NSString *)message {
    return [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                             message:message ?: @"Unknown error"
                            userInfo:@{@"sqlite_code": @(result)}];
}

#pragma mark - Transaction Support

- (void)safeExecuteSync:(void(^)(void))block {
    if (dispatch_get_specific(kPDSActorStoreQueueKey)) {
        block();
    } else {
        dispatch_sync(self.transactionQueue, block);
    }
}

- (void)transactWithBlock:(void (^)(id<PDSActorStoreTransactor> transactor, NSError **error))block
                    error:(NSError **)error {
    [self.database transactWithBlock:^(NSError **localError) {
        block(self, localError);
    } error:error];
}

- (void)readWithBlock:(void (^)(id<PDSActorStoreReader> reader, NSError **error))block
                error:(NSError **)error {
    [self safeExecuteSync:^{
        block(self, error);
    }];
}

#pragma mark - Query Support

- (PDSDatabaseAccount *)accountFromDictionary:(NSDictionary *)dict {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = dict[@"did"];
    account.handle = dict[@"handle"];
    account.email = dict[@"email"];
    account.passwordHash = dict[@"password_hash"];
    account.passwordSalt = dict[@"password_salt"];
    account.accessJwt = dict[@"access_jwt"];
    account.refreshJwt = dict[@"refresh_jwt"];
    account.createdAt = [NSDate dateWithTimeIntervalSince1970:[dict[@"created_at"] doubleValue]].timeIntervalSince1970;
    return account;
}

#pragma mark - Repo Operations

- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT cid, updated_at, rev FROM repo_root ORDER BY updated_at DESC LIMIT 1";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[] error:error];
    if (results.count > 0) {
        NSDictionary *row = results.firstObject;
        PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
        repo.ownerDid = did;
        repo.rootCid = row[@"cid"];
        repo.createdAt = [NSDate date];
        repo.updatedAt = [NSDate dateWithTimeIntervalSince1970:[row[@"updated_at"] doubleValue]];
        return repo;
    }
    return nil;
}

- (nullable NSData *)getRepoRootForDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT cid FROM repo_root ORDER BY updated_at DESC LIMIT 1";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[] error:error];
    if (results.count > 0) return results.firstObject[@"cid"];
    return nil;
}

- (nullable NSString *)getRepoRevisionForDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT rev FROM repo_root ORDER BY updated_at DESC LIMIT 1";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[] error:error];
    if (results.count > 0) return results.firstObject[@"rev"];
    return nil;
}

- (nullable NSString *)latestMutationRevisionWithError:(NSError **)error {
    NSString *sql = @"SELECT rev FROM (SELECT rev FROM records WHERE rev IS NOT NULL UNION ALL SELECT rev FROM record_tombstones) ORDER BY rev DESC LIMIT 1";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[] error:error];
    if (results.count > 0) return results.firstObject[@"rev"];
    return nil;
}

- (BOOL)repoRevisionExists:(NSString *)rev error:(NSError **)error {
    if (rev.length == 0) return NO;
    NSArray *results = [self.database executeParameterizedQuery:@"SELECT 1 FROM repo_root WHERE rev = ? LIMIT 1" params:@[rev] error:error];
    return (results.count > 0);
}

- (BOOL)mutationRevisionExists:(NSString *)rev error:(NSError **)error {
    if (rev.length == 0) return NO;
    NSArray *results = [self.database executeParameterizedQuery:@"SELECT 1 FROM records WHERE rev = ? LIMIT 1" params:@[rev] error:error];
    if (results.count > 0) return YES;
    results = [self.database executeParameterizedQuery:@"SELECT 1 FROM record_tombstones WHERE rev = ? LIMIT 1" params:@[rev] error:error];
    return (results.count > 0);
}

- (BOOL)blockRevisionExists:(NSString *)rev error:(NSError **)error {
    if (rev.length == 0) return NO;
    NSArray *results = [self.database executeParameterizedQuery:@"SELECT 1 FROM ipld_blocks WHERE rev = ? LIMIT 1" params:@[rev] error:error];
    return (results.count > 0);
}

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error {
    NSString *sql = @"INSERT INTO repo_root (cid, rev, updated_at) VALUES (?, ?, ?)";
    return [self.database executeParameterizedUpdate:sql params:@[repo.rootCid ?: [NSNull null], @"", @(repo.updatedAt.timeIntervalSince1970)] error:error];
}

- (BOOL)updateRepoRoot:(NSString *)did rootCid:(NSData *)rootCid error:(NSError **)error {
    return [self updateRepoRoot:did rootCid:rootCid rev:nil error:error];
}

- (BOOL)updateRepoRoot:(NSString *)did rootCid:(NSData *)rootCid rev:(nullable NSString *)rev error:(NSError **)error {
    NSString *resolvedRev = rev ?: [self getRepoRevisionForDid:did error:nil] ?: @"";
    NSString *sql = @"INSERT OR REPLACE INTO repo_root (cid, rev, updated_at) VALUES (?, ?, ?)";
    return [self.database executeParameterizedUpdate:sql params:@[rootCid ?: [NSNull null], resolvedRev, @([[NSDate date] timeIntervalSince1970])] error:error];
}

- (BOOL)clearRepoRootWithError:(NSError **)error {
    return [self.database executeParameterizedUpdate:@"DELETE FROM repo_root" params:@[] error:error];
}

- (BOOL)deleteRepo:(NSString *)did error:(NSError **)error {
    return [self.database executeParameterizedUpdate:@"DELETE FROM repo_root" params:@[] error:error];
}

#pragma mark - Record Operations

- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"SELECT uri, did, collection, rkey, cid, value, created_at, rev, subject_did FROM records WHERE uri = ?";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[uri] error:error];
    if (results.count > 0) return [self recordFromDictionary:results.firstObject];
    return nil;
}

- (NSArray<NSDictionary<NSString *, id> *> *)listRecordTombstonesSinceRev:(nullable NSString *)rev limit:(NSUInteger)limit error:(NSError **)error {
    BOOL hasRev = (rev.length > 0);
    NSString *sql = hasRev ? @"SELECT uri, did, collection, rkey, rev, indexed_at FROM record_tombstones WHERE rev > ? ORDER BY rev LIMIT ?" : @"SELECT uri, did, collection, rkey, rev, indexed_at FROM record_tombstones ORDER BY rev LIMIT ?";
    NSMutableArray *params = [NSMutableArray array];
    if (hasRev) [params addObject:rev];
    [params addObject:@(limit)];
    return [self.database executeParameterizedQuery:sql params:params error:error];
}

- (PDSDatabaseRecord *)recordFromDictionary:(NSDictionary *)row {
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = row[@"uri"] ?: @"";
    record.did = row[@"did"] ?: @"";
    record.collection = row[@"collection"] ?: @"";
    record.rkey = row[@"rkey"] ?: @"";
    record.cid = row[@"cid"];
    record.value = row[@"value"];
    record.createdAt = [NSDate dateWithTimeIntervalSince1970:[row[@"created_at"] doubleValue]];
    record.rev = row[@"rev"];
    record.subjectDid = row[@"subject_did"];
    return record;
}

- (NSArray<PDSDatabaseRecord *> *)listRecordsForDid:(NSString *)did collection:(nullable NSString *)collection limit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError **)error {
    NSMutableArray *params = [NSMutableArray array];
    NSString *sql = collection ? @"SELECT uri, did, collection, rkey, cid, value, created_at, rev, subject_did FROM records WHERE collection = ? ORDER BY rkey LIMIT ? OFFSET ?" : @"SELECT uri, did, collection, rkey, cid, value, created_at, rev, subject_did FROM records ORDER BY rkey LIMIT ? OFFSET ?";
    if (collection) [params addObject:collection];
    [params addObject:@(limit)];
    [params addObject:@(offset)];
    return [self.database executeParameterizedQuery:sql params:params modelClass:[PDSDatabaseRecord class] error:error] ?: @[];
}

- (BOOL)putRecord:(PDSDatabaseRecord *)record forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, value, created_at, rev, subject_did) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
    NSArray *params = @[record.uri ?: @"", did ?: @"", record.collection ?: @"", record.rkey ?: @"", record.cid ?: [NSNull null], record.value ?: [NSNull null], @(record.createdAt.timeIntervalSince1970), record.rev ?: [NSNull null], record.subjectDid ?: [NSNull null]];
    return [self.database executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)createRecord:(PDSDatabaseRecord *)record forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"INSERT INTO records (uri, did, collection, rkey, cid, value, created_at, rev, subject_did) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
    NSArray *params = @[record.uri ?: @"", did ?: @"", record.collection ?: @"", record.rkey ?: @"", record.cid ?: [NSNull null], record.value ?: [NSNull null], @(record.createdAt.timeIntervalSince1970), record.rev ?: [NSNull null], record.subjectDid ?: [NSNull null]];
    return [self.database executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)updateRecord:(PDSDatabaseRecord *)record forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"UPDATE records SET did = ?, collection = ?, rkey = ?, cid = ?, value = ?, created_at = ?, rev = ?, subject_did = ? WHERE uri = ?";
    NSArray *params = @[did ?: @"", record.collection ?: @"", record.rkey ?: @"", record.cid ?: [NSNull null], record.value ?: [NSNull null], @(record.createdAt.timeIntervalSince1970), record.rev ?: [NSNull null], record.subjectDid ?: [NSNull null], record.uri ?: @""];
    return [self.database executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)deleteRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    return [self.database executeParameterizedUpdate:@"DELETE FROM records WHERE uri = ?" params:@[uri] error:error];
}

- (BOOL)addRecordTombstoneURI:(NSString *)uri did:(NSString *)did collection:(NSString *)collection rkey:(NSString *)rkey rev:(NSString *)rev error:(NSError **)error {
    NSString *sql = @"INSERT INTO record_tombstones (uri, did, collection, rkey, rev, indexed_at) VALUES (?, ?, ?, ?, ?, ?)";
    NSArray *params = @[uri ?: @"", did ?: @"", collection ?: @"", rkey ?: @"", rev ?: @"", @([[NSDate date] timeIntervalSince1970])];
    return [self.database executeParameterizedUpdate:sql params:params error:error];
}

- (BOOL)putRecords:(NSArray<PDSDatabaseRecord *> *)records forDid:(NSString *)did error:(NSError **)error {
    return [self.database transactWithBlock:^(NSError **localError) {
        for (PDSDatabaseRecord *record in records) {
            if (![self putRecord:record forDid:did error:localError]) return;
        }
    } error:error];
}

#pragma mark - Block Operations

- (NSArray<NSData *> *)listBlockCIDsSinceRev:(nullable NSString *)rev limit:(NSUInteger)limit error:(NSError **)error {
    BOOL hasRev = (rev.length > 0);
    NSString *sql = hasRev ? @"SELECT cid FROM ipld_blocks WHERE rev > ? ORDER BY rev, cid LIMIT ?" : @"SELECT cid FROM ipld_blocks ORDER BY cid LIMIT ?";
    NSMutableArray *params = [NSMutableArray array];
    if (hasRev) [params addObject:rev];
    [params addObject:@(limit)];
    NSArray *results = [self.database executeParameterizedQuery:sql params:params error:error];
    NSMutableArray *cids = [NSMutableArray arrayWithCapacity:results.count];
    for (NSDictionary *row in results) if (row[@"cid"]) [cids addObject:row[@"cid"]];
    return [cids copy];
}

- (NSArray<NSData *> *)listBlockCIDsForRevision:(NSString *)rev limit:(NSUInteger)limit error:(NSError **)error {
    if (rev.length == 0) return @[];
    NSArray *results = [self.database executeParameterizedQuery:@"SELECT cid FROM ipld_blocks WHERE rev = ? ORDER BY cid LIMIT ?" params:@[rev, @(limit)] error:error];
    NSMutableArray *cids = [NSMutableArray arrayWithCapacity:results.count];
    for (NSDictionary *row in results) if (row[@"cid"]) [cids addObject:row[@"cid"]];
    return [cids copy];
}

- (nullable NSData *)getBlockForCID:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    NSArray *results = [self.database executeParameterizedQuery:@"SELECT block FROM ipld_blocks WHERE cid = ?" params:@[cid] error:error];
    return results.firstObject[@"block"];
}

- (NSArray<PDSDatabaseBlock *> *)listBlocksForDid:(NSString *)did limit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError **)error {
    return [self.database executeParameterizedQuery:@"SELECT cid, block, size, rev FROM ipld_blocks LIMIT ? OFFSET ?" params:@[@(limit), @(offset)] modelClass:[PDSDatabaseBlock class] error:error] ?: @[];
}

- (BOOL)putBlock:(PDSDatabaseBlock *)block forDid:(NSString *)did error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO ipld_blocks (cid, block, size, rev) VALUES (?, ?, ?, ?)";
    return [self.database executeParameterizedUpdate:sql params:@[block.cid ?: [NSNull null], block.blockData ?: [NSNull null], @(block.size), block.rev ?: [NSNull null]] error:error];
}

- (BOOL)putBlocks:(NSArray<PDSDatabaseBlock *> *)blocks forDid:(NSString *)did error:(NSError **)error {
    return [self.database transactWithBlock:^(NSError **localError) {
        for (PDSDatabaseBlock *block in blocks) {
            if (![self putBlock:block forDid:did error:localError]) return;
        }
    } error:error];
}

- (BOOL)deleteBlock:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    return [self.database executeParameterizedUpdate:@"DELETE FROM ipld_blocks WHERE cid = ?" params:@[cid] error:error];
}

#pragma mark - Count Operations

- (NSInteger)getRecordCountForDid:(NSString *)did collection:(nullable NSString *)collection error:(NSError **)error {
    NSString *sql = collection ? @"SELECT COUNT(*) as count FROM records WHERE collection = ?" : @"SELECT COUNT(*) as count FROM records";
    NSArray *params = collection ? @[collection] : @[];
    NSArray *results = [self.database executeParameterizedQuery:sql params:params error:error];
    return [results.firstObject[@"count"] integerValue];
}

- (NSInteger)getBlockCountForDid:(NSString *)did error:(NSError **)error {
    NSArray *results = [self.database executeParameterizedQuery:@"SELECT COUNT(*) as count FROM ipld_blocks" params:@[] error:error];
    return [results.firstObject[@"count"] integerValue];
}

#pragma mark - Signing Key Management

- (BOOL)generateSigningKeyWithError:(NSError **)error {
    return [self generateSigningKeyForDid:self.did error:error];
}

- (BOOL)generateSigningKeyForDid:(NSString *)targetDid error:(NSError **)error {
    if (![targetDid isEqualToString:self.did]) {
#if defined(GNUSTEP)
        NSString *baseDir = PDSActorStoreBaseDirectoryFromDBPath(self.dbPath);
        NSString *keystorePath = [[baseDir stringByAppendingPathComponent:@"keys"] copy];
        id<PDSActorKeyManager> manager = [[PDSOpenSSLKeyManager alloc] initWithDid:targetDid keystorePath:keystorePath];
#else
        id<PDSActorKeyManager> manager = [[PDSAppleActorKeyManager alloc] initWithDid:targetDid];
#endif
        return [manager generateSigningKeyWithError:error];
    }
    return [self.keyManager generateSigningKeyWithError:error];
}

- (BOOL)importSigningKey:(NSData *)privateKey error:(NSError **)error {
    return [self.keyManager importSigningKey:privateKey error:error];
}

- (nullable NSData *)signData:(NSData *)data error:(NSError **)error {
    return [self.keyManager signData:data error:error];
}

- (nullable NSData *)publicSigningKeyWithError:(NSError **)error {
    return [self.keyManager publicSigningKeyWithError:error];
}

- (nullable NSString *)didKeyStringWithError:(NSError **)error {
    return [self.keyManager didKeyStringWithError:error];
}

- (BOOL)storeSigningKey:(NSData *)privateKey publicKey:(NSData *)publicKey error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO signing_keys (did, private_key, public_key_compressed, created_at, updated_at) VALUES (?, ?, ?, ?, ?)";
    double now = [[NSDate date] timeIntervalSince1970];
    return [self.database executeParameterizedUpdate:sql params:@[self.did ?: @"", privateKey ?: [NSNull null], publicKey ?: [NSNull null], @(now), @(now)] error:error];
}

- (nullable NSData *)loadSigningKeyWithError:(NSError **)error {
    NSArray *results = [self.database executeParameterizedQuery:@"SELECT private_key FROM signing_keys WHERE did = ?" params:@[self.did ?: @""] error:error];
    return results.firstObject[@"private_key"];
}

#if !defined(GNUSTEP)
#pragma mark - PDSAppleActorKeyManagerDelegate
- (BOOL)appleActorKeyManager:(PDSAppleActorKeyManager *)manager storeSigningKey:(NSData *)privateKey publicKey:(NSData *)publicKey error:(NSError **)error {
    return [self storeSigningKey:privateKey publicKey:publicKey error:error];
}
- (nullable NSData *)appleActorKeyManagerLoadSigningKey:(PDSAppleActorKeyManager *)manager error:(NSError **)error {
    return [self loadSigningKeyWithError:error];
}
#endif

#pragma mark - Rotation Key Management

- (BOOL)storeRotationKeyPrivate:(NSData *)privateKey publicKey:(NSData *)compressedPublicKey encryptedWithPassword:(NSString *)password error:(NSError **)error {
    if (privateKey.length != 32 || compressedPublicKey.length != 33) return NO;
    uint8_t saltBytes[16];
    if (SecRandomCopyBytes(kSecRandomDefault, 16, saltBytes) != errSecSuccess) return NO;
    NSData *salt = [NSData dataWithBytes:saltBytes length:16];
    NSData *encryptionKey = [self deriveKeyFromPassword:password salt:salt];
    if (!encryptionKey) return NO;
    NSData *encryptedKey = [PDSKeyEnvelope seal:privateKey withKey:encryptionKey error:error];
    if (!encryptedKey) return NO;
    double now = [[NSDate date] timeIntervalSince1970];
    NSString *sql = @"INSERT OR REPLACE INTO rotation_keys (did, encrypted_private_key, public_key_compressed, encryption_salt, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)";
    return [self.database executeParameterizedUpdate:sql params:@[self.did ?: @"", encryptedKey, compressedPublicKey, salt, @(now), @(now)] error:error];
}

- (BOOL)storeRotationKeyPrivate:(NSData *)privateKey publicKey:(NSData *)compressedPublicKey error:(NSError **)error {
    NSString *masterSecret = self.masterSecret ?: [PDSConfiguration sharedConfiguration].masterSecret;
    if (masterSecret.length == 0) return NO;
    return [self storeRotationKeyPrivate:privateKey publicKey:compressedPublicKey encryptedWithPassword:masterSecret error:error];
}

- (nullable NSData *)rotationKeyDecryptedWithPassword:(NSString *)password error:(NSError **)error {
    NSArray *results = [self.database executeParameterizedQuery:@"SELECT encrypted_private_key, encryption_salt FROM rotation_keys WHERE did = ?" params:@[self.did ?: @""] error:error];
    if (results.count == 0) return nil;
    NSDictionary *row = results.firstObject;
    NSData *encryptedKey = row[@"encrypted_private_key"];
    NSData *salt = row[@"encryption_salt"];
    NSData *decryptionKey = [self deriveKeyFromPassword:password salt:salt];
    if (!decryptionKey) return nil;
    if ([PDSKeyEnvelope isVersionedEnvelope:encryptedKey]) return [PDSKeyEnvelope openEnvelope:encryptedKey withKey:decryptionKey error:error];
    return [self decryptData:encryptedKey withKey:decryptionKey];
}

- (nullable NSData *)rotationKeyDecryptedWithError:(NSError **)error {
    NSString *masterSecret = self.masterSecret ?: [PDSConfiguration sharedConfiguration].masterSecret;
    if (masterSecret.length == 0) return nil;
    return [self rotationKeyDecryptedWithPassword:masterSecret error:error];
}

- (nullable NSData *)exportSigningKeyWithError:(NSError **)error {
    return [self.keyManager exportPrivateKeyWithError:error];
}

- (nullable NSData *)rotationKeyCompressedPublicKeyWithError:(NSError **)error {
    NSArray *results = [self.database executeParameterizedQuery:@"SELECT public_key_compressed FROM rotation_keys WHERE did = ?" params:@[self.did ?: @""] error:error];
    return results.firstObject[@"public_key_compressed"];
}

- (BOOL)hasRotationKey {
    NSArray *results = [self.database executeParameterizedQuery:@"SELECT 1 FROM rotation_keys WHERE did = ? LIMIT 1" params:@[self.did ?: @""] error:nil];
    return (results.count > 0);
}

#pragma mark - Encryption Helpers

- (nullable NSData *)deriveKeyFromPassword:(NSString *)password salt:(NSData *)salt { return [CryptoUtils deriveKeyFromPassword:password salt:salt]; }
- (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key { return [CryptoUtils encryptData:data withKey:key]; }
- (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key { return [CryptoUtils decryptData:data withKey:key]; }

static BOOL isValidTableName(NSString *n) { return [@[@"actor_status", @"records", @"blocks", @"blobs", @"migrations", @"account", @"repo", @"cid_index", @"collection_index"] containsObject:n]; }
static BOOL isValidColumnName(NSString *n) { return [@[@"did", @"collection", @"rkey", @"cid", @"value", @"created_at", @"indexed_at", @"takedown_ref", @"blob_data", @"mimeType", @"size", @"height", @"rev", @"handle"] containsObject:n]; }
static BOOL isValidColumnType(NSString *t) { return YES; } // Simplified for now since we whitelist usage

- (BOOL)addColumnIfNeeded:(NSString *)tableName column:(NSString *)columnName type:(NSString *)type {
    if (!isValidTableName(tableName) || !isValidColumnName(columnName)) return NO;
    NSArray *results = [self.database executeParameterizedQuery:@"SELECT name FROM sqlite_master WHERE type='table' AND name=?" params:@[tableName] error:nil];
    if (results.count == 0) return YES;
    NSArray *info = [self.database executeUnsafeRawQuery:[NSString stringWithFormat:@"PRAGMA table_info(%@)", tableName] error:nil];
    for (NSDictionary *row in info) if ([row[@"name"] isEqualToString:columnName]) return YES;
    return [self.database executeUnsafeRawSQL:[NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN %@ %@", tableName, columnName, type] error:nil];
}

@end

#pragma clang diagnostic pop
