# Performance Monitoring

This guide covers performance monitoring, profiling, bottleneck detection, and optimization strategies for September PDS.

## Overview

![Performance Monitoring Flow](../12-diagrams/performance-monitoring-flow.svg)

Performance monitoring in September PDS involves:

- **Profiling tools**: Instruments, Xcode profiler, Linux perf
- **Metrics collection**: Request latency, throughput, resource usage
- **Bottleneck detection**: Identifying slow operations
- **Optimization strategies**: Database, network, memory, CPU
- **Load testing**: Stress testing and capacity planning

## Profiling Tools

### macOS: Instruments

Instruments is the primary profiling tool for macOS development.

#### Time Profiler

Identify CPU-intensive code paths:

```bash
# Build with profiling enabled
xcodebuild -scheme ATProtoPDS-CLI \
  -configuration Release \
  ENABLE_PROFILING=YES \
  build

# Launch with Instruments
instruments -t "Time Profiler" ./build/bin/kaszlak serve
```

**What to look for**:
- Hot functions (high % of CPU time)
- Unexpected call stacks
- Tight loops without optimization
- Excessive object allocation

#### Allocations

Track memory usage and leaks:

```bash
instruments -t "Allocations" ./build/bin/kaszlak serve
```

**What to look for**:
- Memory growth over time (leaks)
- Large allocations
- Excessive temporary objects
- Retain cycles

#### System Trace

Analyze system-level performance:

```bash
instruments -t "System Trace" ./build/bin/kaszlak serve
```

**What to look for**:
- Thread contention
- I/O wait times
- Context switches
- System call overhead

### Linux: perf

Use `perf` for profiling on Linux/GNUstep:

```bash
# Record performance data
perf record -g ./build/bin/kaszlak serve

# Generate report
perf report

# Generate flame graph
perf script | stackcollapse-perf.pl | flamegraph.pl > flamegraph.svg
```

### Xcode Profiler

For quick profiling during development:

1. Open project in Xcode
2. Product → Profile (⌘I)
3. Choose profiling template
4. Run and analyze

## Metrics Collection with PDSMetrics

### PDSMetrics Singleton

September PDS uses a centralized metrics collection system via `PDSMetrics`:

```objc
// From ATProtoPDS/Sources/Metrics/PDSMetrics.m (lines 14-22)
+ (instancetype)sharedMetrics {
    static PDSMetrics *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSMetrics alloc] init];
    });
    return shared;
}
```

The metrics system uses `os_unfair_lock` for thread-safe counter updates:

```objc
// From ATProtoPDS/Sources/Metrics/PDSMetrics.m (lines 42-56)
- (void)incrementHttpRequestsForMethod:(NSString *)method
                             endpoint:(NSString *)endpoint
                               status:(NSInteger)status {
    os_unfair_lock_lock(&_lock);

    NSString *methodKey = [NSString stringWithFormat:@"method_%@", method.lowercaseString];
    _httpRequestsByMethod[methodKey] = @(_httpRequestsByMethod[methodKey].integerValue + 1);

    NSString *endpointKey = [NSString stringWithFormat:@"endpoint_%@", endpoint];
    _httpRequestsByEndpoint[endpointKey] = @(_httpRequestsByEndpoint[endpointKey].integerValue + 1);

    NSString *statusKey = [NSString stringWithFormat:@"status_%ld", (long)status];
    _httpRequestsByStatus[statusKey] = @(_httpRequestsByStatus[statusKey].integerValue + 1);

    os_unfair_lock_unlock(&_lock);
}
```

### Prometheus Export

Metrics are exported in Prometheus format for monitoring systems:

