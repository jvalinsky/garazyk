// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSequencerAnalyticsCollector.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Metrics/GZMetrics.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"

static void PDSSequencerAnalyticsSetServiceDatabaseUnavailableError(NSError **error) {
    if (error && !*error) {
        *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                     code:-1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
    }
}

@interface PDSSequencerAnalyticsCollector ()
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, weak) SubscribeReposHandler *subscribeHandler;
@property (nonatomic, PDS_GCD_STRONG) dispatch_source_t timer;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@property (nonatomic) int64_t lastSeq;
@property (nonatomic) NSTimeInterval lastTimestamp;
@property (nonatomic) NSInteger lastWarnings;
@property (nonatomic) NSInteger lastCritical;
@property (nonatomic) NSInteger lastOverflows;
@property (nonatomic, assign, readwrite) BOOL isCollecting;
@end

@implementation PDSSequencerAnalyticsCollector

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                         subscribeHandler:(SubscribeReposHandler *)subscribeHandler {
    if ((self = [super init])) {
        _serviceDatabases = serviceDatabases;
        _subscribeHandler = subscribeHandler;
        _queue = dispatch_queue_create("com.atproto.pds.diagnostics.analytics", DISPATCH_QUEUE_SERIAL);
        _lastSeq = 0;
        _lastTimestamp = 0;
        _lastWarnings = 0;
        _lastCritical = 0;
        _lastOverflows = 0;
    }
    return self;
}

- (void)startCollecting {
    // Synchronous so isCollecting is accurate to the caller as soon as this
    // returns; self.queue is a private queue only this class dispatches to,
    // so there is no reentrancy/deadlock risk.
    dispatch_sync(self.queue, ^{
        if (self.timer) {
            return; // Already collecting
        }

        self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
        dispatch_source_set_timer(self.timer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                                   60 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);

        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(self.timer, ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf collectMetrics];
            }
        });

        dispatch_resume(self.timer);
        self.isCollecting = YES;
        GZ_LOG_DB_INFO(@"Sequencer analytics collector started");
    });
}

- (void)stopCollecting {
    dispatch_sync(self.queue, ^{
        if (self.timer) {
            dispatch_source_cancel(self.timer);
            self.timer = nil;
            self.isCollecting = NO;
            GZ_LOG_DB_INFO(@"Sequencer analytics collector stopped");
        }
    });
}

- (void)collectMetrics {
    NSError *error = nil;

    // Get current sequence
    int64_t currentSeq = [self.serviceDatabases getMaxEventSequence:&error];
    if (error) {
        GZ_LOG_DB_ERROR(@"Failed to get max sequence: %@", error);
        return;
    }

    // Calculate events per second
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    double eventsPerSecond = 0;
    if (self.lastTimestamp > 0) {
        NSTimeInterval delta = now - self.lastTimestamp;
        if (delta > 0) {
            eventsPerSecond = (double)(currentSeq - self.lastSeq) / delta;
        }
    }

    // Get subscriber count - capture weak reference strongly
    SubscribeReposHandler *strongHandler = self.subscribeHandler;
    NSInteger subscriberCount = strongHandler.attachedConnections.count;

    // Get backpressure metrics
    GZMetrics *metrics = [GZMetrics sharedMetrics];
    NSInteger warnings = metrics.websocketBackpressureWarningsTotal;
    NSInteger critical = metrics.websocketBackpressureCriticalTotal;
    NSInteger overflows = metrics.websocketQueueOverflowClosuresTotal;

    // Calculate deltas
    NSInteger warningsDelta = warnings - self.lastWarnings;
    NSInteger criticalDelta = critical - self.lastCritical;
    NSInteger overflowsDelta = overflows - self.lastOverflows;

    // Determine health status
    NSString *healthStatus = @"healthy";
    if (criticalDelta > 0) {
        healthStatus = @"critical";
    } else if (warningsDelta > 0) {
        healthStatus = @"warning";
    }

    // Get event type distribution (simplified)
    NSString *eventTypeDistribution = @"{}";

    // Insert into database
    BOOL success = [self insertAnalyticsSnapshot:@{
        @"timestamp": @((long)now),
        @"seq_number": @(currentSeq),
        @"events_per_second": @(eventsPerSecond),
        @"subscriber_count": @(subscriberCount),
        @"backpressure_warnings": @(warningsDelta),
        @"backpressure_critical": @(criticalDelta),
        @"queue_overflows": @(overflowsDelta),
        @"event_type_distribution": eventTypeDistribution,
        @"health_status": healthStatus
    } error:&error];

    if (!success) {
        GZ_LOG_DB_ERROR(@"Failed to insert analytics snapshot: %@", error);
        return;
    }

    // Update tracking variables
    self.lastSeq = currentSeq;
    self.lastTimestamp = now;
    self.lastWarnings = warnings;
    self.lastCritical = critical;
    self.lastOverflows = overflows;
}

- (BOOL)insertAnalyticsSnapshot:(NSDictionary *)snapshot error:(NSError **)error {
    NSString *sql = @"INSERT INTO sequencer_analytics "
                    @"(timestamp, seq_number, events_per_second, subscriber_count, "
                    @"backpressure_warnings, backpressure_critical, queue_overflows, "
                    @"event_type_distribution, created_at) "
                    @"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

    PDSDatabase *database = [self.serviceDatabases serviceDatabaseWithError:error];
    if (!database) {
        PDSSequencerAnalyticsSetServiceDatabaseUnavailableError(error);
        return NO;
    }
    return [database executeParameterizedUpdate:sql
                                         params:@[
                                             snapshot[@"timestamp"],
                                             snapshot[@"seq_number"],
                                             snapshot[@"events_per_second"],
                                             snapshot[@"subscriber_count"],
                                             snapshot[@"backpressure_warnings"],
                                             snapshot[@"backpressure_critical"],
                                             snapshot[@"queue_overflows"],
                                             snapshot[@"event_type_distribution"],
                                             @((long)[[NSDate date] timeIntervalSince1970])
                                         ]
                                          error:error];
}

