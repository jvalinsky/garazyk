// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Mikrus/AdminUI/MikrusAdminSnapshot.h"
#import "Mikrus/MikrusDatabase.h"
#import "Mikrus/MikrusMetrics.h"
#import "Mikrus/MikrusConfiguration.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"

NSString *GZMikrusAdminPasswordFromFile(NSString *path, NSError * _Nullable * _Nullable error) {
    NSString *password = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!password) {
        if (error) *error = [NSError errorWithDomain:@"GZMikrusAdminUI" code:1 userInfo:@{ NSLocalizedDescriptionKey: @"Unable to read Mikrus admin password file" }];
        return nil;
    }
    password = [password stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
    if (password.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"GZMikrusAdminUI" code:2 userInfo:@{ NSLocalizedDescriptionKey: @"Mikrus admin password file is empty" }];
        return nil;
    }
    return password;
}

@interface GZMikrusAdminSnapshot ()
@property(nonatomic, strong) GZMikrusDatabase *database;
@property(nonatomic, strong) GZMikrusMetrics *metrics;
@property(nonatomic, strong) GZMikrusConfiguration *configuration;
@property(nonatomic, weak) GZAppViewIngestEngine *ingestEngine;
@end

@implementation GZMikrusAdminSnapshot

- (instancetype)initWithDatabase:(GZMikrusDatabase *)database
                         metrics:(GZMikrusMetrics *)metrics
                   configuration:(GZMikrusConfiguration *)configuration
                    ingestEngine:(nullable GZAppViewIngestEngine *)ingestEngine {
    self = [super init];
    if (self) {
        _database = database;
        _metrics = metrics;
        _configuration = configuration;
        _ingestEngine = ingestEngine;
    }
    return self;
}

- (NSDictionary<NSString *, id> *)snapshot {
    NSDictionary *metricsSnapshot = [self.metrics snapshotDictionary];
    
    // health: degraded when ingest enabled but not running
    NSString *health = @"ok";
    if (self.configuration.ingestEnabled && (!self.ingestEngine || !self.ingestEngine.isRunning)) {
        health = @"degraded";
    }
    
    // ingest state
    NSMutableDictionary *ingestState = [@{
        @"enabled": @(self.configuration.ingestEnabled),
        @"running": self.ingestEngine ? @(self.ingestEngine.isRunning) : @NO,
        @"relayURLs": self.configuration.relayURLs ?: @[],
        @"relayHealth": self.ingestEngine.relayHealth ?: @{},
        @"lagByRelay": self.ingestEngine.lagByRelay ?: @{},
        @"throughput": self.ingestEngine.throughput ?: @{},
        @"checkpointIntervalMs": @(self.ingestEngine.checkpointIntervalMs),
    } mutableCopy];
    [ingestState addEntriesFromDictionary:metricsSnapshot[@"ingest"]];
    
    // index statistics
    NSDictionary *indexStats = [self indexFamilyStatistics];
    
    // collection distribution (top 10)
    NSDictionary *topCollections = [self topCollectionCounts:10];
    
    return @{
        @"health": health,
        @"uptimeSeconds": metricsSnapshot[@"uptimeSeconds"],
        @"config": @{
            @"relayURLs": self.configuration.relayURLs ?: @[],
            @"ingestEnabled": @(self.configuration.ingestEnabled),
        },
        @"ingest": ingestState,
        @"indexes": indexStats,
        @"topCollections": topCollections,
        @"queries": metricsSnapshot[@"queries"],
        @"rateLimitRejects": metricsSnapshot[@"rateLimitRejects"],
        @"database": @{ @"storageBytes": @([self.database storageBytes]) },
        @"recentErrors": [self recentErrors:10],
    };
}

- (NSDictionary<NSString *, NSNumber *> *)topCollectionCounts:(NSInteger)limit {
    // Query top N collections by record count from the mikrus_records table
    NSString *sql = @"SELECT collection, COUNT(*) as cnt FROM mikrus_records "
                    @"GROUP BY collection ORDER BY cnt DESC LIMIT ?";
    NSArray *rows = [self.database executeQuery:sql params:@[@(limit)] error:nil];
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSDictionary *row in rows) {
        NSString *collection = row[@"collection"];
        NSNumber *count = row[@"cnt"];
        if (collection && count) {
            result[collection] = count;
        }
    }
    return [result copy];
}

