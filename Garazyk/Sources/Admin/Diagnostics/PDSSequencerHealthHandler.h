#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSSequencerHealthHandler
 * @brief Handles sequencer health diagnostics API endpoints.
 *
 * Provides real-time and historical metrics for sequencer performance monitoring.
 * Metrics are collected every 60 seconds and stored in the sequencer_analytics table.
 *
 * Endpoints:
 * - GET /stats - Current sequencer metrics (real-time snapshot)
 * - GET /history?hours=24 - Historical data for specified period
 *
 * Response Format (GET /stats):
 * {
 *   "seq_number": 12345,
 *   "events_per_second": 125.5,
 *   "subscriber_count": 42,
 *   "backpressure_warnings": 2,
 *   "backpressure_critical": 0,
 *   "queue_overflows": 0,
 *   "timestamp": 1234567890
 * }
 *
 * Response Format (GET /history):
 * {
 *   "data": [
 *     { "timestamp": ..., "seq_number": ..., "events_per_second": ..., ... },
 *     ...
 *   ],
 *   "period_hours": 24
 * }
 */
@interface PDSSequencerHealthHandler : NSObject

/**
 * @brief Returns the shared singleton instance.
 *
 * @return The shared PDSSequencerHealthHandler instance.
 */
+ (instancetype)sharedHandler;

/**
 * @brief Processes sequencer health API requests.
 *
 * Routes to:
 * - GET /stats → Returns current metrics snapshot
 * - GET /history?hours=N → Returns historical data (default: 24 hours)
 *
 * @param method HTTP method (GET only)
 * @param path Request path (e.g., /stats, /history)
 * @param headers HTTP headers
 * @param body Request body (ignored for GET)
 * @param statusCode Output status code (200, 400, 500)
 * @param contentType Output content type (application/json)
 * @return JSON response body or error message
 */
- (nullable NSString *)handleRequestWithMethod:(NSInteger)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType;

@end

NS_ASSUME_NONNULL_END
