// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppView/Server/AdminUI/SyrenaAdminSnapshot.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"
#import "AppView/Server/Config/AppViewConfiguration.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"
#import "AppView/Server/Backfill/AppViewBackfillOrchestrator.h"
#import "AppView/Server/AdminUI/SyrenaMetrics.h"

NSString * _Nullable GZSyrenaAdminPassword(NSString * _Nullable explicitPath) {
    NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
    NSString *path = explicitPath.length > 0 ? explicitPath : environment[@"SYRENA_ADMIN_PASSWORD_FILE"];
    if (path.length > 0) {
        NSError *readError = nil;
        NSString *password = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readError];
        if (!password) return nil;
        password = [password stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return password.length > 0 ? password : nil;
    }
    NSString *password = environment[@"SYRENA_ADMIN_PASSWORD"];
    return password.length > 0 ? password : nil;
}

@interface GZSyrenaAdminSnapshot ()
@property (nonatomic, strong, nullable) AppViewDatabase *database;
@property (nonatomic, strong) SyrenaMetrics *metrics;
@property (nonatomic, strong) AppViewConfiguration *configuration;
@property (nonatomic, strong, nullable) AppViewIngestEngine *ingestEngine;
@property (nonatomic, strong, nullable) AppViewBackfillOrchestrator *orchestrator;
@property (nonatomic, strong) NSDate *startTime;
@end

@implementation GZSyrenaAdminSnapshot

- (instancetype)initWithDatabase:(AppViewDatabase *)database
                         metrics:(SyrenaMetrics *)metrics
                   configuration:(AppViewConfiguration *)configuration
                    ingestEngine:(AppViewIngestEngine *)ingestEngine
         backfillOrchestrator:(AppViewBackfillOrchestrator *)orchestrator {
    self = [super init];
    if (self) {
        _database = database;
        _metrics = metrics;
        _configuration = configuration;
        _ingestEngine = ingestEngine;
        _orchestrator = orchestrator;
        _startTime = [NSDate date];
    }
    return self;
}

- (int64_t)scalarCountSQL:(NSString *)sql {
    if (!self.database || sql.length == 0) return 0;
    NSArray *rows = [self.database executeParameterizedQuery:sql params:@[] error:nil];
    if (rows.count == 0) return 0;
    NSDictionary *row = [rows[0] isKindOfClass:[NSDictionary class]] ? rows[0] : nil;
    if (!row) return 0;
    id value = row[@"c"];
    if (!value) value = row.allValues.firstObject;
    if ([value isKindOfClass:[NSNumber class]]) return [value longLongValue];
    return 0;
}

