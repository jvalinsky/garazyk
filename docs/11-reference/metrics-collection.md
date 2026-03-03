# Metrics Collection

This guide covers the metrics collection system in September PDS, including the `PDSMetrics` class, custom metrics, and Prometheus-compatible export.

## Overview

September PDS includes a built-in metrics collection system that tracks server performance, resource usage, and operational statistics. The metrics system is designed to be:

- **Thread-safe**: Uses `os_unfair_lock` for efficient concurrent access
- **Prometheus-compatible**: Exports metrics in Prometheus text format
- **Lightweight**: Minimal overhead on request processing
- **Extensible**: Easy to add custom metrics

**Current Implementation Status**: The `PDSMetrics` class exists and provides Prometheus-compatible metrics export, but is not yet fully integrated into the request processing pipeline. Database pool metrics are actively collected through the `DatabasePool.collectMetrics` pattern. HTTP request metrics recording needs to be added to the network layer.

### Architecture Diagram

![Metrics Collection Architecture](../12-diagrams/metrics-collection-architecture.svg)

The diagram above illustrates the complete metrics collection flow in September PDS:
- **Metrics Sources**: HTTP server, database pools, services, and PDSController
- **Central Collection**: PDSMetrics singleton with thread-safe storage
- **Export Layer**: Prometheus text format and JSON via admin API
- **Monitoring Systems**: Prometheus, Grafana, and custom monitoring tools

## PDSMetrics Class

The `PDSMetrics` class provides centralized metrics collection through a singleton pattern.

### Accessing the Metrics Instance

```objc
// Get the shared metrics instance
PDSMetrics *metrics = [PDSMetrics sharedMetrics];
```

*Source: [ATProtoPDS/Sources/Metrics/PDSMetrics.h](../../ATProtoPDS/Sources/Metrics/PDSMetrics.h)*

### Built-in Metrics

September PDS tracks the following metrics out of the box:

#### HTTP Request Metrics

- **`httpRequestsTotal`**: Total number of HTTP requests processed
- **Per-method counters**: Requests broken down by HTTP method (GET, POST, etc.)
- **Per-endpoint counters**: Requests broken down by XRPC endpoint
- **Per-status counters**: Responses broken down by HTTP status code

```objc
// Record an HTTP request
[metrics incrementHttpRequestsForMethod:@"GET" 
                              endpoint:@"/xrpc/com.atproto.repo.getRecord" 
                                status:200];
```

