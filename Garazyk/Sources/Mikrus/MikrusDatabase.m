// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Mikrus/MikrusDatabase.h"
#import "Mikrus/MikrusLinkExtractor.h"
#import "Mikrus/MikrusSourceSpec.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Database/Connection/ATProtoConnectionManagerPooled.h"
#import "Database/Pool/ATProtoConnectionPool.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Debug/GZLogger.h"

#import <sqlite3.h>

NSString * const MikrusDatabaseErrorDomain = @"blue.microcosm.mikrus.database";

static NSString *MikrusNow(void) {
    return [NSDateFormatter atproto_stringFromDate:[NSDate date]];
}

static int64_t MikrusIndexValue(int64_t seq) {
    if (seq > 0) return seq;
    return (int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

static NSError *MikrusDBError(sqlite3 *db, int code, NSString *fallback) {
    if (db) {
        return ATProtoDBSQLError(MikrusDatabaseErrorDomain, db, code);
    }
    return ATProtoDBError(MikrusDatabaseErrorDomain, fallback ?: @"SQLite error", code);
}

static NSArray<NSString *> *MikrusCleanFilters(NSArray<NSString *> *values) {
    NSMutableArray<NSString *> *cleaned = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *value in values ?: @[]) {
        if (![value isKindOfClass:[NSString class]] || value.length == 0) continue;
        if ([seen containsObject:value]) continue;
        [seen addObject:value];
        [cleaned addObject:value];
    }
    return [cleaned copy];
}

static void MikrusAppendInClause(NSMutableString *sql,
                                        NSMutableArray *params,
                                        NSString *column,
                                        NSArray<NSString *> *values) {
    NSArray<NSString *> *cleaned = MikrusCleanFilters(values);
    if (cleaned.count == 0) return;
    [sql appendFormat:@" AND %@ IN (%@)", column, ATProtoDBPlaceholders(cleaned.count)];
    [params addObjectsFromArray:cleaned];
}

static NSString *MikrusCursorFromDictionary(NSDictionary *dictionary) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
    return data ? [AuthCryptoBase64URL encode:data] : nil;
}