- (NSDictionary<NSString *, id> *)snapshot {
    NSDictionary *metricsDict = [self.metrics snapshotDictionary];

    NSDictionary *relayHealth = self.ingestEngine.relayHealth ?: @{};
    NSDictionary *lagByRelay = self.ingestEngine.lagByRelay ?: @{};
    NSDictionary *throughput = self.ingestEngine.throughput ?: @{};
    BOOL ingestRunning = self.ingestEngine.isRunning;

    NSInteger pending    = [self.database countRepoSyncStatesWithStatus:AppViewRepoSyncStatusPending error:nil];
    NSInteger processing = [self.database countRepoSyncStatesWithStatus:AppViewRepoSyncStatusProcessing error:nil];
    NSInteger synced     = [self.database countRepoSyncStatesWithStatus:AppViewRepoSyncStatusSynced error:nil];
    NSInteger dirty      = [self.database countRepoSyncStatesWithStatus:AppViewRepoSyncStatusDirty error:nil];

    NSMutableDictionary *backfill = [NSMutableDictionary dictionaryWithDictionary:@{
        @"enabled":        self.orchestrator ? @(YES) : @(NO),
        @"queueDepth":     self.orchestrator ? @(self.orchestrator.queueDepth) : @0,
        @"activeWorkers":  self.orchestrator ? @(self.orchestrator.activeWorkers) : @0,
        @"repoPending":    @(pending),
        @"repoProcessing": @(processing),
        @"repoSynced":     @(synced),
        @"repoDirty":      @(dirty),
        @"repoTotal":      @(pending + processing + synced + dirty),
    }];
    [backfill addEntriesFromDictionary:metricsDict[@"backfill"] ?: @{}];

    NSError *colErr = nil;
    NSArray<NSString *> *collections = [self.database indexedCollectionsWithError:&colErr];
    NSMutableArray *collectionEntries = [NSMutableArray array];
    for (NSString *collection in collections ?: @[]) {
        NSInteger count = [self.database recordCountForCollection:collection error:nil];
        [collectionEntries addObject:@{@"collection": collection, @"count": @(count)}];
    }

    int64_t handleCount = [self scalarCountSQL:@"SELECT COUNT(*) AS c FROM handles"];
    int64_t postCount = [self scalarCountSQL:@"SELECT COUNT(*) AS c FROM records WHERE collection = 'app.bsky.feed.post'"];
    int64_t profileCount = [self scalarCountSQL:@"SELECT COUNT(*) AS c FROM records WHERE collection = 'app.bsky.actor.profile'"];
    int64_t deadLetter = [self scalarCountSQL:@"SELECT COUNT(*) AS c FROM appview_dead_letter"];
    int64_t hookDeadLetter = [self scalarCountSQL:@"SELECT COUNT(*) AS c FROM dead_letter_hooks"];
    int64_t pendingIndex = [self scalarCountSQL:
        @"SELECT COUNT(*) AS c FROM appview_pending_index_events WHERE indexed_at IS NULL AND terminal_error IS NULL"];

    int64_t storageBytes = 0;
    NSArray *pageRows = [self.database executeParameterizedQuery:@"PRAGMA page_count" params:@[] error:nil];
    if (pageRows.count > 0 && pageRows[0][@"page_count"] != [NSNull null]) {
        storageBytes = [pageRows[0][@"page_count"] longLongValue] * 4096;
    }

    NSTimeInterval uptime = -[self.startTime timeIntervalSinceNow];

    NSDictionary *queries = metricsDict[@"queries"] ?: @{};
    int64_t queryTotal = [queries[@"total"] longLongValue];
    int64_t queryErrors = [queries[@"errors"] longLongValue];
    int64_t rateLimitRejects = [metricsDict[@"rateLimitRejects"] longLongValue];

    BOOL anyRelayConnected = NO;
    for (NSString *status in relayHealth.allValues) {
        if ([[status lowercaseString] containsString:@"connect"]) {
            anyRelayConnected = YES;
            break;
        }
    }
    NSString *firehoseLane = (!ingestRunning) ? @"down"
        : (anyRelayConnected || relayHealth.count == 0) ? @"ok" : @"warn";
    NSString *syncLane = (!self.orchestrator) ? @"idle"
        : (dirty > 1000 || pending > 500) ? @"warn"
        : (dirty > 0 || pending > 0 || processing > 0) ? @"active" : @"ok";
    NSString *servingLane = (queryErrors > 0 && queryTotal > 0 && (queryErrors * 100 / MAX(queryTotal, 1)) >= 5) ? @"warn"
        : (rateLimitRejects > 100) ? @"warn" : @"ok";

    NSString *health = @"healthy";
    if (!ingestRunning || [firehoseLane isEqualToString:@"down"]) health = @"degraded";
    else if ([syncLane isEqualToString:@"warn"] || [servingLane isEqualToString:@"warn"] || deadLetter > 0) health = @"degraded";

    return @{
        @"health":            health,
        @"uptimeSeconds":     @((int64_t)uptime),
        @"lanes": @{
            @"firehose": firehoseLane,
            @"sync":     syncLane,
            @"serving":  servingLane,
        },
        @"ingest": @{
            @"running":     @(ingestRunning),
            @"relayHealth": relayHealth,
            @"lagByRelay":  lagByRelay,
            @"throughput":  throughput,
            @"events":      metricsDict[@"ingest"][@"events"] ?: @0,
            @"commits":     metricsDict[@"ingest"][@"commits"] ?: @0,
            @"deletes":     metricsDict[@"ingest"][@"deletes"] ?: @0,
            @"ops":         metricsDict[@"ingest"][@"ops"] ?: @0,
            @"identities":  metricsDict[@"ingest"][@"identities"] ?: @0,
            @"errors":      metricsDict[@"ingest"][@"errors"] ?: @0,
        },
        @"backfill":  backfill,
        @"coverage": @{
            @"handles":  @(handleCount),
            @"profiles": @(profileCount),
            @"posts":    @(postCount),
            @"reposSynced": @(synced),
            @"reposTotal": @(pending + processing + synced + dirty),
        },
        @"exceptions": @{
            @"deadLetter":     @(deadLetter),
            @"hookDeadLetter": @(hookDeadLetter),
            @"pendingIndex":   @(pendingIndex),
        },
        @"indexes":   @{@"collections": collectionEntries},
        @"lexicons":  @{@"count": @(self.configuration.indexCollections.count)},
        @"queries":   queries,
        @"rateLimitRejects": @(rateLimitRejects),
        @"database":  @{@"storageBytes": @(storageBytes)},
        @"config": @{
            @"relayURLs":        self.configuration.relayURLs ?: @[],
            @"backfillEnabled":  @(self.configuration.backfillEnabled),
            @"partialEnabled":   @(self.configuration.partialEnabled),
        },
    };
}

