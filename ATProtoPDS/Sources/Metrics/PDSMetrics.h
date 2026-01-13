#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @header PDSMetrics.h
 
 @abstract Prometheus metrics collection for the PDS.
 
 @discussion This header defines the PDSMetrics class for collecting
 and exporting operational metrics in Prometheus format.
 
 @copyright Copyright (c) 2024 Jack Valinsky
 */

/*!
 @class PDSMetrics
 
 @abstract Collects and exports PDS metrics for monitoring.
 
 @discussion PDSMetrics provides metrics collection for operational
 monitoring. It tracks HTTP requests, repository count, blob storage,
 and other key metrics. The `exportPrometheus` method returns metrics
 in Prometheus text format.
 
 @code
 PDSMetrics *metrics = [PDSMetrics sharedMetrics];
 
 // Track HTTP request
 [metrics incrementHttpRequestsForMethod:@"GET" endpoint:@"/xrpc" status:200];
 
 // Export for Prometheus scraping
 NSString *prometheusOutput = [metrics exportPrometheus];
 @endcode
 */
@interface PDSMetrics : NSObject

/*!
 @method sharedMetrics
 
 @abstract Returns the shared metrics instance.
 
 @return The singleton PDSMetrics instance.
 */
+ (instancetype)sharedMetrics;

/*! Total number of HTTP requests processed. */
@property (nonatomic, assign) NSInteger httpRequestsTotal;

/*! Number of active repositories. */
@property (nonatomic, assign) NSInteger repositoryCount;

/*! Total number of blobs stored. */
@property (nonatomic, assign) NSInteger blobCount;

/*! Total bytes used for blob storage. */
@property (nonatomic, assign) unsigned long long blobStorageBytes;

/*! Size of the database in bytes. */
@property (nonatomic, assign) unsigned long long databaseSizeBytes;

/*! Number of currently active connections. */
@property (nonatomic, assign) NSInteger activeConnections;

/*!
 @method incrementHttpRequestsForMethod:endpoint:status:
 
 @abstract Records an HTTP request metric.
 
 @param method The HTTP method (GET, POST, etc.).
 @param endpoint The endpoint path.
 @param status The HTTP status code.
 */
- (void)incrementHttpRequestsForMethod:(NSString *)method
                             endpoint:(NSString *)endpoint
                               status:(NSInteger)status;

/*!
 @method incrementRepositoryCount
 
 @abstract Increments the repository count by one.
 */
- (void)incrementRepositoryCount;

/*!
 @method incrementBlobCount
 
 @abstract Increments the blob count by one.
 */
- (void)incrementBlobCount;

/*!
 @method addBlobBytes:
 
 @abstract Adds to the total blob storage bytes.
 
 @param bytes The number of bytes to add.
 */
- (void)addBlobBytes:(unsigned long long)bytes;

/*!
 @method setActiveConnections:
 
 @abstract Sets the current active connection count.
 
 @param connections The number of active connections.
 */
- (void)setActiveConnections:(NSInteger)connections;

/*!
 @method setDatabaseSize:
 
 @abstract Sets the current database size.
 
 @param bytes The database size in bytes.
 */
- (void)setDatabaseSize:(unsigned long long)bytes;

/*!
 @method exportPrometheus
 
 @abstract Exports all metrics in Prometheus text format.
 
 @return A string containing all metrics in Prometheus format.
 */
- (NSString *)exportPrometheus;

@end

NS_ASSUME_NONNULL_END