- (NSArray<NSDictionary *> *)recentErrors:(NSInteger)limit {
    // Error-log polling is bounded like explore queries. Non-positive limits
    // are treated as an empty request rather than reaching SQLite LIMIT -1.
    if (limit <= 0) return @[];
    limit = MIN(limit, 100);
    // Query the most recent ingest errors from the event log
    // This assumes an ingest_errors table exists; if not, return empty array
    // Error messages can contain request bodies, local paths, or credentials.
    // Keep only operational context; never expose the diagnostic payload.
    NSString *sql = @"SELECT timestamp, relay_url, seq "
                    @"FROM ingest_errors ORDER BY timestamp DESC LIMIT ?";
    NSArray *rows = [self.database executeQuery:sql params:@[@(limit)] error:nil];
    
    if (!rows) {
        return @[];
    }

    NSMutableArray *safeRows = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSMutableDictionary *safeRow = [row mutableCopy];
        safeRow[@"error_message"] = @"Ingest error (details redacted)";
        NSString *relayURL = [row[@"relay_url"] isKindOfClass:[NSString class]] ? row[@"relay_url"] : nil;
        NSURLComponents *components = relayURL.length > 0 ? [NSURLComponents componentsWithString:relayURL] : nil;
        NSString *host = components.host;
        safeRow[@"relay_url"] = host.length > 0 ? host : @"(relay redacted)";
        [safeRows addObject:safeRow];
    }
    return safeRows;
}

- (NSDictionary<NSString *, id> *)indexFamilyStatistics {
    // Compute statistics for each index family
    int64_t linksCount = [self approximateRowCount:@"mikrus_links"];
    int64_t recordsCount = [self approximateRowCount:@"mikrus_records"];
    int64_t identitiesCount = [self approximateRowCount:@"mikrus_handles"];
    int64_t manyToManyCount = [self approximateRowCount:@"mikrus_many_to_many"];
    
    return @{
        @"backlinks": @{
            @"approxEdges": @(linksCount),
            @"description": @"URI-to-URI link edges",
        },
        @"records": @{
            @"approxCount": @(recordsCount),
            @"description": @"Cached record lookups",
        },
        @"identities": @{
            @"approxCount": @(identitiesCount),
            @"description": @"DID-to-handle mappings",
        },
        @"manyToMany": @{
            @"approxEdges": @(manyToManyCount),
            @"description": @"Relationship edges",
        },
    };
}

- (int64_t)approximateRowCount:(NSString *)table {
    static NSSet<NSString *> *allowed = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSSet setWithArray:@[
            @"mikrus_links", @"mikrus_records", @"mikrus_handles", @"mikrus_many_to_many"
        ]];
    });
    if (![allowed containsObject:table]) return 0;

    // MAX(rowid) is an intentionally O(1)-shaped approximation. The dashboard
    // must not turn every poll into an unbounded COUNT scan.
    NSString *sql = [NSString stringWithFormat:@"SELECT MAX(rowid) as mx FROM %@", table];
    NSArray *rows = [self.database executeQuery:sql params:@[] error:nil];
    if (rows.count == 0) return 0;
    id value = rows.firstObject[@"mx"];
    if ([value isKindOfClass:[NSNull class]] || !value) return 0;
    return [value longLongValue];
}

static NSInteger GZMikrusClampExploreLimit(NSInteger limit) {
    if (limit < 1) return 25;
    if (limit > 100) return 100;
    return limit;
}

- (NSArray<NSDictionary *> *)listRecordsInCollection:(NSString *)collection
                                               limit:(NSInteger)limit
                                              cursor:(nullable NSString *)cursor
                                          nextCursor:(NSString * _Nullable * _Nullable)nextCursor {
    if (nextCursor) *nextCursor = nil;
    if (collection.length == 0) return @[];

    NSInteger pageSize = GZMikrusClampExploreLimit(limit);
    NSMutableArray *params = [NSMutableArray arrayWithObject:collection];
    NSString *sql;
    if (cursor.length > 0) {
        sql = @"SELECT uri, did, collection, rkey, cid, indexed_at FROM mikrus_records "
              @"WHERE collection = ? AND uri > ? ORDER BY uri ASC LIMIT ?";
        [params addObject:cursor];
    } else {
        sql = @"SELECT uri, did, collection, rkey, cid, indexed_at FROM mikrus_records "
              @"WHERE collection = ? ORDER BY uri ASC LIMIT ?";
    }
    [params addObject:@(pageSize + 1)];

    NSArray *rows = [self.database executeQuery:sql params:params error:nil] ?: @[];
    if ((NSInteger)rows.count > pageSize) {
        if (nextCursor) {
            *nextCursor = rows[pageSize - 1][@"uri"];
        }
        return [rows subarrayWithRange:NSMakeRange(0, (NSUInteger)pageSize)];
    }
    return rows;
}

