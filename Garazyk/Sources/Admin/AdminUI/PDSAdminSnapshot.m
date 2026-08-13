// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Admin/AdminUI/PDSAdminSnapshot.h"

#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Metrics/GZMetrics.h"
#import "Sync/Firehose/SubscribeReposHandler.h"

@protocol GZPDSAdminStatsSource <NSObject>
- (nullable NSDictionary *)getServerStatsWithError:(NSError **)error;
@end

@interface GZPDSAdminSnapshot ()
@property(nonatomic, strong) PDSDatabase *database;
@property(nonatomic, strong, nullable) id adminStatsSource;
@property(nonatomic, strong, nullable) PDSDatabasePool *userDatabasePool;
@property(nonatomic, strong, nullable) PDSServiceDatabases *serviceDatabases;
@property(nonatomic, strong, nullable) ATProtoSubscribeReposHandler *subscribeReposHandler;
@property(nonatomic, strong, nullable) NSDate *startedAt;
@end

@implementation GZPDSAdminSnapshot

- (instancetype)initWithDatabase:(PDSDatabase *)database
                 adminStatsSource:(nullable id)adminStatsSource
                 userDatabasePool:(nullable PDSDatabasePool *)userDatabasePool
                 serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases
           subscribeReposHandler:(nullable ATProtoSubscribeReposHandler *)subscribeReposHandler
                        startedAt:(nullable NSDate *)startedAt {
    self = [super init];
    if (self) {
        _database = database;
        _adminStatsSource = adminStatsSource;
        _userDatabasePool = userDatabasePool;
        _serviceDatabases = serviceDatabases;
        _subscribeReposHandler = subscribeReposHandler;
        _startedAt = startedAt;
    }
    return self;
}

- (NSDictionary<NSString *, id> *)snapshot {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];

    id<GZPDSAdminStatsSource> statsSource = self.adminStatsSource;
    if ([statsSource respondsToSelector:@selector(getServerStatsWithError:)]) {
        NSError *statsError = nil;
        NSDictionary *stats = [statsSource getServerStatsWithError:&statsError];
        if ([stats isKindOfClass:[NSDictionary class]]) {
            [out addEntriesFromDictionary:stats];
        }
    }

    [self gz_addSessionsTo:out];
    [self gz_addDatabaseTo:out];
    [self gz_addPoolTo:out];
    [self gz_addSequencerTo:out];
    [self gz_addHealthAndUptimeTo:out];

    return [out copy];
}

#pragma mark - Sections