static NSDictionary *MikrusDictionaryFromCursor(NSString *cursor, NSError **error) {
    if (cursor.length == 0) return nil;
    NSData *data = [AuthCryptoBase64URL decode:cursor];
    if (!data) {
        if (error) *error = [NSError errorWithDomain:MikrusDatabaseErrorDomain
                                                code:400
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid cursor"}];
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) *error = [NSError errorWithDomain:MikrusDatabaseErrorDomain
                                                code:400
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid cursor"}];
        return nil;
    }
    return json;
}

@interface MikrusDatabase ()
@property (nonatomic, strong) ATProtoConnectionPool *pool;
@property (nonatomic, strong) ATProtoConnectionManagerPooled *connectionManager;
@end

@implementation MikrusDatabase

- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    if (path.length == 0) {
        if (error) *error = [NSError errorWithDomain:MikrusDatabaseErrorDomain
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

    _pool = [[ATProtoConnectionPool alloc] initWithPath:path minConnections:1 maxConnections:8];
    if (!_pool) {
        if (error) *error = [NSError errorWithDomain:MikrusDatabaseErrorDomain
                                                code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to create connection pool"}];
        return nil;
    }
    _connectionManager = [[ATProtoConnectionManagerPooled alloc] initWithPool:_pool];
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
        @"CREATE TABLE IF NOT EXISTS mikrus_records ("
        "  uri TEXT PRIMARY KEY,"
        "  did TEXT NOT NULL,"
        "  collection TEXT NOT NULL,"
        "  rkey TEXT NOT NULL,"
        "  cid TEXT,"
        "  value_json TEXT,"
        "  indexed_at INTEGER NOT NULL,"
        "  updated_at TEXT NOT NULL,"
        "  UNIQUE(did, collection, rkey)"
        ");"
        "CREATE TABLE IF NOT EXISTS mikrus_links ("
        "  subject TEXT NOT NULL,"
        "  source_collection TEXT NOT NULL,"
        "  source_path TEXT NOT NULL,"
        "  link_did TEXT NOT NULL,"
        "  link_collection TEXT NOT NULL,"
        "  link_rkey TEXT NOT NULL,"
        "  link_uri TEXT NOT NULL,"
        "  link_cid TEXT,"
        "  indexed_at INTEGER NOT NULL,"
        "  created_at TEXT NOT NULL,"
        "  PRIMARY KEY(subject, source_collection, source_path, link_did, link_collection, link_rkey)"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_mikrus_links_subject_source_order "
        "ON mikrus_links(subject, source_collection, source_path, indexed_at DESC, link_did, link_collection, link_rkey);"
        "CREATE INDEX IF NOT EXISTS idx_mikrus_links_subject_source_did_order "
        "ON mikrus_links(subject, source_collection, source_path, link_did, indexed_at DESC, link_collection, link_rkey);"
        "CREATE INDEX IF NOT EXISTS idx_mikrus_links_record "
        "ON mikrus_links(link_did, link_collection, link_rkey);"
        "CREATE INDEX IF NOT EXISTS idx_mikrus_links_record_path "
        "ON mikrus_links(link_did, link_collection, link_rkey, source_collection, source_path, subject);"
        "CREATE TABLE IF NOT EXISTS mikrus_handles ("
        "  handle TEXT PRIMARY KEY,"
        "  did TEXT NOT NULL,"
        "  updated_at TEXT NOT NULL"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_mikrus_handles_did ON mikrus_handles(did);"
        "DROP INDEX IF EXISTS idx_mikrus_records_did_collection;";

    __block BOOL migrated = NO;
    __block NSError *innerError = nil;
    [self.connectionManager execute:^(sqlite3 *db) {
        char *errmsg = NULL;
        int rc = sqlite3_exec(db, schema.UTF8String, NULL, NULL, &errmsg);
        if (rc != SQLITE_OK) {
            NSString *message = errmsg ? [NSString stringWithUTF8String:errmsg] : @"Migration failed";
            innerError = [NSError errorWithDomain:MikrusDatabaseErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
            if (errmsg) {
                sqlite3_free(errmsg);
            }
            return;
        }
        migrated = YES;
    } error:&innerError];
    if (!migrated && error) {
        *error = innerError;
    }
    return migrated;
}

- (BOOL)indexRecord:(NSDictionary *)record
                did:(NSString *)did
         collection:(NSString *)collection
               rkey:(NSString *)rkey
                cid:(nullable NSString *)cid
                seq:(int64_t)seq
              error:(NSError **)error {
    if (![record isKindOfClass:[NSDictionary class]] ||
        did.length == 0 || collection.length == 0 || rkey.length == 0) {
        if (error) *error = [NSError errorWithDomain:MikrusDatabaseErrorDomain
                                                code:400
                                            userInfo:@{NSLocalizedDescriptionKey: @"Missing record identity"}];
        return NO;
    }

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    NSString *json = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *linkEntries =
        [[MikrusLinkExtractor linkEntriesInRecord:record] mutableCopy];
    if ([MikrusLinkExtractor isLinkSubject:rkey]) {
        [linkEntries addObject:@{@"path": @".", @"subject": rkey}];
    }
    int64_t indexedAt = MikrusIndexValue(seq);
    NSString *now = MikrusNow();

    return [self performWriteTransaction:^BOOL(sqlite3 *db, NSError **innerError) {
        NSString *deleteLinks = @"DELETE FROM mikrus_links WHERE link_did = ? AND link_collection = ? AND link_rkey = ?";
        if (![self executeUpdate:deleteLinks params:@[did, collection, rkey] connection:db error:innerError]) return NO;

        NSString *upsertRecord =
            @"INSERT INTO mikrus_records(uri, did, collection, rkey, cid, value_json, indexed_at, updated_at) "
            "VALUES(?,?,?,?,?,?,?,?) "
            "ON CONFLICT(uri) DO UPDATE SET "
            "did=excluded.did, collection=excluded.collection, rkey=excluded.rkey, cid=excluded.cid, "
            "value_json=excluded.value_json, indexed_at=excluded.indexed_at, updated_at=excluded.updated_at";
        if (![self executeUpdate:upsertRecord
                          params:@[uri, did, collection, rkey, cid ?: [NSNull null], json ?: @"{}", @(indexedAt), now]
                      connection:db
                           error:innerError]) {
            return NO;
        }

        NSString *insertLink =
            @"INSERT OR IGNORE INTO mikrus_links("
            "subject, source_collection, source_path, link_did, link_collection, link_rkey, link_uri, link_cid, indexed_at, created_at"
            ") VALUES(?,?,?,?,?,?,?,?,?,?)";
        for (NSDictionary *entry in linkEntries) {
            NSString *path = entry[@"path"];
            NSString *subject = entry[@"subject"];
            if (path.length == 0 || subject.length == 0) continue;
            NSArray *params = @[subject, collection, path, did, collection, rkey, uri, cid ?: [NSNull null], @(indexedAt), now];
            if (![self executeUpdate:insertLink params:params connection:db error:innerError]) return NO;
        }
        return YES;
    } error:error];
}

- (BOOL)deleteRecordForDID:(NSString *)did
                collection:(NSString *)collection
                      rkey:(NSString *)rkey
                     error:(NSError **)error {
    if (did.length == 0 || collection.length == 0 || rkey.length == 0) {
        if (error) *error = [NSError errorWithDomain:MikrusDatabaseErrorDomain
                                                code:400
                                            userInfo:@{NSLocalizedDescriptionKey: @"Missing record identity"}];
        return NO;
    }

    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    return [self performWriteTransaction:^BOOL(sqlite3 *db, NSError **innerError) {
        if (![self executeUpdate:@"DELETE FROM mikrus_links WHERE link_did = ? AND link_collection = ? AND link_rkey = ?"
                          params:@[did, collection, rkey]
                      connection:db
                           error:innerError]) {
            return NO;
        }
        return [self executeUpdate:@"DELETE FROM mikrus_records WHERE uri = ?"
                            params:@[uri]
                        connection:db
                             error:innerError];
    } error:error];
}

- (nullable NSArray<NSDictionary *> *)backlinkRecordsForSubject:(NSString *)subject
                                                         source:(MikrusSourceSpec *)source
                                                     didFilters:(NSArray<NSString *> *)didFilters
                                                          limit:(NSInteger)limit
                                                         cursor:(nullable NSString *)cursor
                                                     nextCursor:(NSString * _Nullable * _Nullable)nextCursor
                                                          total:(NSInteger * _Nullable)total
                                                          error:(NSError **)error {
    if (nextCursor) *nextCursor = nil;
    if (total) *total = 0;
    NSDictionary *cursorDict = MikrusDictionaryFromCursor(cursor, error);
    if (cursor.length > 0 && !cursorDict) return nil;

    NSMutableString *countSQL = [NSMutableString stringWithString:
        @"SELECT COUNT(*) AS total FROM mikrus_links "
        "WHERE subject = ? AND source_collection = ? AND source_path = ?"];
    NSMutableArray *countParams = [NSMutableArray arrayWithArray:@[subject, source.collection, source.path]];
    MikrusAppendInClause(countSQL, countParams, @"link_did", didFilters);
    NSArray *countRows = [self executeQuery:countSQL params:countParams error:error];
    if (!countRows) return nil;
    if (total && countRows.count > 0) *total = [countRows.firstObject[@"total"] integerValue];

    NSMutableString *sql = [NSMutableString stringWithString:
        @"SELECT link_did AS did, link_collection AS collection, link_rkey AS rkey, indexed_at "
        "FROM mikrus_links "
        "WHERE subject = ? AND source_collection = ? AND source_path = ?"];
    NSMutableArray *params = [NSMutableArray arrayWithArray:@[subject, source.collection, source.path]];
    MikrusAppendInClause(sql, params, @"link_did", didFilters);

    if (cursorDict) {
        [sql appendString:
            @" AND (indexed_at < ? OR (indexed_at = ? AND "
            "(link_did > ? OR (link_did = ? AND link_collection > ?) OR "
            "(link_did = ? AND link_collection = ? AND link_rkey > ?))))"];
        NSNumber *indexedAt = cursorDict[@"indexed_at"] ?: @0;
        NSString *did = cursorDict[@"did"] ?: @"";
        NSString *collection = cursorDict[@"collection"] ?: @"";
        NSString *rkey = cursorDict[@"rkey"] ?: @"";
        [params addObjectsFromArray:@[indexedAt, indexedAt, did, did, collection, did, collection, rkey]];
    }

    [sql appendString:@" ORDER BY indexed_at DESC, link_did ASC, link_collection ASC, link_rkey ASC LIMIT ?"];
    [params addObject:@(limit + 1)];

    NSArray *rows = [self executeQuery:sql params:params error:error];
    if (!rows) return nil;
    BOOL hasMore = rows.count > (NSUInteger)limit;
    NSArray *pageRows = hasMore ? [rows subarrayWithRange:NSMakeRange(0, (NSUInteger)limit)] : rows;

    NSMutableArray *records = [NSMutableArray arrayWithCapacity:pageRows.count];
    for (NSDictionary *row in pageRows) {
        [records addObject:@{
            @"did": row[@"did"] ?: @"",
            @"collection": row[@"collection"] ?: @"",
            @"rkey": row[@"rkey"] ?: @""
        }];
    }
    if (hasMore && nextCursor && pageRows.count > 0) {
        NSDictionary *row = pageRows.lastObject;
        *nextCursor = MikrusCursorFromDictionary(@{
            @"indexed_at": row[@"indexed_at"] ?: @0,
            @"did": row[@"did"] ?: @"",
            @"collection": row[@"collection"] ?: @"",
            @"rkey": row[@"rkey"] ?: @""
        });
    }
    return [records copy];
}

- (nullable NSArray<NSString *> *)backlinkDIDsForSubject:(NSString *)subject
                                                  source:(MikrusSourceSpec *)source
                                                   limit:(NSInteger)limit
                                                  cursor:(nullable NSString *)cursor
                                              nextCursor:(NSString * _Nullable * _Nullable)nextCursor
                                                   total:(NSInteger * _Nullable)total
                                                   error:(NSError **)error {
    if (nextCursor) *nextCursor = nil;
    if (total) *total = 0;
    NSDictionary *cursorDict = MikrusDictionaryFromCursor(cursor, error);
    if (cursor.length > 0 && !cursorDict) return nil;

    NSString *countSQL =
        @"SELECT COUNT(*) AS total FROM ("
        "SELECT link_did FROM mikrus_links "
        "WHERE subject = ? AND source_collection = ? AND source_path = ? "
        "GROUP BY link_did)";
    NSArray *countRows = [self executeQuery:countSQL params:@[subject, source.collection, source.path] error:error];
    if (!countRows) return nil;
    if (total && countRows.count > 0) *total = [countRows.firstObject[@"total"] integerValue];

    NSMutableString *sql = [NSMutableString stringWithString:
        @"SELECT link_did AS did, MAX(indexed_at) AS indexed_at "
        "FROM mikrus_links "
        "WHERE subject = ? AND source_collection = ? AND source_path = ? "
        "GROUP BY link_did"];
    NSMutableArray *params = [NSMutableArray arrayWithArray:@[subject, source.collection, source.path]];
    if (cursorDict) {
        [sql appendString:@" HAVING (MAX(indexed_at) < ? OR (MAX(indexed_at) = ? AND link_did > ?))"];
        NSNumber *indexedAt = cursorDict[@"indexed_at"] ?: @0;
        NSString *did = cursorDict[@"did"] ?: @"";
        [params addObjectsFromArray:@[indexedAt, indexedAt, did]];
    }
    [sql appendString:@" ORDER BY indexed_at DESC, link_did ASC LIMIT ?"];
    [params addObject:@(limit + 1)];

    NSArray *rows = [self executeQuery:sql params:params error:error];
    if (!rows) return nil;
    BOOL hasMore = rows.count > (NSUInteger)limit;
    NSArray *pageRows = hasMore ? [rows subarrayWithRange:NSMakeRange(0, (NSUInteger)limit)] : rows;

    NSMutableArray<NSString *> *dids = [NSMutableArray arrayWithCapacity:pageRows.count];
    for (NSDictionary *row in pageRows) {
        NSString *did = row[@"did"];
        if (did.length > 0) [dids addObject:did];
    }
    if (hasMore && nextCursor && pageRows.count > 0) {
        NSDictionary *row = pageRows.lastObject;
        *nextCursor = MikrusCursorFromDictionary(@{
            @"indexed_at": row[@"indexed_at"] ?: @0,
            @"did": row[@"did"] ?: @""
        });
    }
    return [dids copy];
}

- (NSInteger)backlinksCountForSubject:(NSString *)subject
                                source:(MikrusSourceSpec *)source
                                 error:(NSError **)error {
    NSString *sql =
        @"SELECT COUNT(*) AS total FROM mikrus_links "
        "WHERE subject = ? AND source_collection = ? AND source_path = ?";
    NSArray *rows = [self executeQuery:sql params:@[subject, source.collection, source.path] error:error];
    if (!rows || rows.count == 0) return -1;
    return [rows.firstObject[@"total"] integerValue];
}

- (nullable NSArray<NSDictionary *> *)manyToManyItemsForSubject:(NSString *)subject
                                                         source:(MikrusSourceSpec *)source
                                                    pathToOther:(NSString *)pathToOther
                                                       linkDIDs:(NSArray<NSString *> *)linkDIDs
                                                  otherSubjects:(NSArray<NSString *> *)otherSubjects
                                                          limit:(NSInteger)limit
                                                         cursor:(nullable NSString *)cursor
                                                     nextCursor:(NSString * _Nullable * _Nullable)nextCursor
                                                          error:(NSError **)error {
    if (nextCursor) *nextCursor = nil;
    NSDictionary *cursorDict = MikrusDictionaryFromCursor(cursor, error);
    if (cursor.length > 0 && !cursorDict) return nil;

    NSMutableString *sql = [NSMutableString stringWithString:
        @"SELECT l1.link_did AS did, l1.link_collection AS collection, l1.link_rkey AS rkey, "
        "l2.subject AS other_subject, l1.indexed_at AS indexed_at "
        "FROM mikrus_links l1 "
        "JOIN mikrus_links l2 "
        "ON l2.link_did = l1.link_did "
        "AND l2.link_collection = l1.link_collection "
        "AND l2.link_rkey = l1.link_rkey "
        "AND l2.source_collection = l1.source_collection "
        "AND l2.source_path = ? "
        "WHERE l1.subject = ? AND l1.source_collection = ? AND l1.source_path = ?"];
    NSMutableArray *params = [NSMutableArray arrayWithArray:@[pathToOther, subject, source.collection, source.path]];
    MikrusAppendInClause(sql, params, @"l1.link_did", linkDIDs);
    MikrusAppendInClause(sql, params, @"l2.subject", otherSubjects);

    if (cursorDict) {
        [sql appendString:
            @" AND (l1.indexed_at < ? OR (l1.indexed_at = ? AND "
            "(l1.link_did > ? OR (l1.link_did = ? AND l1.link_collection > ?) OR "
            "(l1.link_did = ? AND l1.link_collection = ? AND l1.link_rkey > ?) OR "
            "(l1.link_did = ? AND l1.link_collection = ? AND l1.link_rkey = ? AND l2.subject > ?))))"];
        NSNumber *indexedAt = cursorDict[@"indexed_at"] ?: @0;
        NSString *did = cursorDict[@"did"] ?: @"";
        NSString *collection = cursorDict[@"collection"] ?: @"";
        NSString *rkey = cursorDict[@"rkey"] ?: @"";
        NSString *other = cursorDict[@"other"] ?: @"";
        [params addObjectsFromArray:@[indexedAt, indexedAt, did, did, collection,
                                      did, collection, rkey, did, collection, rkey, other]];
    }

    [sql appendString:@" ORDER BY l1.indexed_at DESC, l1.link_did ASC, l1.link_collection ASC, l1.link_rkey ASC, l2.subject ASC LIMIT ?"];
    [params addObject:@(limit + 1)];

    NSArray *rows = [self executeQuery:sql params:params error:error];
    if (!rows) return nil;
    BOOL hasMore = rows.count > (NSUInteger)limit;
    NSArray *pageRows = hasMore ? [rows subarrayWithRange:NSMakeRange(0, (NSUInteger)limit)] : rows;

    NSMutableArray *items = [NSMutableArray arrayWithCapacity:pageRows.count];
    for (NSDictionary *row in pageRows) {
        [items addObject:@{
            @"linkRecord": @{
                @"did": row[@"did"] ?: @"",
                @"collection": row[@"collection"] ?: @"",
                @"rkey": row[@"rkey"] ?: @""
            },
            @"otherSubject": row[@"other_subject"] ?: @""
        }];
    }
    if (hasMore && nextCursor && pageRows.count > 0) {
        NSDictionary *row = pageRows.lastObject;
        *nextCursor = MikrusCursorFromDictionary(@{
            @"indexed_at": row[@"indexed_at"] ?: @0,
            @"did": row[@"did"] ?: @"",
            @"collection": row[@"collection"] ?: @"",
            @"rkey": row[@"rkey"] ?: @"",
            @"other": row[@"other_subject"] ?: @""
        });
    }
    return [items copy];
}

- (nullable NSArray<NSDictionary *> *)manyToManyCountsForSubject:(NSString *)subject
                                                          source:(MikrusSourceSpec *)source
                                                     pathToOther:(NSString *)pathToOther
                                                            dids:(NSArray<NSString *> *)dids
                                                   otherSubjects:(NSArray<NSString *> *)otherSubjects
                                                           limit:(NSInteger)limit
                                                          cursor:(nullable NSString *)cursor
                                                      nextCursor:(NSString * _Nullable * _Nullable)nextCursor
                                                           error:(NSError **)error {
    if (nextCursor) *nextCursor = nil;
    NSDictionary *cursorDict = MikrusDictionaryFromCursor(cursor, error);
    if (cursor.length > 0 && !cursorDict) return nil;

    NSMutableString *sql = [NSMutableString stringWithString:
        @"SELECT l2.subject AS subject, COUNT(*) AS total, COUNT(DISTINCT l1.link_did) AS distinct_count "
        "FROM mikrus_links l1 "
        "JOIN mikrus_links l2 "
        "ON l2.link_did = l1.link_did "
        "AND l2.link_collection = l1.link_collection "
        "AND l2.link_rkey = l1.link_rkey "
        "AND l2.source_collection = l1.source_collection "
        "AND l2.source_path = ? "
        "WHERE l1.subject = ? AND l1.source_collection = ? AND l1.source_path = ?"];
    NSMutableArray *params = [NSMutableArray arrayWithArray:@[pathToOther, subject, source.collection, source.path]];
    MikrusAppendInClause(sql, params, @"l1.link_did", dids);
    MikrusAppendInClause(sql, params, @"l2.subject", otherSubjects);
    [sql appendString:@" GROUP BY l2.subject"];

    if (cursorDict) {
        [sql appendString:@" HAVING (COUNT(*) < ? OR (COUNT(*) = ? AND l2.subject > ?))"];
        NSNumber *total = cursorDict[@"total"] ?: @0;
        NSString *cursorSubject = cursorDict[@"subject"] ?: @"";
        [params addObjectsFromArray:@[total, total, cursorSubject]];
    }

    [sql appendString:@" ORDER BY total DESC, l2.subject ASC LIMIT ?"];
    [params addObject:@(limit + 1)];

    NSArray *rows = [self executeQuery:sql params:params error:error];
    if (!rows) return nil;
    BOOL hasMore = rows.count > (NSUInteger)limit;
    NSArray *pageRows = hasMore ? [rows subarrayWithRange:NSMakeRange(0, (NSUInteger)limit)] : rows;

    NSMutableArray *counts = [NSMutableArray arrayWithCapacity:pageRows.count];
    for (NSDictionary *row in pageRows) {
        [counts addObject:@{
            @"subject": row[@"subject"] ?: @"",
            @"total": row[@"total"] ?: @0,
            @"distinct": row[@"distinct_count"] ?: @0
        }];
    }
    if (hasMore && nextCursor && pageRows.count > 0) {
        NSDictionary *row = pageRows.lastObject;
        *nextCursor = MikrusCursorFromDictionary(@{
            @"total": row[@"total"] ?: @0,
            @"subject": row[@"subject"] ?: @""
        });
    }
    return [counts copy];
}

- (nullable NSDictionary *)recordByURI:(NSString *)uri
                                   cid:(nullable NSString *)cid
                                 error:(NSError **)error {
    NSString *sql = @"SELECT uri, cid, value_json FROM mikrus_records WHERE uri = ? LIMIT 1";
    NSArray *rows = [self executeQuery:sql params:@[uri ?: @""] error:error];
    if (!rows || rows.count == 0) {
        if (error) *error = [NSError errorWithDomain:MikrusDatabaseErrorDomain
                                                code:404
                                            userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        return nil;
    }

    NSDictionary *row = rows.firstObject;
    NSString *storedCID = row[@"cid"];
    if (cid.length > 0 && storedCID.length > 0 && ![storedCID isEqualToString:cid]) {
        if (error) *error = [NSError errorWithDomain:MikrusDatabaseErrorDomain
                                                code:404
                                            userInfo:@{NSLocalizedDescriptionKey: @"Record not found for requested CID"}];
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

- (BOOL)saveHandle:(NSString *)handle did:(NSString *)did error:(NSError **)error {
    if (handle.length == 0 || did.length == 0) return YES;
    NSString *normalized = [handle lowercaseString];
    return [self performWriteTransaction:^BOOL(sqlite3 *db, NSError **innerError) {
        if (![self executeUpdate:@"DELETE FROM mikrus_handles WHERE did = ?"
                          params:@[did]
                      connection:db
                           error:innerError]) {
            return NO;
        }
        return [self executeUpdate:@"INSERT OR REPLACE INTO mikrus_handles(handle, did, updated_at) VALUES(?,?,?)"
                            params:@[normalized, did, MikrusNow()]
                        connection:db
                             error:innerError];
    } error:error];
}

- (nullable NSString *)resolveHandleToDID:(NSString *)handle error:(NSError **)error {
    NSArray *rows = [self executeQuery:@"SELECT did FROM mikrus_handles WHERE handle = ? LIMIT 1"
                                params:@[[handle lowercaseString] ?: @""]
                                 error:error];
    if (!rows || rows.count == 0) return nil;
    return rows.firstObject[@"did"];
}

- (nullable NSString *)resolveDIDToHandle:(NSString *)did error:(NSError **)error {
    NSArray *rows = [self executeQuery:@"SELECT handle FROM mikrus_handles WHERE did = ? LIMIT 1"
                                params:@[did ?: @""]
                                 error:error];
    if (!rows || rows.count == 0) return nil;
    return rows.firstObject[@"handle"];
}

#pragma mark - SQLite helpers

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                            params:(NSArray *)params
                                             error:(NSError **)error {
    __block NSArray<NSDictionary *> *result = nil;
    __block NSError *innerError = nil;
    [self.connectionManager execute:^(sqlite3 *db) {
        sqlite3_stmt *stmt = NULL;
        int rc = sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            innerError = MikrusDBError(db, rc, @"Failed to prepare query");
            return;
        }
        ATProtoDBBindParams(stmt, params ?: @[]);

        NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
        while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
            NSMutableDictionary *row = [NSMutableDictionary dictionary];
            int count = sqlite3_column_count(stmt);
            for (int i = 0; i < count; i++) {
                const char *name = sqlite3_column_name(stmt, i);
                if (!name) continue;
                row[[NSString stringWithUTF8String:name]] = ATProtoDBColumnValue(stmt, i) ?: [NSNull null];
            }
            [rows addObject:row];
        }

        if (rc != SQLITE_DONE) {
            innerError = MikrusDBError(db, rc, @"Failed to execute query");
            sqlite3_finalize(stmt);
            return;
        }

        sqlite3_finalize(stmt);
        result = [rows copy];
    } error:&innerError];

    if (!result && error) {
        *error = innerError;
    }
    return result;
}

- (BOOL)executeUpdate:(NSString *)sql
               params:(NSArray *)params
           connection:(sqlite3 *)db
                error:(NSError **)error {
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = MikrusDBError(db, rc, @"Failed to prepare update");
        return NO;
    }
    ATProtoDBBindParams(stmt, params ?: @[]);
    rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        if (error) *error = MikrusDBError(db, rc, @"Failed to execute update");
        sqlite3_finalize(stmt);
        return NO;
    }
    sqlite3_finalize(stmt);
    return YES;
}

- (BOOL)performWriteTransaction:(BOOL (^)(sqlite3 *db, NSError **error))block
                          error:(NSError **)error {
    __block BOOL innerOK = YES;
    __block NSError *innerError = nil;
    BOOL ok = [self.connectionManager transact:^(sqlite3 *db, BOOL *rollback) {
        innerOK = block(db, &innerError);
        *rollback = !innerOK;
    } error:&innerError];

    if (!ok && error) *error = innerError;
    return ok;
}

@end