- (NSArray<NSDictionary *> *)searchIndexWithQuery:(NSString *)query limit:(NSInteger)limit {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return @[];

    NSInteger pageSize = GZMikrusClampExploreLimit(limit);

    if ([trimmed hasPrefix:@"at://"]) {
        NSString *sql = @"SELECT uri, did, collection, rkey, cid, indexed_at FROM mikrus_records "
                        @"WHERE uri = ? LIMIT 1";
        return [self.database executeQuery:sql params:@[trimmed] error:nil] ?: @[];
    }

    if ([trimmed hasPrefix:@"did:"]) {
        NSString *sql = @"SELECT uri, did, collection, rkey, cid, indexed_at FROM mikrus_records "
                        @"WHERE did = ? ORDER BY indexed_at DESC, uri ASC LIMIT ?";
        return [self.database executeQuery:sql params:@[trimmed, @(pageSize)] error:nil] ?: @[];
    }

    // Handle lookup → DID records
    NSError *handleError = nil;
    NSString *resolvedDID = [self.database resolveHandleToDID:trimmed error:&handleError];
    if (resolvedDID.length > 0) {
        NSString *sql = @"SELECT uri, did, collection, rkey, cid, indexed_at FROM mikrus_records "
                        @"WHERE did = ? ORDER BY indexed_at DESC, uri ASC LIMIT ?";
        NSArray *rows = [self.database executeQuery:sql params:@[resolvedDID, @(pageSize)] error:nil] ?: @[];
        if (rows.count > 0) return rows;
    }

    // Exact collection match
    NSString *exactSQL = @"SELECT uri, did, collection, rkey, cid, indexed_at FROM mikrus_records "
                         @"WHERE collection = ? ORDER BY indexed_at DESC, uri ASC LIMIT ?";
    NSArray *exact = [self.database executeQuery:exactSQL params:@[trimmed, @(pageSize)] error:nil] ?: @[];
    if (exact.count > 0) return exact;

    // Collection / URI prefix (bounded)
    NSString *prefix = [trimmed stringByAppendingString:@"%"];
    NSString *prefixSQL = @"SELECT uri, did, collection, rkey, cid, indexed_at FROM mikrus_records "
                          @"WHERE collection LIKE ? OR uri LIKE ? "
                          @"ORDER BY indexed_at DESC, uri ASC LIMIT ?";
    return [self.database executeQuery:prefixSQL params:@[prefix, prefix, @(pageSize)] error:nil] ?: @[];
}

- (nullable NSDictionary<NSString *, id> *)recordDetailForURI:(NSString *)uri {
    if (uri.length == 0) return nil;

    NSError *error = nil;
    NSDictionary *record = [self.database recordByURI:uri cid:nil error:&error];
    if (!record) return nil;

    NSString *metaSQL = @"SELECT did, collection, rkey, indexed_at, updated_at FROM mikrus_records WHERE uri = ? LIMIT 1";
    NSArray *metaRows = [self.database executeQuery:metaSQL params:@[uri] error:nil];
    NSDictionary *meta = metaRows.firstObject ?: @{};

    NSString *linksSQL = @"SELECT subject, source_collection, source_path, link_uri, link_cid, indexed_at "
                         @"FROM mikrus_links WHERE subject = ? OR link_uri = ? "
                         @"ORDER BY indexed_at DESC LIMIT 25";
    NSArray *links = [self.database executeQuery:linksSQL params:@[uri, uri] error:nil] ?: @[];

    NSMutableDictionary *detail = [@{
        @"uri": record[@"uri"] ?: uri,
        @"value": record[@"value"] ?: @{},
        @"backlinks": links,
    } mutableCopy];
    if (record[@"cid"]) detail[@"cid"] = record[@"cid"];
    if (meta[@"did"]) detail[@"did"] = meta[@"did"];
    if (meta[@"collection"]) detail[@"collection"] = meta[@"collection"];
    if (meta[@"rkey"]) detail[@"rkey"] = meta[@"rkey"];
    if (meta[@"indexed_at"]) detail[@"indexed_at"] = meta[@"indexed_at"];
    if (meta[@"updated_at"]) detail[@"updated_at"] = meta[@"updated_at"];
    return [detail copy];
}

@end