```objc
// From ATProtoPDS/Sources/Metrics/PDSMetrics.m (lines 93-107)
- (NSString *)exportPrometheus {
    NSMutableString *output = [NSMutableString string];

    [output appendString:@"# HELP pds_http_requests_total Total HTTP requests\n"];
    [output appendString:@"# TYPE pds_http_requests_total counter\n"];

    for (NSString *key in _httpRequestsByMethod) {
        NSString *method = [key stringByReplacingOccurrencesOfString:@"method_" withString:@""];
        [output appendFormat:@"pds_http_requests_total{method=\"%@\"} %@\n", method, _httpRequestsByMethod[key]];
    }

    [output appendString:@"\n# HELP pds_http_requests_by_endpoint Total HTTP requests by endpoint\n"];
    [output appendString:@"# TYPE pds_http_requests_by_endpoint counter\n"];

    for (NSString *key in _httpRequestsByEndpoint) {
        NSString *endpoint = [key stringByReplacingOccurrencesOfString:@"endpoint_" withString:@""];
        endpoint = [endpoint stringByReplacingOccurrencesOfString:@"/xrpc/" withString:@""];
        [output appendFormat:@"pds_http_requests_by_endpoint{endpoint=\"%@\"} %@\n", endpoint, _httpRequestsByEndpoint[key]];
    }
    // ... additional metrics
}
```

## Request Latency Monitoring

### Measuring Request Duration

Track request processing time using timestamps:

```objc
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    
    // Process request
    [self processRequest:request response:response];
    
    NSTimeInterval duration = [[NSDate date] timeIntervalSince1970] - startTime;
    
    // Log slow requests
    if (duration > 1.0) {
        PDS_LOG_HTTP_WARN(@"Slow request: %@ %@ (%.2fs)", 
                          request.method, request.path, duration);
    }
    
    // Record metric
    [[PDSMetrics sharedMetrics] incrementHttpRequestsForMethod:request.method
                                                      endpoint:request.path
                                                        status:response.statusCode];
}
```

### Percentile Tracking

Track P50, P95, P99 latencies:

```objc
@interface LatencyTracker : NSObject
@property (nonatomic, strong) NSMutableArray<NSNumber *> *samples;
@property (nonatomic, assign) NSUInteger maxSamples;

- (void)recordLatency:(NSTimeInterval)latency;
- (NSTimeInterval)percentile:(double)p;  // 0.0 to 1.0
@end

@implementation LatencyTracker

- (instancetype)init {
    self = [super init];
    if (self) {
        _samples = [NSMutableArray array];
        _maxSamples = 1000;  // Keep last 1000 samples
    }
    return self;
}

- (void)recordLatency:(NSTimeInterval)latency {
    @synchronized(self.samples) {
        [self.samples addObject:@(latency)];
        if (self.samples.count > self.maxSamples) {
            [self.samples removeObjectAtIndex:0];
        }
    }
}

- (NSTimeInterval)percentile:(double)p {
    @synchronized(self.samples) {
        if (self.samples.count == 0) return 0.0;
        
        NSArray *sorted = [self.samples sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger index = (NSUInteger)(p * (sorted.count - 1));
        return [sorted[index] doubleValue];
    }
}

@end

// Usage
LatencyTracker *tracker = [[LatencyTracker alloc] init];
[tracker recordLatency:duration];

NSLog(@"P50: %.2fms", [tracker percentile:0.50] * 1000);
NSLog(@"P95: %.2fms", [tracker percentile:0.95] * 1000);
NSLog(@"P99: %.2fms", [tracker percentile:0.99] * 1000);
```

## Database Performance

### Database Configuration for Performance

September PDS configures SQLite with performance-optimized PRAGMA settings:

