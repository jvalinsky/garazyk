// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
  @file PDSMetrics.h
  @brief Prometheus metrics collection and export for the ATProto PDS server.
  */


/**
 * @abstract Declares the PDSMetrics public API.
 */
@interface PDSMetrics : NSObject

/**
 * @brief Returns the shared singleton instance for metrics collection.
 *
 * @return The shared PDSMetrics instance.
 */
+ (instancetype)sharedMetrics;

/**
 * @brief Total number of HTTP requests processed since server startup.
 *
 * This counter tracks all HTTP requests regardless of endpoint or response status.
 */
@property (nonatomic, assign) NSInteger httpRequestsTotal;

/**
 * @brief Current total number of repositories stored in the PDS.
 *
 * This value represents the count of user repositories currently managed by the server.
 */
@property (nonatomic, assign) NSInteger repositoryCount;

/**
 * @brief Current total number of blobs stored in the PDS.
 *
 * This value represents the total count of blob records in the blob storage system.
 */
@property (nonatomic, assign) NSInteger blobCount;

/**
 * @brief Total bytes currently used by blob storage.
 *
 * This value represents the cumulative size of all stored blobs in bytes.
 */
@property (nonatomic, assign) unsigned long long blobStorageBytes;

/**
 * @brief Total size of the database in bytes.
 *
 * This value represents the current size of the SQLite database file.
 */
@property (nonatomic, assign) unsigned long long databaseSizeBytes;

/**
 * @brief Current number of active network connections.
 *
 * This value tracks the number of concurrent connections currently being handled.
 */
@property (nonatomic, assign) NSInteger activeConnections;

/**
 * @brief Server start time as a Unix timestamp (seconds since epoch).
 */
@property (nonatomic, readonly) NSTimeInterval serverStartTime;

/*!
 * @abstract Records an HTTP request with method, endpoint, and status code.
 *
 * Increments the HTTP request counter for tracking request metrics per
 * endpoint and response status.
 *
 * @param method The HTTP method (e.g., "GET", "POST").
 * @param endpoint The API endpoint path (e.g., "/xrpc/com.atproto.server.createSession").
 * @param status The HTTP response status code (e.g., 200, 400, 500).
 */
- (void)incrementHttpRequestsForMethod:(NSString *)method
                              endpoint:(NSString *)endpoint
                                status:(NSInteger)status;

/*!
 * @abstract Increments the repository count by one.
 *
 * Call when a new repository is created on the PDS.
 */
- (void)incrementRepositoryCount;

/**
 * @brief Increments the blob count by one.
 *
 * Call this method when a new blob is stored in the PDS.
 */
- (void)incrementBlobCount;

/**
 * @brief Adds bytes to the total blob storage counter.
 *
 * @param bytes The number of bytes to add to the blob storage total.
 */
- (void)addBlobBytes:(unsigned long long)bytes;

/**
 * @brief Sets the current number of active connections.
 *
 * @param connections The current number of active network connections.
 */
- (void)setActiveConnections:(NSInteger)connections;

/**
 * @brief Updates the database size metric.
 *
 * @param bytes The current size of the database in bytes.
 */
- (void)setDatabaseSize:(unsigned long long)bytes;

/**
 * @brief Records an HTTP request latency observation for histogram metrics.
 *
 * Increments all histogram buckets where the threshold is >= the observed
 * duration, increments the observation count, and adds to the cumulative sum.
 *
 * @param seconds The request duration in seconds.
 * @param method The HTTP method (e.g., "GET", "POST").
 * @param endpoint The API endpoint path (e.g., "/xrpc/com.atproto.server.createSession").
 * @param status The HTTP response status code.
 */
/**
 * @abstract Performs the observeRequestLatency operation.
 */
- (void)observeRequestLatency:(NSTimeInterval)seconds
                        method:(NSString *)method
                      endpoint:(NSString *)endpoint
                        status:(NSInteger)status;

#pragma mark - Firehose Metrics

/**
 * @brief Sets the current number of firehose subscribers.
 *
 * @param count The current subscriber count.
 */
- (void)setFirehoseSubscribers:(NSInteger)count;

/**
 * @brief Increments the firehose event counter for the given event kind.
 *
 * @param kind The event kind (e.g., "commit", "identity", "account").
 */
- (void)incrementFirehoseEvent:(NSString *)kind;