*Source: [ATProtoPDS/Sources/Metrics/PDSMetrics.m](../../ATProtoPDS/Sources/Metrics/PDSMetrics.m#L44-L56)*

#### Repository Metrics

- **`repositoryCount`**: Current total number of repositories
- **`blobCount`**: Current total number of blobs
- **`blobStorageBytes`**: Total bytes used by blob storage

```objc
// Increment repository count when creating a new repository
[metrics incrementRepositoryCount];

// Increment blob count and storage when uploading a blob
[metrics incrementBlobCount];
[metrics addBlobBytes:blobSize];
```

*Source: [ATProtoPDS/Sources/Metrics/PDSMetrics.m](../../ATProtoPDS/Sources/Metrics/PDSMetrics.m#L58-L72)*

#### System Metrics

- **`databaseSizeBytes`**: Current size of the SQLite database
- **`activeConnections`**: Current number of active network connections

```objc
// Update system metrics
[metrics setDatabaseSize:dbFileSize];
[metrics setActiveConnections:connectionCount];
```

*Source: [ATProtoPDS/Sources/Metrics/PDSMetrics.m](../../ATProtoPDS/Sources/Metrics/PDSMetrics.m#L74-L84)*

## Prometheus Export

The metrics system exports data in Prometheus text format, which can be scraped by Prometheus or compatible monitoring systems.

### Export Format

```objc
NSString *prometheusOutput = [metrics exportPrometheus];
```

The output follows the Prometheus exposition format:

```
# HELP pds_http_requests_total Total HTTP requests
# TYPE pds_http_requests_total counter
pds_http_requests_total{method="get"} 1234
pds_http_requests_total{method="post"} 567

# HELP pds_http_requests_by_endpoint Total HTTP requests by endpoint
# TYPE pds_http_requests_by_endpoint counter
pds_http_requests_by_endpoint{endpoint="com.atproto.repo.getRecord"} 890
pds_http_requests_by_endpoint{endpoint="com.atproto.server.createSession"} 123

# HELP pds_http_responses_total Total HTTP responses by status code
# TYPE pds_http_responses_total counter
pds_http_responses_total{status="200"} 1100
pds_http_responses_total{status="400"} 50
pds_http_responses_total{status="500"} 5

# HELP pds_repository_count Total number of repositories
# TYPE pds_repository_count gauge
pds_repository_count 42

# HELP pds_blob_count Total number of blobs
# TYPE pds_blob_count gauge
pds_blob_count 156

# HELP pds_blob_storage_bytes Total blob storage used
# TYPE pds_blob_storage_bytes gauge
pds_blob_storage_bytes 10485760

# HELP pds_database_size_bytes Size of database file
# TYPE pds_database_size_bytes gauge
pds_database_size_bytes 52428800

# HELP pds_active_connections Current active connections
# TYPE pds_active_connections gauge
pds_active_connections 8
```

*Source: [ATProtoPDS/Sources/Metrics/PDSMetrics.m](../../ATProtoPDS/Sources/Metrics/PDSMetrics.m#L86-L133)*

### Metrics Endpoint

The metrics are exposed via the admin API endpoint, which supports both Prometheus text format and JSON:

```objc
- (NSString *)handleAdminMetrics:(NSDictionary *)headers body:(NSData *)body {
    NSString *accept = headers[@"Accept"] ?: headers[@"accept"] ?: @"";
    PDSMetrics *metrics = [PDSMetrics sharedMetrics];

    if ([accept containsString:@"text/plain"] || [accept containsString:@"*/*"]) {
        return [self textResponseWithStatus:200 body:[metrics exportPrometheus]];
    }

    return [self jsonResponseWithStatus:200 body:@{
        @"http_requests_total": @([[PDSMetrics sharedMetrics] httpRequestsTotal]),
        @"repository_count": @([[PDSMetrics sharedMetrics] repositoryCount]),
        @"blob_count": @([[PDSMetrics sharedMetrics] blobCount]),
        @"blob_storage_bytes": @([[PDSMetrics sharedMetrics] blobStorageBytes]),
        @"active_connections": @([[PDSMetrics sharedMetrics] activeConnections])
    }];
}
```

*Source: [ATProtoPDS/Sources/Admin/PDSAdminHandler.m](../../ATProtoPDS/Sources/Admin/PDSAdminHandler.m#L308-L323)*

This handler:
- Checks the `Accept` header to determine response format
- Returns Prometheus text format for monitoring systems
- Returns JSON format for programmatic access
- Provides access to all tracked metrics

### Accessing Metrics

```bash
# Access metrics endpoint (requires admin authentication)
curl -H "Authorization: Bearer <admin-token>" \
     https://pds.example.com/_pds/admin/metrics
```

*Source: [ATProtoPDS/Sources/Admin/PDSAdminHandler.m](../../ATProtoPDS/Sources/Admin/PDSAdminHandler.m#L308-L323)*

## Application-Level Metrics Integration

### PDSController Metrics

The `PDSController` class provides a high-level metrics interface that aggregates metrics from various subsystems:

```objc
- (NSDictionary<NSString *, id> *)getMetrics {
  return @{
    @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
    @"user_databases" : [_userDatabasePool collectMetrics] ?: @{},
    @"service_databases" : @{}
  };
}
```

*Source: [ATProtoPDS/Sources/App/PDSController.m](../../ATProtoPDS/Sources/App/PDSController.m#L953-L960)*

This method is called by the admin API to provide operational metrics about the PDS instance.

### Database Pool Metrics

The `DatabasePool` class tracks connection pool statistics and per-database metrics:

```objc
- (NSDictionary<NSString *, id> *)collectMetrics {
    __block NSDictionary *metrics = nil;
    
    dispatch_sync(self.poolQueue, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        m[@"max_size"] = @(self.maxSize);
        m[@"current_size"] = @(self.stores.count);
        m[@"open_file_handles"] = @(self.openFileHandleCount);
        
        NSMutableDictionary *stores = [NSMutableDictionary dictionary];
        for (NSString *did in self.stores) {
            PDSActorStore *store = self.stores[did];
            NSDate *lastAccess = self.lastAccessTime[did];
            stores[did] = @{
                @"is_open": @(store.isOpen),
                @"db_path": store.dbPath ?: @"",
                @"last_access": lastAccess ?: [NSDate distantPast]
            };
        }
        m[@"stores"] = stores;
        
        metrics = [m copy];
    });
    
    return metrics;
}
```

*Source: [ATProtoPDS/Sources/Database/Pool/DatabasePool.m](../../ATProtoPDS/Sources/Database/Pool/DatabasePool.m#L321-L346)*

This provides visibility into:
- **Pool capacity**: Maximum and current pool size
- **Resource usage**: Number of open file handles
- **Per-database stats**: Open status, file path, last access time

### Health Check Metrics

The `PDSHealthCheck` class aggregates metrics from all database pools:

```objc
- (NSDictionary<NSString *, id> *)collectMetrics {
    NSMutableDictionary *metrics = [NSMutableDictionary dictionary];
    
    metrics[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    
    PDSServiceDatabases *serviceDb = [PDSServiceDatabases sharedInstance];
    
    metrics[@"service_pool"] = [serviceDb.servicePool collectMetrics];
    metrics[@"did_cache_pool"] = [serviceDb.didCachePool collectMetrics];
    metrics[@"sequencer_pool"] = [serviceDb.sequencerPool collectMetrics];
    
    metrics[@"warnings"] = [self getWarnings];
    metrics[@"errors"] = [self getErrors];
    
    return metrics;
}
```

*Source: [ATProtoPDS/Sources/Database/Monitoring/PDSHealthCheck.m](../../ATProtoPDS/Sources/Database/Monitoring/PDSHealthCheck.m#L190-L205)*

This provides a comprehensive view of all database subsystems and their health status.

## Custom Metrics

You can extend the metrics system to track custom application-specific metrics.

### Adding a New Counter

1. Add a property to `PDSMetrics.h`:

```objc
@property (nonatomic, assign) NSInteger customEventCount;
```

2. Add an increment method:

```objc
- (void)incrementCustomEventCount;
```

3. Implement the method in `PDSMetrics.m`:

```objc
- (void)incrementCustomEventCount {
    os_unfair_lock_lock(&_lock);
    _customEventCount++;
    os_unfair_lock_unlock(&_lock);
}
```

4. Add export logic to `exportPrometheus`:

```objc
[output appendString:@"\n# HELP pds_custom_events_total Total custom events\n"];
[output appendString:@"# TYPE pds_custom_events_total counter\n"];
[output appendFormat:@"pds_custom_events_total %ld\n", (long)_customEventCount];
```

### Adding Labeled Metrics

For metrics with multiple dimensions, use dictionaries:

```objc
@interface PDSMetrics ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *customMetricsByLabel;
@end

- (void)incrementCustomMetric:(NSString *)label {
    os_unfair_lock_lock(&_lock);
    NSString *key = [NSString stringWithFormat:@"custom_%@", label];
    _customMetricsByLabel[key] = @(_customMetricsByLabel[key].integerValue + 1);
    os_unfair_lock_unlock(&_lock);
}
```

## Thread Safety

All metrics operations are protected by `os_unfair_lock`, which provides:

- **Low overhead**: Faster than `NSLock` or `@synchronized`
- **Priority inversion avoidance**: Better than spinlocks for user-space code
- **Fairness**: Prevents starvation under contention

```objc
- (void)incrementRepositoryCount {
    os_unfair_lock_lock(&_lock);
    _repositoryCount++;
    os_unfair_lock_unlock(&_lock);
}
```

*Source: [ATProtoPDS/Sources/Metrics/PDSMetrics.m](../../ATProtoPDS/Sources/Metrics/PDSMetrics.m#L58-L62)*

**Note**: `os_unfair_lock` is macOS-only. On Linux/GNUstep, the metrics system uses a stub implementation.

## Integration with Monitoring Systems

### Prometheus

Configure Prometheus to scrape the metrics endpoint:

```yaml
scrape_configs:
  - job_name: 'september-pds'
    scheme: https
    authorization:
      credentials: '<admin-token>'
    static_configs:
      - targets: ['pds.example.com']
    metrics_path: '/_pds/admin/metrics'
    scrape_interval: 15s
```

### Grafana

Create dashboards using Prometheus as a data source:

- **Request Rate**: `rate(pds_http_requests_total[5m])`
- **Error Rate**: `rate(pds_http_responses_total{status=~"5.."}[5m])`
- **Repository Growth**: `pds_repository_count`
- **Storage Usage**: `pds_blob_storage_bytes`

## Best Practices

### Implementing Metrics in Your Code

To add metrics collection to a new component, follow the `DatabasePool` pattern:

1. **Add a collectMetrics method** that returns a dictionary:

```objc
- (NSDictionary<NSString *, id> *)collectMetrics {
    NSMutableDictionary *metrics = [NSMutableDictionary dictionary];
    
    // Add your metrics
    metrics[@"total_items"] = @(self.itemCount);
    metrics[@"active_items"] = @(self.activeCount);
    metrics[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    
    return metrics;
}
```

2. **Use thread-safe access** if your component is accessed concurrently:

```objc
- (NSDictionary<NSString *, id> *)collectMetrics {
    __block NSDictionary *metrics = nil;
    
    dispatch_sync(self.queue, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        m[@"count"] = @(self.internalCount);
        metrics = [m copy];
    });
    
    return metrics;
}
```

3. **Aggregate metrics** from child components:

```objc
- (NSDictionary<NSString *, id> *)collectMetrics {
    NSMutableDictionary *metrics = [NSMutableDictionary dictionary];
    
    metrics[@"component_a"] = [self.componentA collectMetrics];
    metrics[@"component_b"] = [self.componentB collectMetrics];
    
    return metrics;
}
```

*Pattern based on: [ATProtoPDS/Sources/Database/Pool/DatabasePool.m](../../ATProtoPDS/Sources/Database/Pool/DatabasePool.m#L321-L346)*

### When to Record Metrics

- **Request handling**: Record at the HTTP server level for consistency
- **Resource creation**: Increment counters when repositories/blobs are created
- **Periodic updates**: Update gauges (database size, connections) on a schedule

### Performance Considerations

- **Minimize lock contention**: Keep critical sections short
- **Batch updates**: If recording many metrics, consider batching
- **Avoid blocking**: Never perform I/O while holding the metrics lock

### Metric Naming

Follow Prometheus naming conventions:

- Use `_total` suffix for counters: `pds_http_requests_total`
- Use descriptive names: `pds_blob_storage_bytes` not `pds_blobs`
- Use consistent units: `_bytes`, `_seconds`, `_count`
- Use labels for dimensions: `{method="get"}` not separate metrics

## Testing

Test metrics collection in unit tests:

```objc
- (void)testMetricsCollection {
    PDSMetrics *metrics = [[PDSMetrics alloc] init];
    
    // Record some metrics
    [metrics incrementHttpRequestsForMethod:@"GET" 
                                  endpoint:@"/xrpc/com.atproto.repo.getRecord" 
                                    status:200];
    [metrics incrementRepositoryCount];
    
    // Verify export
    NSString *output = [metrics exportPrometheus];
    XCTAssertTrue([output containsString:@"pds_http_requests_total{method=\"get\"}"]);
    XCTAssertTrue([output containsString:@"pds_repository_count 1"]);
}
```

*Source: [ATProtoPDS/Tests/Metrics/PDSMetricsTests.m](../../ATProtoPDS/Tests/Metrics/PDSMetricsTests.m#L12-L28)*

## Related Documentation

- [Logging Strategy](logging-strategy.md) - Structured logging and log levels
- [Performance Monitoring](performance-monitoring.md) - Profiling and optimization
- [Alerting](alerting.md) - Setting up alerts based on metrics

## See Also

- [Prometheus Documentation](https://prometheus.io/docs/introduction/overview/)
- [Prometheus Exposition Format](https://prometheus.io/docs/instrumenting/exposition_formats/)