```objc
// From ATProtoPDS/Sources/Database/ActorStore/ActorStore.m (lines 131-156)
- (BOOL)configureDatabase:(NSError **)error {
    const char *pragmas[] = {
        "PRAGMA journal_mode=WAL",        // Write-Ahead Logging for concurrency
        "PRAGMA synchronous=NORMAL",      // Balance safety and performance
        "PRAGMA wal_autocheckpoint=1000", // Checkpoint every 1000 pages
        "PRAGMA cache_size=-64000",       // 64MB cache (negative = KB)
        "PRAGMA temp_store=MEMORY",       // Store temp tables in memory
        "PRAGMA foreign_keys=ON",         // Enable foreign key constraints
        "PRAGMA encoding='UTF-8'",        // UTF-8 encoding
        NULL
    };
    
    for (int i = 0; pragmas[i] != NULL; i++) {
        char *errMsg = NULL;
        int result = sqlite3_exec(self.db, pragmas[i], NULL, NULL, &errMsg);
        if (result != SQLITE_OK) {
            if (error) {
                *error = [ATProtoError errorWithCode:ATProtoErrorCodeDatabaseError
                                           message:[NSString stringWithUTF8String:errMsg]
                                          userInfo:@{@"sqlite_code": @(result)}];
            }
            sqlite3_free(errMsg);
            return NO;
        }
    }
    
    return YES;
}
```

**Key Performance Settings:**
- `journal_mode=WAL`: Enables Write-Ahead Logging for better concurrent read/write performance
- `synchronous=NORMAL`: Reduces fsync calls while maintaining crash safety
- `cache_size=-64000`: Allocates 64MB of memory for page cache (negative value = kilobytes)
- `temp_store=MEMORY`: Keeps temporary tables in RAM for faster operations

### Query Profiling

Enable SQLite query logging:

```objc
// In PDSDatabase initialization
sqlite3_trace_v2(db, SQLITE_TRACE_PROFILE, ^int(unsigned type, void *ctx, void *p, void *x) {
    if (type == SQLITE_TRACE_PROFILE) {
        sqlite3_stmt *stmt = (sqlite3_stmt *)p;
        int64_t *nanoseconds = (int64_t *)x;
        double milliseconds = *nanoseconds / 1000000.0;
        
        if (milliseconds > 100.0) {  // Log queries > 100ms
            const char *sql = sqlite3_sql(stmt);
            PDS_LOG_DB_WARN(@"Slow query (%.2fms): %s", milliseconds, sql);
        }
    }
    return 0;
}, NULL);
```

### EXPLAIN QUERY PLAN

Analyze query execution:

```bash
# Connect to database
sqlite3 data/service.db

# Analyze query
EXPLAIN QUERY PLAN SELECT * FROM accounts WHERE handle = 'alice.example.com';

# Check for missing indexes
.schema accounts
```

### Index Optimization

Add indexes for frequently queried columns:

```sql
-- Check query performance
EXPLAIN QUERY PLAN SELECT * FROM records WHERE did = ? AND collection = ?;

-- Add composite index if needed
CREATE INDEX IF NOT EXISTS idx_records_did_collection ON records(did, collection);

-- Verify improvement
EXPLAIN QUERY PLAN SELECT * FROM records WHERE did = ? AND collection = ?;
```

### Connection Pooling

Monitor database connection usage:

```objc
@interface PDSDatabasePool ()
@property (nonatomic, assign) NSUInteger activeConnections;
@property (nonatomic, assign) NSUInteger peakConnections;
@end

- (PDSActorDatabase *)databaseForDID:(NSString *)did {
    @synchronized(self) {
        self.activeConnections++;
        if (self.activeConnections > self.peakConnections) {
            self.peakConnections = self.activeConnections;
            PDS_LOG_DB_INFO(@"New peak connections: %lu", 
                           (unsigned long)self.peakConnections);
        }
    }
    
    // Get or create database
    PDSActorDatabase *db = [self getCachedOrCreateDatabase:did];
    
    return db;
}

- (void)releaseDatabase:(PDSActorDatabase *)db {
    @synchronized(self) {
        self.activeConnections--;
    }
}
```

## Memory Profiling

### Memory Usage Tracking

September PDS tracks memory usage using Mach task info APIs:

```objc
// From ATProtoPDS/Sources/CLI/PDSCLIHealthCommand.m (lines 162-179)
+ (NSDictionary *)checkMemory {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"status"] = @"ok";

    struct task_vm_info vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vmInfo, &count);

    if (kr == KERN_SUCCESS) {
        unsigned long long usedBytes = vmInfo.phys_footprint;
        unsigned long long limitBytes = 1024ULL * 1024 * 1024;

        result[@"used_bytes"] = @(usedBytes);
        result[@"limit_bytes"] = @(limitBytes);
        double usageRatio = (double)usedBytes / (double)limitBytes;
        if (usedBytes > limitBytes * 0.9) {
            result[@"status"] = @"warn";
            result[@"message"] = @"High memory usage";
        }
    }

    return result;
}
```

