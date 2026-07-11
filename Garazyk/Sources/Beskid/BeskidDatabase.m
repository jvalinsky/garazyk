// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Beskid/BeskidDatabase.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Database/Connection/ATProtoConnectionManagerPooled.h"
#import "Database/Pool/ATProtoConnectionPool.h"
#import "Database/Utils/ATProtoDatabaseQueryRunner.h"
#import "Debug/GZLogger.h"

#import <sqlite3.h>

NSString * const BeskidDatabaseErrorDomain = @"blue.microcosm.beskid.database";

static NSString *BeskidNow(void) {
    return [NSDateFormatter atproto_stringFromDate:[NSDate date]];
}

@interface BeskidDatabase () {
    dispatch_queue_t _writeQueue;
}
@property (nonatomic, strong) ATProtoConnectionPool *pool;
@property (nonatomic, strong) ATProtoConnectionManagerPooled *connectionManager;
@property (nonatomic, strong) ATProtoDatabaseQueryRunner *queryRunner;
@end

@implementation BeskidDatabase

- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error {
    self = [super init];
    if (!self) return nil;

    if (path.length == 0) {
        if (error) *error = [NSError errorWithDomain:BeskidDatabaseErrorDomain
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Database path is required"}];
        return nil;
    }

    if (![path isEqualToString:@":memory:"]) {
        NSString *directory = [path stringByDeletingLastPathComponent];
        if (directory.length > 0) {
            NSError *mkdirError = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&mkdirError]) {
                if (error) *error = mkdirError;
                return nil;
            }
        }
    }

    _writeQueue = dispatch_queue_create("blue.microcosm.beskid.writer", DISPATCH_QUEUE_SERIAL);
    _pool = [[ATProtoConnectionPool alloc] initWithPath:path];
    if (!_pool) {
        if (error) *error = [NSError errorWithDomain:BeskidDatabaseErrorDomain
                                                code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to create connection pool"}];
        return nil;
    }

    _connectionManager = [[ATProtoConnectionManagerPooled alloc] initWithPool:_pool];
    _queryRunner = [[ATProtoDatabaseQueryRunner alloc] initWithConnectionManager:_connectionManager
                                                                     errorDomain:BeskidDatabaseErrorDomain];
    return self;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    [self.pool closeAllConnections];
}

