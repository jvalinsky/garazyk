// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppView/Server/AdminUI/SyrenaAdminSnapshot.h"

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
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"
#import "AppView/Server/Config/AppViewConfiguration.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"
#import "AppView/Server/Backfill/AppViewBackfillOrchestrator.h"
#import "AppView/Server/AdminUI/SyrenaMetrics.h"

@interface GZSyrenaAdminSnapshot ()
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) SyrenaMetrics *metrics;
@property (nonatomic, strong) AppViewConfiguration *configuration;
@property (nonatomic, strong) AppViewIngestEngine *ingestEngine;
@property (nonatomic, strong, nullable) AppViewBackfillOrchestrator *orchestrator;
@property (nonatomic, strong) NSDate *startTime;
@end

@implementation GZSyrenaAdminSnapshot

- (instancetype)initWithDatabase:(AppViewDatabase *)database
                         metrics:(SyrenaMetrics *)metrics
                   configuration:(AppViewConfiguration *)configuration
                    ingestEngine:(AppViewIngestEngine *)ingestEngine
         backfillOrchestrator:(nullable AppViewBackfillOrchestrator *)orchestrator {
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

- (NSDictionary<NSString *, id> *)snapshot {
    NSDictionary *metricsDict = [self.metrics snapshotDictionary];

    // Ingest
    NSDictionary *relayHealth = self.ingestEngine.relayHealth ?: @{};
    NSDictionary *lagByRelay = self.ingestEngine.lagByRelay ?: @{};
    NSDictionary *throughput = self.ingestEngine.throughput ?: @{};
    BOOL ingestRunning = self.ingestEngine.isRunning;

    // Backfill
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
    }];
    [backfill addEntriesFromDictionary:metricsDict[@"backfill"] ?: @{}];

    // Indexes: cheap collection counts
    NSError *colErr = nil;
    NSArray<NSString *> *collections = [self.database indexedCollectionsWithError:&colErr];
    NSMutableArray *collectionEntries = [NSMutableArray array];
    for (NSString *collection in collections ?: @[]) {
        NSInteger count = [self.database recordCountForCollection:collection error:nil];
        [collectionEntries addObject:@{@"collection": collection, @"count": @(count)}];
    }

    // Storage: cheap PRAGMA
    int64_t storageBytes = 0;
    NSArray *pageRows = [self.database executeParameterizedQuery:@"PRAGMA page_count" params:@[] error:nil];
    if (pageRows.count > 0 && pageRows[0][@"page_count"] != [NSNull null]) {
        storageBytes = [pageRows[0][@"page_count"] longLongValue] * 4096;
    }

    // Uptime
    NSTimeInterval uptime = -[self.startTime timeIntervalSinceNow];

    // Health: degraded if ingest stopped or backfill has many failures
    NSString *health = @"healthy";
    if (!ingestRunning) health = @"degraded";
    else if (dirty > 1000) health = @"degraded";

    return @{
        @"health":            health,
        @"uptimeSeconds":     @((int64_t)uptime),
        @"ingest": @{
            @"running":     @(ingestRunning),
            @"relayHealth": relayHealth,
            @"lagByRelay":  lagByRelay,
            @"throughput":  throughput,
        },
        @"backfill":  backfill,
        @"indexes":   @{@"collections": collectionEntries},
        @"lexicons":  @{@"count": @(self.configuration.indexCollections.count)},
        @"queries":   metricsDict[@"queries"] ?: @{},
        @"rateLimitRejects": metricsDict[@"rateLimitRejects"] ?: @0,
        @"database":  @{@"storageBytes": @(storageBytes)},
        @"config": @{
            @"relayURLs":        self.configuration.relayURLs ?: @[],
            @"backfillEnabled":  @(self.configuration.backfillEnabled),
            @"partialEnabled":   @(self.configuration.partialEnabled),
        },
    };
}

@end
