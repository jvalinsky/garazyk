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
@property(nonatomic, strong) MikrusDatabase *database;
@property(nonatomic, strong) MikrusMetrics *metrics;
@property(nonatomic, strong) MikrusConfiguration *configuration;
@property(nonatomic, weak) AppViewIngestEngine *ingestEngine;
@end

@implementation GZMikrusAdminSnapshot

- (instancetype)initWithDatabase:(MikrusDatabase *)database
                         metrics:(MikrusMetrics *)metrics
                   configuration:(MikrusConfiguration *)configuration
                    ingestEngine:(nullable AppViewIngestEngine *)ingestEngine {
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
    if (self.configuration.ingestEnabled && self.ingestEngine && !self.ingestEngine.isRunning) {
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
    // Query the most recent ingest errors from the event log
    // This assumes an ingest_errors table exists; if not, return empty array
    NSString *sql = @"SELECT timestamp, relay_url, error_message, did, seq "
                    @"FROM ingest_errors ORDER BY timestamp DESC LIMIT ?";
    NSArray *rows = [self.database executeQuery:sql params:@[@(limit)] error:nil];
    
    if (!rows) {
        return @[];
    }
    
    return rows;
}

- (NSDictionary<NSString *, id> *)indexFamilyStatistics {
    // Compute statistics for each index family
    int64_t linksCount = [self approximateRowCount:@"mikrus_links"];
    int64_t recordsCount = [self approximateRowCount:@"mikrus_records"];
    int64_t identitiesCount = [self approximateRowCount:@"mikrus_identities"];
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
    NSString *sql = [NSString stringWithFormat:@"SELECT MAX(rowid) as mx FROM %@", table];
    NSArray *rows = [self.database executeQuery:sql params:@[] error:nil];
    if (rows.count == 0) return 0;
    id value = rows.firstObject[@"mx"];
    if ([value isKindOfClass:[NSNull class]] || !value) return 0;
    return [value longLongValue];
}

@end