- (NSDictionary<NSString *, id> *)queueWithStatus:(NSString *)status
                                            limit:(NSInteger)limit
                                           cursor:(NSString *)cursor {
    if (!self.orchestrator) {
        return @{@"entries": @[], @"total": @0, @"cursor": [NSNull null], @"enabled": @NO};
    }
    NSDictionary *result = [self.orchestrator queueWithLimit:limit cursor:cursor status:status];
    NSMutableDictionary *out = [result mutableCopy] ?: [NSMutableDictionary dictionary];
    out[@"enabled"] = @YES;
    return out;
}

- (NSDictionary<NSString *, id> *)enqueueDIDs:(NSArray<NSString *> *)dids {
    if (!self.orchestrator) {
        return @{@"error": @"BackfillDisabled", @"message": @"Backfill orchestrator is not running"};
    }
    NSMutableArray<NSString *> *valid = [NSMutableArray array];
    for (id item in dids ?: @[]) {
        if (![item isKindOfClass:[NSString class]]) continue;
        NSString *did = [(NSString *)item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([did hasPrefix:@"did:"] && did.length > 5) {
            [valid addObject:did];
        }
    }
    if (valid.count == 0) {
        return @{@"error": @"BadRequest", @"message": @"Provide at least one did:… value"};
    }
    [self.orchestrator enqueueDIDs:valid];
    return @{@"success": @YES, @"enqueued": @(valid.count)};
}

- (NSDictionary<NSString *, id> *)retryDID:(NSString *)did {
    if (!self.orchestrator) {
        return @{@"error": @"BackfillDisabled", @"message": @"Backfill orchestrator is not running"};
    }
    NSString *trimmed = [did stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![trimmed hasPrefix:@"did:"]) {
        return @{@"error": @"BadRequest", @"message": @"DID required"};
    }
    if (![self.orchestrator retryRepo:trimmed]) {
        return @{@"error": @"NotFound", @"message": @"Repo not found in queue"};
    }
    return @{@"success": @YES, @"did": trimmed};
}

- (NSDictionary<NSString *, id> *)cancelDID:(NSString *)did {
    if (!self.orchestrator) {
        return @{@"error": @"BackfillDisabled", @"message": @"Backfill orchestrator is not running"};
    }
    NSString *trimmed = [did stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![trimmed hasPrefix:@"did:"]) {
        return @{@"error": @"BadRequest", @"message": @"DID required"};
    }
    if (![self.orchestrator cancelRepo:trimmed]) {
        return @{@"error": @"NotFound", @"message": @"Repo not found in queue"};
    }
    return @{@"success": @YES, @"did": trimmed};
}

- (NSDictionary<NSString *, id> *)rebuildScope {
    if (!self.orchestrator) {
        return @{@"error": @"BackfillDisabled", @"message": @"Backfill orchestrator is not running"};
    }
    [self.orchestrator start];
    return @{@"success": @YES, @"message": @"Backfill scope rebuild triggered"};
}

@end