- (BOOL)runMigrations:(NSError **)error {
    static NSString * const schema =
        @"CREATE TABLE IF NOT EXISTS beskid_records ("
        "  uri TEXT PRIMARY KEY,"
        "  did TEXT NOT NULL,"
        "  collection TEXT NOT NULL,"
        "  rkey TEXT NOT NULL,"
        "  cid TEXT NOT NULL,"
        "  value_json TEXT NOT NULL,"
        "  indexed_at INTEGER NOT NULL,"
        "  expires_at INTEGER NOT NULL,"
        "  UNIQUE(did, collection, rkey)"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_beskid_records_did_collection ON beskid_records(did, collection);"
        "CREATE TABLE IF NOT EXISTS beskid_identities ("
        "  did TEXT PRIMARY KEY,"
        "  handle TEXT NOT NULL,"
        "  pds_endpoint TEXT NOT NULL,"
        "  signing_key TEXT NOT NULL,"
        "  raw_doc_json TEXT NOT NULL,"
        "  indexed_at INTEGER NOT NULL,"
        "  expires_at INTEGER NOT NULL"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_beskid_identities_handle ON beskid_identities(handle);";

    __block BOOL migrated = NO;
    __block NSError *innerError = nil;
    dispatch_sync(_writeQueue, ^{
        [self.connectionManager execute:^(sqlite3 *db) {
            char *errmsg = NULL;
            int rc = sqlite3_exec(db, schema.UTF8String, NULL, NULL, &errmsg);
            if (rc != SQLITE_OK) {
                NSString *message = errmsg ? [NSString stringWithUTF8String:errmsg] : @"Migration failed";
                innerError = [NSError errorWithDomain:BeskidDatabaseErrorDomain
                                                 code:rc
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
                if (errmsg) sqlite3_free(errmsg);
                return;
            }
            migrated = YES;
        } error:&innerError];
    });

    if (!migrated && error) *error = innerError;
    return migrated;
}

#pragma mark - Record Cache Operations

- (nullable NSDictionary *)recordByURI:(NSString *)uri
                                   cid:(nullable NSString *)cid
                                 error:(NSError **)error {
    int64_t now = (int64_t)[[NSDate date] timeIntervalSince1970];
    NSString *sql = @"SELECT uri, cid, value_json, expires_at FROM beskid_records WHERE uri = ? LIMIT 1";
    NSArray<NSDictionary *> *rows = [self executeQuery:sql params:@[uri ?: @""] error:error];
    if (!rows || rows.count == 0) {
        if (error) *error = [NSError errorWithDomain:BeskidDatabaseErrorDomain
                                                code:404
                                            userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        return nil;
    }

    NSDictionary *row = rows.firstObject;
    int64_t expiresAt = [row[@"expires_at"] longLongValue];
    if (now >= expiresAt) {
        if (error) *error = [NSError errorWithDomain:BeskidDatabaseErrorDomain
                                                code:410
                                            userInfo:@{NSLocalizedDescriptionKey: @"Record cache has expired"}];
        return nil;
    }

    NSString *storedCID = row[@"cid"];
    if (cid && storedCID && ![cid isEqualToString:storedCID]) {
        if (error) *error = [NSError errorWithDomain:BeskidDatabaseErrorDomain
                                                code:404
                                            userInfo:@{NSLocalizedDescriptionKey: @"CID mismatch"}];
        return nil;
    }

    NSDictionary *value = @{};
    NSString *json = row[@"value_json"];
    if ([json isKindOfClass:[NSString class]] && json.length > 0) {
        id parsed = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
                                                    options:0
                                                      error:nil];
        if ([parsed isKindOfClass:[NSDictionary class]]) value = parsed;
    }

    NSMutableDictionary *result = [@{@"uri": row[@"uri"] ?: uri, @"value": value} mutableCopy];
    if (storedCID.length > 0) result[@"cid"] = storedCID;
    return [result copy];
}

- (BOOL)saveRecord:(NSDictionary *)record
               did:(NSString *)did
        collection:(NSString *)collection
              rkey:(NSString *)rkey
               cid:(NSString *)cid
               ttl:(NSTimeInterval)ttl
             error:(NSError **)error {
    if (!record || did.length == 0 || collection.length == 0 || rkey.length == 0 || cid.length == 0) {
        if (error) *error = [NSError errorWithDomain:BeskidDatabaseErrorDomain
                                                code:400
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid parameter values"}];
        return NO;
    }

    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:record options:0 error:&jsonError];
    if (!jsonData) {
        if (error) *error = jsonError;
        return NO;
    }
    NSString *valueJson = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    int64_t now = (int64_t)[[NSDate date] timeIntervalSince1970];
    int64_t expiresAt = now + (int64_t)ttl;

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];

    __block BOOL success = NO;
    __block NSError *localError = nil;
    dispatch_sync(_writeQueue, ^{
        success = [self performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
            // Delete old record mapping to satisfy unique constraint of did/collection/rkey if URI is changing
            [tx executeUpdate:@"DELETE FROM beskid_records WHERE did = ? AND collection = ? AND rkey = ?"
                       params:@[did, collection, rkey]
                        error:nil];

            NSString *sql = @"INSERT OR REPLACE INTO beskid_records(uri, did, collection, rkey, cid, value_json, indexed_at, expires_at) VALUES(?,?,?,?,?,?,?,?)";
            return [tx executeUpdate:sql
                              params:@[uri, did, collection, rkey, cid, valueJson, @(now), @(expiresAt)]
                               error:innerError];
        } error:&localError];
    });

    if (!success && error) *error = localError;
    return success;
}

