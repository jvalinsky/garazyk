// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSequencerAnalyticsCollector.h"
#import "Database/Service/ServiceDatabases.h"
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Metrics/PDSMetrics.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"
#import <sqlite3.h>

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
    // Capture self strongly - dispatch_source and timer handler will extend lifetime
    // stopCollecting must be called to cancel timer and release this reference
    dispatch_async(self.queue, ^{
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
        PDS_LOG_DB_INFO(@"Sequencer analytics collector started");
    });
}

- (void)stopCollecting {
    dispatch_sync(self.queue, ^{
        if (self.timer) {
            dispatch_source_cancel(self.timer);
            self.timer = nil;
            self.isCollecting = NO;
            PDS_LOG_DB_INFO(@"Sequencer analytics collector stopped");
        }
    });
}

- (void)collectMetrics {
    NSError *error = nil;

    // Get current sequence
    int64_t currentSeq = [self.serviceDatabases getMaxEventSequence:&error];
    if (error) {
        PDS_LOG_DB_ERROR(@"Failed to get max sequence: %@", error);
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
    PDSMetrics *metrics = [PDSMetrics sharedMetrics];
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
        PDS_LOG_DB_ERROR(@"Failed to insert analytics snapshot: %@", error);
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
    sqlite3 *db = [self.serviceDatabases serviceDatabase];
    if (!db) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        return NO;
    }

    NSString *sql = @"INSERT INTO sequencer_analytics "
                    @"(timestamp, seq_number, events_per_second, subscriber_count, "
                    @"backpressure_warnings, backpressure_critical, queue_overflows, "
                    @"event_type_distribution, created_at) "
                    @"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                         code:sqlite3_extended_errcode(db)
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Prepare failed: %s", sqlite3_errmsg(db)]}];
        }
        return NO;
    }

    sqlite3_bind_int64(stmt, 1, [snapshot[@"timestamp"] longValue]);
    sqlite3_bind_int64(stmt, 2, [snapshot[@"seq_number"] longLongValue]);
    sqlite3_bind_double(stmt, 3, [snapshot[@"events_per_second"] doubleValue]);
    sqlite3_bind_int64(stmt, 4, [snapshot[@"subscriber_count"] longLongValue]);
    sqlite3_bind_int64(stmt, 5, [snapshot[@"backpressure_warnings"] longLongValue]);
    sqlite3_bind_int64(stmt, 6, [snapshot[@"backpressure_critical"] longLongValue]);
    sqlite3_bind_int64(stmt, 7, [snapshot[@"queue_overflows"] longLongValue]);
    sqlite3_bind_text(stmt, 8, [snapshot[@"event_type_distribution"] UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 9, (long)[[NSDate date] timeIntervalSince1970]);

    BOOL success = sqlite3_step(stmt) == SQLITE_DONE;
    sqlite3_finalize(stmt);

    if (!success && error) {
        *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                     code:sqlite3_extended_errcode(db)
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(db)]}];
    }

    return success;
}

- (nullable NSDictionary *)currentSnapshot {
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
        PDSMetrics *metrics = [PDSMetrics sharedMetrics];

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
    sqlite3 *db = [self.serviceDatabases serviceDatabase];
    if (!db) return nil;

    NSString *sql = @"SELECT timestamp, seq_number, events_per_second, subscriber_count, "
                    @"backpressure_warnings, backpressure_critical, queue_overflows "
                    @"FROM sequencer_analytics "
                    @"WHERE timestamp >= ? "
                    @"ORDER BY timestamp ASC "
                    @"LIMIT ?";

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        return nil;
    }

    sqlite3_bind_int64(stmt, 1, (long)timestamp);
    sqlite3_bind_int64(stmt, 2, limit);

    NSMutableArray *results = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSDictionary *row = @{
            @"timestamp": @(sqlite3_column_int64(stmt, 0)),
            @"seq": @(sqlite3_column_int64(stmt, 1)),
            @"eventsPerSecond": @(sqlite3_column_double(stmt, 2)),
            @"subscriberCount": @(sqlite3_column_int64(stmt, 3)),
            @"backpressureWarnings": @(sqlite3_column_int64(stmt, 4)),
            @"backpressureCritical": @(sqlite3_column_int64(stmt, 5)),
            @"queueOverflows": @(sqlite3_column_int64(stmt, 6))
        };
        [results addObject:row];
    }

    sqlite3_finalize(stmt);
    return results.count > 0 ? results : nil;
}

- (nullable NSArray<NSDictionary *> *)hourlyDataForPastDays:(NSInteger)days {
    sqlite3 *db = [self.serviceDatabases serviceDatabase];
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

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        return nil;
    }

    sqlite3_bind_int64(stmt, 1, (long)cutoff);

    NSMutableArray *results = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSDictionary *row = @{
            @"hour": @(sqlite3_column_int64(stmt, 0)),
            @"avgEventsPerSecond": @(sqlite3_column_double(stmt, 1)),
            @"avgSubscribers": @(sqlite3_column_double(stmt, 2)),
            @"totalWarnings": @(sqlite3_column_int64(stmt, 3))
        };
        [results addObject:row];
    }

    sqlite3_finalize(stmt);
    return results.count > 0 ? results : nil;
}

- (BOOL)pruneOlderThan:(NSInteger)retentionDays error:(NSError **)error {
    sqlite3 *db = [self.serviceDatabases serviceDatabase];
    if (!db) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        return NO;
    }

    NSTimeInterval cutoff = [NSDate timeIntervalSinceReferenceDate] - (retentionDays * 24 * 3600);

    NSString *sql = @"DELETE FROM sequencer_analytics WHERE timestamp < ?";

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.diagnostics"
                                         code:sqlite3_extended_errcode(db)
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(db)]}];
        }
        return NO;
    }

    sqlite3_bind_int64(stmt, 1, (long)cutoff);
    BOOL success = sqlite3_step(stmt) == SQLITE_DONE;
    sqlite3_finalize(stmt);

    return success;
}

- (void)dealloc {
    [self stopCollecting];
}

@end