This pattern uses `task_info()` with `TASK_VM_INFO` to get the physical memory footprint of the process.

### Detecting Leaks

Use Instruments Leaks template or manual checks:

```objc
// Enable malloc stack logging
export MallocStackLogging=1

// Run with leak detection
leaks --atExit -- ./build/bin/kaszlak serve
```

### Autorelease Pool Optimization

Use autorelease pools in loops to prevent memory accumulation:

```objc
// From ATProtoPDS/Sources/Network/HttpServer.m (lines 775-778)
@autoreleasepool {
    NSData *chunk = [fileHandle readDataOfLength:kHttpFileSendChunkSize];
    if (chunk.length == 0) {
        break;
    }
    // Process chunk
}
```

**Pattern in concurrent operations:**

```objc
// From ATProtoPDS/Tests/Database/Integration/PDSConcurrentAccessTestFixture.m (lines 34-40)
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @autoreleasepool {
        NSError *localError = nil;
        [self.pool readWithDid:@"did:plc:concurrent-test" 
                         block:^(id<PDSActorStoreReader> reader, NSError **innerError) {
            // Database operations
        }];
    }
});
```

**Best practice:** Wrap each iteration of long-running loops and concurrent operations in `@autoreleasepool` to drain temporary objects immediately.

## Network Performance

### Connection Reuse

Reuse HTTP connections:

```objc
@interface HttpClient ()
@property (nonatomic, strong) NSURLSession *session;
@end

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.HTTPMaximumConnectionsPerHost = 6;
        config.timeoutIntervalForRequest = 30.0;
        config.requestCachePolicy = NSURLRequestUseProtocolCachePolicy;
        
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}
```

### Request Batching

Batch multiple operations:

```objc
// Bad: N separate requests
for (NSString *did in dids) {
    [self fetchProfileForDID:did completion:^(NSDictionary *profile) {
        // Process profile
    }];
}

// Good: Single batched request
[self fetchProfilesForDIDs:dids completion:^(NSArray *profiles) {
    // Process all profiles
}];
```

### Compression

Enable response compression:

```objc
NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
[request setValue:@"gzip, deflate" forHTTPHeaderField:@"Accept-Encoding"];
```

## Concurrency Optimization

### GCD Queue Management

Use appropriate queue types:

```objc
// Serial queue for ordered operations
dispatch_queue_t serialQueue = dispatch_queue_create("com.pds.serial", 
                                                     DISPATCH_QUEUE_SERIAL);

// Concurrent queue for parallel operations
dispatch_queue_t concurrentQueue = dispatch_queue_create("com.pds.concurrent", 
                                                         DISPATCH_QUEUE_CONCURRENT);

// Use global queues for short tasks
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    // Background work
});
```

### Lock Contention

Minimize time holding locks:

```objc
// Bad: Holding lock during I/O
@synchronized(self.cache) {
    NSData *data = [self.cache objectForKey:key];
    if (!data) {
        data = [self fetchDataFromDisk:key];  // Slow I/O!
        [self.cache setObject:data forKey:key];
    }
    return data;
}

// Good: Lock only for cache access
NSData *data = nil;
@synchronized(self.cache) {
    data = [self.cache objectForKey:key];
}

if (!data) {
    data = [self fetchDataFromDisk:key];  // I/O outside lock
    @synchronized(self.cache) {
        [self.cache setObject:data forKey:key];
    }
}

return data;
```

### Thread Pool Sizing

Configure appropriate thread pool sizes:

```objc
// For I/O-bound tasks: More threads
NSOperationQueue *ioQueue = [[NSOperationQueue alloc] init];
ioQueue.maxConcurrentOperationCount = 10;

// For CPU-bound tasks: Match CPU count
NSOperationQueue *cpuQueue = [[NSOperationQueue alloc] init];
cpuQueue.maxConcurrentOperationCount = [[NSProcessInfo processInfo] processorCount];
```

## Bottleneck Detection

### Common Bottlenecks

1. **Database queries**: Use indexes, optimize queries
2. **Network I/O**: Use connection pooling, compression
3. **Serialization**: Cache parsed objects, use efficient formats
4. **Lock contention**: Reduce critical section size
5. **Memory allocation**: Reuse objects, use object pools

### Slow Consumer Detection

September PDS detects and handles slow consumers in the firehose:

```objc
// From ATProtoPDS/Sources/Sync/SubscribeReposHandler.m (lines 947-954)
if (connection.pendingSendCount >= self.maxPendingSendsPerConnection ||
    connection.pendingSendBytes >= self.maxPendingBytesPerConnection) {
    [self sendErrorFrameWithCode:kSubscribeReposErrorConsumerTooSlow
                         message:@"connection output queue exceeded server limit"
                    toConnection:connection];
    [self detachConnection:connection];
    [connection closeWithCode:1008 reason:kSubscribeReposErrorConsumerTooSlow];
    return NO;
}
```

This pattern prevents slow clients from blocking the server by monitoring pending send buffers.

### Fast vs Slow Path Optimization

Repository operations use fast/slow path patterns:

```objc
// From ATProtoPDS/Sources/App/Services/PDSRepositoryService.m (line 195)
// Slow path: rebuild export state, self-heal head commit if needed.
MST *mst = nil;
CID *commitCID = nil;
```

The code comments explicitly mark slow paths that involve expensive operations like rebuilding state.

### Identifying Bottlenecks

Use strategic logging:

```objc
- (void)processRequest:(HttpRequest *)request {
    NSTimeInterval t0 = [[NSDate date] timeIntervalSince1970];
    
    // Parse request
    NSDictionary *params = [self parseRequest:request];
    NSTimeInterval t1 = [[NSDate date] timeIntervalSince1970];
    
    // Database query
    NSArray *results = [self queryDatabase:params];
    NSTimeInterval t2 = [[NSDate date] timeIntervalSince1970];
    
    // Serialize response
    NSData *response = [self serializeResults:results];
    NSTimeInterval t3 = [[NSDate date] timeIntervalSince1970];
    
    PDS_LOG_DEBUG(@"Request timing: parse=%.2fms query=%.2fms serialize=%.2fms",
                  (t1-t0)*1000, (t2-t1)*1000, (t3-t2)*1000);
}
```

## Load Testing

### Using Apache Bench

Simple HTTP load testing:

```bash
# 1000 requests, 10 concurrent
ab -n 1000 -c 10 http://localhost:2583/xrpc/com.atproto.server.describeServer

# With authentication
ab -n 1000 -c 10 -H "Authorization: Bearer <token>" \
   http://localhost:2583/xrpc/com.atproto.repo.listRecords
```

### Using wrk

More advanced load testing:

```bash
# Install wrk
brew install wrk  # macOS
apt-get install wrk  # Linux

# Run load test
wrk -t4 -c100 -d30s http://localhost:2583/xrpc/com.atproto.server.describeServer

# With Lua script for complex scenarios
wrk -t4 -c100 -d30s -s script.lua http://localhost:2583/
```

Example `script.lua`:

```lua
wrk.method = "POST"
wrk.headers["Content-Type"] = "application/json"
wrk.headers["Authorization"] = "Bearer <token>"

request = function()
   body = '{"repo":"did:plc:test","collection":"app.bsky.feed.post"}'
   return wrk.format(nil, nil, nil, body)
end
```

### Monitoring During Load Tests

Watch metrics during load tests:

```bash
# Terminal 1: Run load test
wrk -t4 -c100 -d60s http://localhost:2583/

# Terminal 2: Monitor metrics
watch -n 1 'curl -s http://localhost:2583/_pds/admin/metrics | grep pds_http'

# Terminal 3: Monitor system resources
top -pid $(pgrep kaszlak)
```