- (void)gz_addSessionsTo:(NSMutableDictionary *)out {
    if (out[@"sessions_active"] || out[@"sessionsActive"]) {
        return;
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSError *error = nil;
    NSArray *rows = [self.database executeParameterizedQuery:
                     @"SELECT COUNT(*) AS count FROM refresh_tokens "
                     @"WHERE expires_at > ? AND next_token IS NULL"
                                                      params:@[@(now)]
                                                       error:&error];
    if (error || rows.count == 0) {
        // Table may be absent in sparse test DBs; omit rather than fail the poll.
        return;
    }
    out[@"sessions_active"] = rows.firstObject[@"count"] ?: @0;
}

- (void)gz_addDatabaseTo:(NSMutableDictionary *)out {
    if ([out[@"database"] isKindOfClass:[NSDictionary class]]) {
        return;
    }
    // In-connection PRAGMA only — no filesystem walks of actor/blob trees.
    NSArray *pageCount = [self.database executeParameterizedQuery:@"PRAGMA page_count"
                                                           params:@[]
                                                            error:nil];
    NSArray *pageSize = [self.database executeParameterizedQuery:@"PRAGMA page_size"
                                                          params:@[]
                                                           error:nil];
    NSArray *journal = [self.database executeParameterizedQuery:@"PRAGMA journal_mode"
                                                         params:@[]
                                                          error:nil];
    NSArray *freelist = [self.database executeParameterizedQuery:@"PRAGMA freelist_count"
                                                          params:@[]
                                                           error:nil];
    int64_t pages = [pageCount.firstObject[@"page_count"] longLongValue];
    int64_t size = [pageSize.firstObject[@"page_size"] longLongValue];
    if (size <= 0) {
        size = 4096;
    }
    id mode = journal.firstObject[@"journal_mode"] ?: journal.firstObject[@"Journal_Mode"];
    if (!mode) {
        // Some SQLite wrappers return the mode under a single anonymous key.
        NSDictionary *row = journal.firstObject;
        if ([row isKindOfClass:[NSDictionary class]] && row.count == 1) {
            mode = row.allValues.firstObject;
        }
    }
    NSMutableDictionary *database = [NSMutableDictionary dictionary];
    database[@"storageBytes"] = @(pages * size);
    if (mode) {
        database[@"journalMode"] = [mode description];
    }
    if (freelist.count > 0) {
        database[@"freelistCount"] = freelist.firstObject[@"freelist_count"] ?: @0;
    }
    out[@"database"] = [database copy];
}

- (void)gz_addPoolTo:(NSMutableDictionary *)out {
    if (!self.userDatabasePool) {
        return;
    }
    // Use size counters only — never collectMetrics (per-DID paths / stores map).
    out[@"pool"] = @{
        @"cachedStores": @(self.userDatabasePool.currentSize),
        @"maxSize": @(self.userDatabasePool.maxSize),
        @"openFileHandles": @(self.userDatabasePool.openFileHandleCount),
    };
}

- (void)gz_addSequencerTo:(NSMutableDictionary *)out {
    NSMutableDictionary *sequencer = [NSMutableDictionary dictionary];
    if (self.serviceDatabases) {
        NSError *error = nil;
        int64_t seq = [self.serviceDatabases getMaxEventSequence:&error];
        if (!error) {
            sequencer[@"currentSeq"] = @(seq);
        }
    }
    if (self.subscribeReposHandler) {
        sequencer[@"subscriberCount"] = @(self.subscribeReposHandler.attachedConnections.count);
    }
    GZMetrics *metrics = [GZMetrics sharedMetrics];
    sequencer[@"backpressureWarnings"] = @(metrics.websocketBackpressureWarningsTotal);
    sequencer[@"backpressureCritical"] = @(metrics.websocketBackpressureCriticalTotal);
    NSString *seqHealth = metrics.websocketBackpressureCriticalTotal > 0 ? @"critical" : @"healthy";
    sequencer[@"healthStatus"] = seqHealth;
    if (sequencer.count > 0) {
        out[@"sequencer"] = [sequencer copy];
    }
}

- (void)gz_addHealthAndUptimeTo:(NSMutableDictionary *)out {
    GZMetrics *metrics = [GZMetrics sharedMetrics];
    NSTimeInterval start = self.startedAt
        ? self.startedAt.timeIntervalSince1970
        : metrics.serverStartTime;
    NSTimeInterval uptime = 0;
    if (start > 0) {
        uptime = MAX(0, [[NSDate date] timeIntervalSince1970] - start);
    }
    out[@"uptimeSeconds"] = @((long long)uptime);

    NSInteger requests = metrics.httpRequestsTotal;
    out[@"httpRequestsTotal"] = @(requests);
    if (uptime > 0) {
        out[@"httpRequestsPerSecond"] = @((double)requests / uptime);
    } else {
        out[@"httpRequestsPerSecond"] = @0.0;
    }

    NSString *health = @"ok";
    NSDictionary *sequencer = out[@"sequencer"];
    if ([sequencer[@"healthStatus"] isEqual:@"critical"]) {
        health = @"degraded";
    }
    NSDictionary *pool = out[@"pool"];
    if ([pool isKindOfClass:[NSDictionary class]]) {
        NSUInteger cached = [pool[@"cachedStores"] unsignedIntegerValue];
        NSUInteger maxSize = [pool[@"maxSize"] unsignedIntegerValue];
        if (maxSize > 0 && cached >= maxSize) {
            health = @"degraded";
        }
    }
    out[@"health"] = health;
}

@end