- (BOOL)deleteRecordForDID:(NSString *)did
                collection:(NSString *)collection
                      rkey:(NSString *)rkey
                     error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *localError = nil;
    dispatch_sync(_writeQueue, ^{
        success = [self performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
            NSString *sql = @"DELETE FROM beskid_records WHERE did = ? AND collection = ? AND rkey = ?";
            return [tx executeUpdate:sql params:@[did, collection, rkey] error:innerError];
        } error:&localError];
    });
    if (!success && error) *error = localError;
    return success;
}

#pragma mark - Identity Cache Operations

- (BOOL)saveHandle:(NSString *)handle did:(NSString *)did error:(NSError **)error {
    if (handle.length == 0 || did.length == 0) return YES;
    NSString *normalized = [handle lowercaseString];
    int64_t now = (int64_t)[[NSDate date] timeIntervalSince1970];
    int64_t expiresAt = now + 86400; // Default handle map TTL 24h

    __block BOOL success = NO;
    __block NSError *localError = nil;
    dispatch_sync(_writeQueue, ^{
        success = [self performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
            NSString *pds = @"";
            NSString *key = @"";
            NSString *doc = @"{}";
            
            // Preserve any existing identity fields for this DID — this is a handle-only
            // upsert, so read the current row (within the transaction) and carry its values.
            NSArray<NSDictionary *> *existing =
                [tx executeQuery:@"SELECT pds_endpoint, signing_key, raw_doc_json FROM beskid_identities WHERE did = ? LIMIT 1"
                          params:@[did]
                           error:NULL];
            if (existing.count > 0) {
                NSDictionary *row = existing.firstObject;
                if ([row[@"pds_endpoint"] isKindOfClass:[NSString class]]) pds = row[@"pds_endpoint"];
                if ([row[@"signing_key"] isKindOfClass:[NSString class]]) key = row[@"signing_key"];
                if ([row[@"raw_doc_json"] isKindOfClass:[NSString class]]) doc = row[@"raw_doc_json"];
            }

            // Delete standard mappings
            [tx executeUpdate:@"DELETE FROM beskid_identities WHERE handle = ? OR did = ?"
                       params:@[normalized, did]
                        error:nil];

            NSString *sql = @"INSERT OR REPLACE INTO beskid_identities(did, handle, pds_endpoint, signing_key, raw_doc_json, indexed_at, expires_at) VALUES(?,?,?,?,?,?,?)";
            return [tx executeUpdate:sql
                              params:@[did, normalized, pds, key, doc, @(now), @(expiresAt)]
                               error:innerError];
        } error:&localError];
    });
    if (!success && error) *error = localError;
    return success;
}

- (nullable NSString *)resolveHandleToDID:(NSString *)handle error:(NSError **)error {
    int64_t now = (int64_t)[[NSDate date] timeIntervalSince1970];
    NSString *sql = @"SELECT did, expires_at FROM beskid_identities WHERE handle = ? LIMIT 1";
    NSArray<NSDictionary *> *rows = [self executeQuery:sql params:@[[handle lowercaseString] ?: @""] error:error];
    if (!rows || rows.count == 0) return nil;

    NSDictionary *row = rows.firstObject;
    int64_t expiresAt = [row[@"expires_at"] longLongValue];
    if (now >= expiresAt) return nil;

    return row[@"did"];
}

- (nullable NSString *)resolveDIDToHandle:(NSString *)did error:(NSError **)error {
    int64_t now = (int64_t)[[NSDate date] timeIntervalSince1970];
    NSString *sql = @"SELECT handle, expires_at FROM beskid_identities WHERE did = ? LIMIT 1";
    NSArray<NSDictionary *> *rows = [self executeQuery:sql params:@[did ?: @""] error:error];
    if (!rows || rows.count == 0) return nil;

    NSDictionary *row = rows.firstObject;
    int64_t expiresAt = [row[@"expires_at"] longLongValue];
    if (now >= expiresAt) return nil;

    return row[@"handle"];
}