## Optimization Strategies

### Database Optimization

**1. Configure Performance PRAGMAs**

```objc
// From ATProtoPDS/Sources/Database/Service/ServiceDatabases.m (lines 124-130)
- (void)applyPerformancePragmasOnPool:(PDSDatabasePool *)pool {
    static NSString *const pragmaSQL =
        @"PRAGMA journal_mode=WAL;"
        @"PRAGMA synchronous=NORMAL;"
        @"PRAGMA cache_size=-32000;"  // 32MB cache
        @"PRAGMA temp_store=MEMORY;";
    [self executeSQL:pragmaSQL onPool:pool error:nil];
}
```

**2. Use WAL Mode**

```objc
// From ATProtoPDS/Sources/Database/PDSDatabase.m (lines 254-257)
- (BOOL)setWalMode:(NSError **)error {
    char *errMsg = NULL;
    int rc = sqlite3_exec(_db, "PRAGMA journal_mode=WAL", NULL, NULL, &errMsg);
    if (rc != SQLITE_OK && errMsg) {
        NSError *e = [NSError errorWithDomain:PDSDatabaseErrorDomain
                                         code:PDSDatabaseErrorQueryFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:errMsg]}];
        if (error) *error = e;
        sqlite3_free(errMsg);
        return NO;
    }
    return YES;
}
```

**3. Optimize Cache Size**

```objc
// From ATProtoPDS/Sources/Database/PDSDatabase.m (lines 279-286)
rc = sqlite3_exec(_db, "PRAGMA cache_size=65536", NULL, NULL, &errMsg);
if (rc != SQLITE_OK && errMsg) {
    NSError *e = [self errorWithMessage:errMsg code:PDSDatabaseErrorQueryFailed];
    if (error) *error = e;
    sqlite3_free(errMsg);
    return NO;
}
```

This sets the cache to 65536 pages (approximately 256MB with 4KB pages).

### Caching Strategies

Implement multi-level caching:

```objc
@interface CacheManager : NSObject
@property (nonatomic, strong) NSCache *memoryCache;  // L1: Memory
@property (nonatomic, strong) NSString *diskCachePath;  // L2: Disk
@end

- (nullable NSData *)dataForKey:(NSString *)key {
    // Check memory cache
    NSData *data = [self.memoryCache objectForKey:key];
    if (data) {
        return data;
    }
    
    // Check disk cache
    NSString *path = [self.diskCachePath stringByAppendingPathComponent:key];
    data = [NSData dataWithContentsOfFile:path];
    if (data) {
        [self.memoryCache setObject:data forKey:key];  // Promote to L1
        return data;
    }
    
    return nil;
}
```

### Lazy Loading

Defer expensive operations:

```objc
@interface Repository ()
@property (nonatomic, strong) MST *mstCache;
@end

- (MST *)mst {
    if (!_mstCache) {
        _mstCache = [self loadMSTFromDatabase];
    }
    return _mstCache;
}
```

### Object Pooling

Reuse expensive objects:

```objc
@interface ObjectPool : NSObject
- (id)acquireObject;
- (void)releaseObject:(id)object;
@end

@implementation ObjectPool {
    NSMutableArray *_pool;
    Class _objectClass;
}

- (instancetype)initWithClass:(Class)cls initialSize:(NSUInteger)size {
    self = [super init];
    if (self) {
        _objectClass = cls;
        _pool = [NSMutableArray arrayWithCapacity:size];
        for (NSUInteger i = 0; i < size; i++) {
            [_pool addObject:[[cls alloc] init]];
        }
    }
    return self;
}

- (id)acquireObject {
    @synchronized(_pool) {
        if (_pool.count > 0) {
            id obj = [_pool lastObject];
            [_pool removeLastObject];
            return obj;
        }
    }
    return [[_objectClass alloc] init];
}

- (void)releaseObject:(id)object {
    @synchronized(_pool) {
        [_pool addObject:object];
    }
}

@end
```