/**
 * @brief Sets the current firehose sequence number.
 *
 * @param seq The latest sequence number.
 */
- (void)setFirehoseSeq:(int64_t)seq;

#pragma mark - Rate Limiting Metrics

/**
 * @brief Increments the rate limit rejection counter for the given type.
 *
 * @param type The rate limit type (e.g., "did", "ip", "blob").
 */
- (void)incrementRateLimitRejection:(NSString *)type;

#pragma mark - Auth Metrics

/**
 * @brief Increments the auth failure counter for the given reason.
 *
 * @param reason The failure reason (e.g., "invalid_token", "expired", "invalid_issuer").
 */
- (void)incrementAuthFailure:(NSString *)reason;

/**
 * @brief Increments the OAuth token grant counter for the given grant type.
 *
 * @param grantType The grant type (e.g., "authorization_code", "refresh_token").
 */
- (void)incrementOAuthTokenGrant:(NSString *)grantType;

/**
 * @brief Sets the current number of active auth sessions.
 *
 * @param count The current session count.
 */
- (void)setActiveAuthSessions:(NSInteger)count;

#pragma mark - Repository Metrics

/**
 * @brief Increments the total repo commits counter.
 */
- (void)incrementRepoCommits;

#pragma mark - WebSocket Metrics

/**
 * @brief Counter: Total backpressure warning events.
 *
 * Incremented each time a WebSocket connection reaches the warning threshold.
 */
@property (nonatomic, assign) NSInteger websocketBackpressureWarningsTotal;

/**
 * @brief Counter: Total backpressure critical events.
 *
 * Incremented each time a WebSocket connection reaches the critical threshold.
 */
@property (nonatomic, assign) NSInteger websocketBackpressureCriticalTotal;

/**
 * @brief Counter: Total connections closed due to queue overflow.
 *
 * Incremented each time a connection is forcibly closed due to queue overflow.
 */
@property (nonatomic, assign) NSInteger websocketQueueOverflowClosuresTotal;

/**
 * @brief Gauge: Current number of connections under backpressure.
 *
 * Tracks the number of active connections currently experiencing backpressure.
 */
@property (nonatomic, assign) NSInteger websocketConnectionsUnderBackpressure;

/**
 * @brief Records a WebSocket backpressure warning event.
 */
- (void)recordWebSocketBackpressureWarning;

/**
 * @brief Records a WebSocket backpressure critical event.
 */
- (void)recordWebSocketBackpressureCritical;

/**
 * @brief Records a WebSocket queue overflow closure event.
 */
- (void)recordWebSocketQueueOverflowClosure;

/**
 * @brief Updates the count of connections under backpressure.
 *
 * @param isUnderBackpressure YES to increment, NO to decrement.
 */
- (void)recordWebSocketBackpressureStateChange:(BOOL)isUnderBackpressure;

#pragma mark - Account Quota Metrics

/**
 * @brief Increments the quota exceeded counter for the given kind.
 *
 * @param kind The quota kind (e.g., "blob_bytes", "record_count", "repo_bytes").
 */
- (void)incrementQuotaExceeded:(NSString *)kind;

/**
 * @brief Sets the per-account blob bytes gauge.
 *
 * @param did The account DID.
 * @param bytes The blob bytes for this account.
 */
- (void)setAccountBlobBytes:(unsigned long long)bytes forDid:(NSString *)did;

/**
 * @brief Sets the per-account repo bytes gauge.
 *
 * @param did The account DID.
 * @param bytes The repo bytes for this account.
 */
- (void)setAccountRepoBytes:(unsigned long long)bytes forDid:(NSString *)did;

/**
 * @brief Current resident memory usage of the process in bytes.
 */
@property (nonatomic, assign, readonly) unsigned long long residentMemoryBytes;

/**
 * @brief Total physical memory available on the system in bytes.
 */
@property (nonatomic, assign, readonly) unsigned long long totalSystemMemoryBytes;

/**
 * @brief Exports all metrics in Prometheus text format.
 *
 * This method generates a Prometheus-compatible metrics exposition format
 * string that can be served by an HTTP endpoint for Prometheus scraping.
 *
 * @return A string containing all metrics in Prometheus format.
 */
- (NSString *)exportPrometheus;

@end

NS_ASSUME_NONNULL_END