- (BOOL)saveIdentity:(NSString *)did
              handle:(NSString *)handle
         pdsEndpoint:(NSString *)pdsEndpoint
          signingKey:(NSString *)signingKey
        rawDocument:(NSDictionary *)rawDocument
                 ttl:(NSTimeInterval)ttl
               error:(NSError **)error {
    if (did.length == 0 || handle.length == 0) return NO;

    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:rawDocument ?: @{} options:0 error:&jsonError];
    if (!jsonData) {
        if (error) *error = jsonError;
        return NO;
    }
    NSString *rawDocJson = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    int64_t now = (int64_t)[[NSDate date] timeIntervalSince1970];
    int64_t expiresAt = now + (int64_t)ttl;
    NSString *normalizedHandle = [handle lowercaseString];

    __block BOOL success = NO;
    __block NSError *localError = nil;
    dispatch_sync(_writeQueue, ^{
        success = [self performWriteTransaction:^BOOL(id<ATProtoDatabaseTransactor> tx, NSError **innerError) {
            [tx executeUpdate:@"DELETE FROM beskid_identities WHERE did = ? OR handle = ?"
                       params:@[did, normalizedHandle]
                        error:nil];

            NSString *sql = @"INSERT OR REPLACE INTO beskid_identities(did, handle, pds_endpoint, signing_key, raw_doc_json, indexed_at, expires_at) VALUES(?,?,?,?,?,?,?)";
            return [tx executeUpdate:sql
                              params:@[did, normalizedHandle, pdsEndpoint ?: @"", signingKey ?: @"", rawDocJson, @(now), @(expiresAt)]
                               error:innerError];
        } error:&localError];
    });

    if (!success && error) *error = localError;
    return success;
}

- (nullable NSDictionary *)identityForDID:(NSString *)did error:(NSError **)error {
    int64_t now = (int64_t)[[NSDate date] timeIntervalSince1970];
    NSString *sql = @"SELECT did, handle, pds_endpoint, signing_key, raw_doc_json, expires_at FROM beskid_identities WHERE did = ? LIMIT 1";
    NSArray<NSDictionary *> *rows = [self executeQuery:sql params:@[did ?: @""] error:error];
    if (!rows || rows.count == 0) return nil;

    NSDictionary *row = rows.firstObject;
    int64_t expiresAt = [row[@"expires_at"] longLongValue];
    if (now >= expiresAt) {
        if (error) *error = [NSError errorWithDomain:BeskidDatabaseErrorDomain
                                                code:410
                                            userInfo:@{NSLocalizedDescriptionKey: @"Identity cache has expired"}];
        return nil;
    }

    NSString *json = row[@"raw_doc_json"];
    if ([json isEqualToString:@"{}"]) {
        return nil; // Partial cache (handle only), treat as miss for full identity
    }

    NSDictionary *rawDoc = @{};
    if ([json isKindOfClass:[NSString class]] && json.length > 0) {
        id parsed = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
                                                    options:0
                                                      error:nil];
        if ([parsed isKindOfClass:[NSDictionary class]]) rawDoc = parsed;
    }

    return @{
        @"did": row[@"did"] ?: @"",
        @"handle": row[@"handle"] ?: @"",
        @"pds": row[@"pds_endpoint"] ?: @"",
        @"signing_key": row[@"signing_key"] ?: @"",
        @"raw_document": rawDoc
    };
}

#pragma mark - SQLite helpers

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                            params:(NSArray *)params
                                             error:(NSError **)error {
    return [self.queryRunner executeQuery:sql params:params error:error];
}

- (BOOL)performWriteTransaction:(BOOL (^)(id<ATProtoDatabaseTransactor> tx, NSError **error))block
                          error:(NSError **)error {
    return [self.queryRunner performWriteTransaction:block error:error];
}

@end