- (nullable NSDictionary *)currentSnapshot {
    if (!self.serviceDatabases) return nil;

    __block NSDictionary *snapshot = nil;
    __weak typeof(self) weakSelf = self;

    dispatch_sync(self.queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        NSError *error = nil;
        int64_t currentSeq = [strongSelf.serviceDatabases getMaxEventSequence:&error];
        if (error) return;

        SubscribeReposHandler *strongHandler = strongSelf.subscribeHandler;
        NSInteger subscriberCount = strongHandler.attachedConnections.count;
        GZMetrics *metrics = [GZMetrics sharedMetrics];

        snapshot = @{
            @"currentSeq": @(currentSeq),
            @"eventsPerSecond": @(0), // Would need delta calculation
            @"subscriberCount": @(subscriberCount),
            @"backpressureWarnings": @(metrics.websocketBackpressureWarningsTotal),
            @"backpressureCritical": @(metrics.websocketBackpressureCriticalTotal),
            @"queueOverflows": @(metrics.websocketQueueOverflowClosuresTotal),
            @"healthStatus": metrics.websocketBackpressureCriticalTotal > 0 ? @"critical" : @"healthy"
        };
    });

    return snapshot;
}

- (nullable NSArray<NSDictionary *> *)historicalDataSince:(NSTimeInterval)timestamp
                                                   limit:(NSInteger)limit {
    NSError *error = nil;
    PDSDatabase *database = [self.serviceDatabases serviceDatabaseWithError:&error];
    if (!database) return nil;

    NSString *sql = @"SELECT timestamp, seq_number, events_per_second, subscriber_count, "
                    @"backpressure_warnings, backpressure_critical, queue_overflows "
                    @"FROM sequencer_analytics "
                    @"WHERE timestamp >= ? "
                    @"ORDER BY timestamp ASC "
                    @"LIMIT ?";

    NSArray<NSDictionary *> *rows = [database executeParameterizedQuery:sql
                                                                   params:@[@((long)timestamp), @(limit)]
                                                                    error:&error];
    if (error) return nil;
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *sourceRow in rows) {
        NSDictionary *row = @{
            @"timestamp": sourceRow[@"timestamp"] ?: @0,
            @"seq": sourceRow[@"seq_number"] ?: @0,
            @"eventsPerSecond": sourceRow[@"events_per_second"] ?: @0,
            @"subscriberCount": sourceRow[@"subscriber_count"] ?: @0,
            @"backpressureWarnings": sourceRow[@"backpressure_warnings"] ?: @0,
            @"backpressureCritical": sourceRow[@"backpressure_critical"] ?: @0,
            @"queueOverflows": sourceRow[@"queue_overflows"] ?: @0
        };
        [results addObject:row];
    }
    return results.count > 0 ? results : nil;
}

- (nullable NSArray<NSDictionary *> *)hourlyDataForPastDays:(NSInteger)days {
    NSError *error = nil;
    PDSDatabase *database = [self.serviceDatabases serviceDatabaseWithError:&error];
    if (!database) return nil;

    NSTimeInterval cutoff = [NSDate timeIntervalSinceReferenceDate] - (days * 24 * 3600);

    NSString *sql = @"SELECT "
                    @"  CAST(timestamp / 3600 AS INTEGER) * 3600 AS hour, "
                    @"  AVG(events_per_second) AS avg_eps, "
                    @"  AVG(subscriber_count) AS avg_subs, "
                    @"  SUM(backpressure_warnings) AS total_warnings "
                    @"FROM sequencer_analytics "
                    @"WHERE timestamp >= ? "
                    @"GROUP BY hour "
                    @"ORDER BY hour ASC";

    NSArray<NSDictionary *> *rows = [database executeParameterizedQuery:sql
                                                                   params:@[@((long)cutoff)]
                                                                    error:&error];
    if (error) return nil;
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *sourceRow in rows) {
        NSDictionary *row = @{
            @"hour": sourceRow[@"hour"] ?: @0,
            @"avgEventsPerSecond": sourceRow[@"avg_eps"] ?: @0,
            @"avgSubscribers": sourceRow[@"avg_subs"] ?: @0,
            @"totalWarnings": sourceRow[@"total_warnings"] ?: @0
        };
        [results addObject:row];
    }
    return results.count > 0 ? results : nil;
}

- (BOOL)pruneOlderThan:(NSInteger)retentionDays error:(NSError **)error {
    PDSDatabase *database = [self.serviceDatabases serviceDatabaseWithError:error];
    if (!database) {
        PDSSequencerAnalyticsSetServiceDatabaseUnavailableError(error);
        return NO;
    }

    NSTimeInterval cutoff = [NSDate timeIntervalSinceReferenceDate] - (retentionDays * 24 * 3600);

    NSString *sql = @"DELETE FROM sequencer_analytics WHERE timestamp < ?";

    return [database executeParameterizedUpdate:sql
                                         params:@[@((long)cutoff)]
                                          error:error];
}

- (void)dealloc {
    [self stopCollecting];
}

@end
