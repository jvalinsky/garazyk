#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @file PDSMetrics.h
 * @brief Prometheus metrics collection and export for the ATProto PDS server.
 *
 * This class provides centralized metrics collection for the PDS server,
 * supporting HTTP request tracking, repository and blob counting, and
 * Prometheus-compatible format export.
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
 * @brief Records an HTTP request with method, endpoint, and status code.
 *
 * This method increments the HTTP request counter and can be used to track
 * detailed request metrics per endpoint and response status.
 *
 * @param method The HTTP method (e.g., "GET", "POST").
 * @param endpoint The API endpoint path (e.g., "/xrpc/com.atproto.server.createSession").
 * @param status The HTTP response status code (e.g., 200, 400, 500).
 */
- (void)incrementHttpRequestsForMethod:(NSString *)method
                              endpoint:(NSString *)endpoint
                                status:(NSInteger)status;

/**
 * @brief Increments the repository count by one.
 *
 * Call this method when a new repository is created on the PDS.
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