## Performance Benchmarks

### XCTest Performance Measurement

September PDS uses XCTest's `measureBlock` for performance benchmarking:

```objc
// From ATProtoPDS/Tests/Debug/PDSLoggerPerformanceTests.m (lines 31-36)
[self measureBlock:^{
    for (int i = 0; i < 1000; i++) {
        PDS_LOG_INFO(@"Performance test message %d", i);
    }
    [logger flush];
}];
```

**Async vs Sync Logging Performance:**

```objc
// From ATProtoPDS/Tests/Debug/PDSLoggerPerformanceTests.m (lines 23-36)
- (void)testAsyncLoggingPerformance {
    PDSLogger *logger = [PDSLogger sharedLogger];
    logger.logFilePath = self.testLogPath;
    logger.asyncLogging = YES;
    logger.logLevel = PDSLogLevelInfo;
    logger.printToStdout = NO;

    [self measureBlock:^{
        for (int i = 0; i < 1000; i++) {
            PDS_LOG_INFO(@"Performance test message %d", i);
        }
        [logger flush];
    }];
}
```

### Timeout-Based Performance Validation

Ensure operations complete within acceptable time limits:

```objc
// From ATProtoPDS/Tests/Security/CBORSecurityTests.m (lines 80-85)
NSDate *start = [NSDate date];
CBORValue *decoded = [CBORDecoder decode:data];
NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];

XCTAssertNil(decoded, @"Should fail to decode incomplete data");
XCTAssertLessThan(duration, 1.0, @"Should fail fast and not hang allocating memory");
```

This pattern validates that error paths don't cause performance degradation or hangs.

### Establishing Baselines

Create performance benchmarks:

```objc
- (void)testRecordCreationPerformance {
    NSTimeInterval start = [[NSDate date] timeIntervalSince1970];
    
    for (NSInteger i = 0; i < 1000; i++) {
        [self createTestRecord];
    }
    
    NSTimeInterval duration = [[NSDate date] timeIntervalSince1970] - start;
    NSTimeInterval perRecord = duration / 1000.0;
    
    NSLog(@"Created 1000 records in %.2fs (%.2fms per record)", 
          duration, perRecord * 1000);
    
    // Assert performance threshold
    XCTAssertLessThan(perRecord, 0.010, @"Record creation too slow");
}
```

### Regression Testing

Track performance over time:

```bash
# Run benchmarks and save results
./build/tests/AllTests -XCTest PerformanceTests > perf-$(date +%Y%m%d).txt

# Compare with baseline
diff perf-baseline.txt perf-$(date +%Y%m%d).txt
```

## Best Practices

### Do's

- **Profile before optimizing**: Measure, don't guess
- **Focus on hot paths**: Optimize the 20% that matters
- **Use appropriate data structures**: Choose the right tool
- **Cache expensive operations**: Avoid redundant work
- **Monitor in production**: Track real-world performance
- **Set performance budgets**: Define acceptable thresholds
- **Test under load**: Simulate production conditions

### Don'ts

- **Don't premature optimize**: Clarity first, speed second
- **Don't optimize without measuring**: Prove the improvement
- **Don't sacrifice correctness**: Fast and wrong is useless
- **Don't ignore memory**: CPU is cheap, memory isn't
- **Don't forget concurrency**: Test with multiple threads
- **Don't optimize in isolation**: Consider the whole system

## Related Documentation

- [Metrics Collection](metrics-collection.md) - Quantitative monitoring
- [Logging Strategy](logging-strategy.md) - Diagnostic logging
- [Database Layer](../05-database-layer/sqlite-architecture.md) - Database optimization
- [Rate Limiting](../04-network-layer/rate-limiting.md) - Protecting performance

## See Also

- [Instruments User Guide](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/InstrumentsUserGuide/)
- [SQLite Performance Tuning](https://www.sqlite.org/optoverview.html)
- [Objective-C Performance Tips](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/PerformanceOverview/)
