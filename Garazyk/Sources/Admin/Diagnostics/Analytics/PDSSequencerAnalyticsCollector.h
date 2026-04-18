#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;
@class SubscribeReposHandler;
@class PDSMetrics;

/**
 * @class PDSSequencerAnalyticsCollector
 * @brief Collects and stores sequencer health metrics at regular intervals.
 *
 * Periodically queries sequencer state and stores snapshots in the
 * sequencer_analytics table for historical analysis and visualization.
 */
@interface PDSSequencerAnalyticsCollector : NSObject

/**
 * @brief Initialize with required dependencies.
 *
 * @param serviceDatabases Service database instance for schema and queries
 * @param subscribeHandler Subscribe handler for current subscriber count
 * @return Initialized collector instance
 */
- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                         subscribeHandler:(SubscribeReposHandler *)subscribeHandler;

/**
 * @brief Start periodic metric collection.
 *
 * Begins collecting metrics every 60 seconds. Safe to call multiple times.
 */
- (void)startCollecting;

/**
 * @brief Stop periodic metric collection.
 *
 * Safe to call if not currently collecting.
 */
- (void)stopCollecting;

/**
 * @brief Get the current sequencer metrics snapshot.
 *
 * @return Dictionary with keys: currentSeq, eventsPerSecond, subscriberCount,
 *         backpressureWarnings, backpressureCritical, queueOverflows,
 *         eventTypes (JSON string), healthStatus
 */
- (nullable NSDictionary *)currentSnapshot;

/**
 * @brief Get historical metrics since timestamp.
 *
 * @param timestamp Unix timestamp (seconds since epoch)
 * @param limit Maximum number of records to return
 * @return Array of snapshot dictionaries sorted by timestamp ascending
 */
- (nullable NSArray<NSDictionary *> *)historicalDataSince:(NSTimeInterval)timestamp
                                                   limit:(NSInteger)limit;

/**
 * @brief Get hourly aggregated metrics for the past N days.
 *
 * @param days Number of days of history to return
 * @return Array of hourly aggregated snapshots
 */
- (nullable NSArray<NSDictionary *> *)hourlyDataForPastDays:(NSInteger)days;

/**
 * @brief Prune analytics data older than retention period.
 *
 * @param retentionDays Keep data from the past N days
 * @param error Output parameter for errors
 * @return YES if successful, NO on error
 */
- (BOOL)pruneOlderThan:(NSInteger)retentionDays error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
