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
        @"checkpointIntervalMs": @(self.ingestEngine.checkpointIntervalMs),
    } mutableCopy];
    [ingestState addEntriesFromDictionary:metricsSnapshot[@"ingest"]];
    
    // approximate index gauges from bounded rowid scan
    int64_t approxEdges = [self approximateRowCount:@"mikrus_links"];
    
    return @{
        @"health": health,
        @"uptimeSeconds": metricsSnapshot[@"uptimeSeconds"],
        @"config": @{
            @"relayURLs": self.configuration.relayURLs ?: @[],
            @"ingestEnabled": @(self.configuration.ingestEnabled),
        },
        @"ingest": ingestState,
        @"indexes": @{
            @"approxEdges": @(approxEdges),
        },
        @"queries": metricsSnapshot[@"queries"],
        @"rateLimitRejects": metricsSnapshot[@"rateLimitRejects"],
        @"database": @{ @"storageBytes": @([self.database storageBytes]) },
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
