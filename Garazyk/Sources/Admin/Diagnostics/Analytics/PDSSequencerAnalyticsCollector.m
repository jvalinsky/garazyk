// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSequencerAnalyticsCollector.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Metrics/GZMetrics.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"

@interface PDSSequencerAnalyticsCollector ()
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, weak) ATProtoSubscribeReposHandler *subscribeHandler;
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

/*!
 The service connection, reached through PDSDatabase so statements run on that
 object's serialized queue. Driving the raw sqlite3 handle from this collector's
 own timer queue races every other user of the same connection.
 */
- (nullable PDSDatabase *)serviceDatabaseWithError:(NSError **)error {
    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:error];
    if (!db && error && !*error) {
        *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                     code:-1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
    }
    return db;
}

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                         subscribeHandler:(ATProtoSubscribeReposHandler *)subscribeHandler {
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
    ATProtoSubscribeReposHandler *strongHandler = self.subscribeHandler;
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
    PDSDatabase *db = [self serviceDatabaseWithError:error];
    if (!db) return NO;

    NSString *sql = @"INSERT INTO sequencer_analytics "
                    @"(timestamp, seq_number, events_per_second, subscriber_count, "
                    @"backpressure_warnings, backpressure_critical, queue_overflows, "
                    @"event_type_distribution, created_at) "
                    @"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

    NSArray *params = @[
        @([snapshot[@"timestamp"] longValue]),
        @([snapshot[@"seq_number"] longLongValue]),
        @([snapshot[@"events_per_second"] doubleValue]),
        @([snapshot[@"subscriber_count"] longLongValue]),
        @([snapshot[@"backpressure_warnings"] longLongValue]),
        @([snapshot[@"backpressure_critical"] longLongValue]),
        @([snapshot[@"queue_overflows"] longLongValue]),
        snapshot[@"event_type_distribution"] ?: [NSNull null],
        @((long long)[[NSDate date] timeIntervalSince1970])
    ];

    return [db executeParameterizedUpdate:sql params:params error:error];
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

        ATProtoSubscribeReposHandler *strongHandler = strongSelf.subscribeHandler;
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
    PDSDatabase *db = [self serviceDatabaseWithError:nil];
    if (!db) return nil;

    NSString *sql = @"SELECT timestamp, seq_number, events_per_second, subscriber_count, "
                    @"backpressure_warnings, backpressure_critical, queue_overflows "
                    @"FROM sequencer_analytics "
                    @"WHERE timestamp >= ? "
                    @"ORDER BY timestamp ASC "
                    @"LIMIT ?";

    NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:sql
                                                           params:@[@((long long)timestamp), @(limit)]
                                                            error:nil];

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        [results addObject:@{
            @"timestamp": @([row[@"timestamp"] longLongValue]),
            @"seq": @([row[@"seq_number"] longLongValue]),
            @"eventsPerSecond": @([row[@"events_per_second"] doubleValue]),
            @"subscriberCount": @([row[@"subscriber_count"] longLongValue]),
            @"backpressureWarnings": @([row[@"backpressure_warnings"] longLongValue]),
            @"backpressureCritical": @([row[@"backpressure_critical"] longLongValue]),
            @"queueOverflows": @([row[@"queue_overflows"] longLongValue])
        }];
    }
    return results.count > 0 ? results : nil;
}

- (nullable NSArray<NSDictionary *> *)hourlyDataForPastDays:(NSInteger)days {
    PDSDatabase *db = [self serviceDatabaseWithError:nil];
    if (!db) return nil;

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

    NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:sql
                                                           params:@[@((long long)cutoff)]
                                                            error:nil];

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        [results addObject:@{
            @"hour": @([row[@"hour"] longLongValue]),
            @"avgEventsPerSecond": @([row[@"avg_eps"] doubleValue]),
            @"avgSubscribers": @([row[@"avg_subs"] doubleValue]),
            @"totalWarnings": @([row[@"total_warnings"] longLongValue])
        }];
    }
    return results.count > 0 ? results : nil;
}

- (BOOL)pruneOlderThan:(NSInteger)retentionDays error:(NSError **)error {
    PDSDatabase *db = [self serviceDatabaseWithError:error];
    if (!db) return NO;

    NSTimeInterval cutoff = [NSDate timeIntervalSinceReferenceDate] - (retentionDays * 24 * 3600);

    return [db executeParameterizedUpdate:@"DELETE FROM sequencer_analytics WHERE timestamp < ?"
                                   params:@[@((long long)cutoff)]
                                    error:error];
}

- (void)dealloc {
    [self stopCollecting];
}

@end
