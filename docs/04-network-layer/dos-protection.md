---
title: DoS Protection
---

# DoS Protection

## Overview

Denial of Service (DoS) protection prevents malicious actors from overwhelming the PDS and making it unavailable to legitimate users. The PDS implements multiple layers of defense to detect and mitigate various attack vectors.

## Attack Vectors

### 1. Request Flooding

**Attack:** Overwhelming the server with high-volume requests.

**Impact:**
- CPU exhaustion from request processing
- Memory exhaustion from connection handling
- Network bandwidth saturation
- Legitimate users unable to connect

**Mitigation:**
- Rate limiting per IP/DID
- Connection limits
- Request queue depth limits
- Fast rejection of invalid requests

### 2. Slowloris Attack

**Attack:** Opening many connections and sending partial HTTP requests slowly to keep connections open.

**Impact:**
- Connection pool exhaustion
- Server unable to accept new connections
- Resource starvation

**Mitigation:**
- Connection timeouts
- Request header size limits
- Request timeout enforcement
- Maximum concurrent connections per IP

### 3. Large Payload Attack

**Attack:** Sending extremely large request bodies to consume memory and bandwidth.

**Impact:**
- Memory exhaustion
- Disk space exhaustion
- Bandwidth saturation
- Processing delays

**Mitigation:**
- Request body size limits
- Streaming request processing
- Early rejection of oversized requests
- Blob upload quotas

### 4. Computational Exhaustion

**Attack:** Triggering expensive operations (crypto, database queries, MST operations).

**Impact:**
- CPU exhaustion
- Database lock contention
- Response time degradation
- Service unavailability

**Mitigation:**
- Operation complexity limits
- Query timeout enforcement
- Cryptographic operation rate limiting
- MST depth limits

### 5. WebSocket Flooding

**Attack:** Opening many WebSocket connections or sending high-volume messages.

**Impact:**
- Connection pool exhaustion
- Memory exhaustion from buffering
- CPU exhaustion from message processing
- Firehose unavailability

**Mitigation:**
- WebSocket connection limits
- Message rate limiting
- Backpressure mechanisms
- Connection timeout enforcement

### 6. Database Exhaustion

**Attack:** Triggering expensive database queries or excessive writes.

**Impact:**
- Database lock contention
- Disk I/O saturation
- Query timeout cascades
- Service degradation

**Mitigation:**
- Query complexity limits
- Transaction timeout enforcement
- Write rate limiting
- Database connection pooling

## Defense Layers

### Layer 1: Network Level

**Firewall Rules:**
```bash
# Example iptables rules (applied at infrastructure level)
# Limit new connections per IP
iptables -A INPUT -p tcp --dport 2583 -m connlimit --connlimit-above 50 -j REJECT

# Rate limit SYN packets
iptables -A INPUT -p tcp --syn -m limit --limit 10/s --limit-burst 20 -j ACCEPT
iptables -A INPUT -p tcp --syn -j DROP

# Drop invalid packets
iptables -A INPUT -m state --state INVALID -j DROP
```

**Reverse Proxy (nginx):**
```nginx
# In production: exe.dev HTTPS → nginx:3000 → PDS:2583
http {
    # Connection limits
    limit_conn_zone $binary_remote_addr zone=addr:10m;
    limit_conn addr 10;
    
    # Request rate limits
    limit_req_zone $binary_remote_addr zone=req_limit:10m rate=10r/s;
    limit_req zone=req_limit burst=20 nodelay;
    
    # Request size limits
    client_max_body_size 10M;
    client_body_timeout 10s;
    client_header_timeout 10s;
    
    # Timeouts
    keepalive_timeout 30s;
    send_timeout 30s;
}
```

## Layer 2: HTTP Server Level

**Connection Management:**

```objc
// In HttpServer.m - Connection limits
@interface HttpServer ()
@property (nonatomic, assign) NSUInteger maxConnections;
@property (nonatomic, assign) NSUInteger activeConnections;
@property (nonatomic, strong) NSMutableDictionary *connectionsPerIP;
@end

- (BOOL)shouldAcceptConnection:(NSString *)remoteIP {
    // 1. Check global connection limit
    if (self.activeConnections >= self.maxConnections) {
        PDS_LOG_HTTP_WARNING(@"Rejecting connection: max connections reached (%lu)", 
                             (unsigned long)self.maxConnections);
        return NO;
    }
    
    // 2. Check per-IP connection limit
    NSNumber *ipConnections = self.connectionsPerIP[remoteIP] ?: @0;
    if (ipConnections.integerValue >= 10) {
        PDS_LOG_HTTP_WARNING(@"Rejecting connection from %@: per-IP limit reached", remoteIP);
        return NO;
    }
    
    return YES;
}
```

**Request Size Limits:**

```objc
// In HttpServer.m - Request validation
- (BOOL)validateRequest:(HttpRequest *)request {
    // 1. Header size limit (8KB)
    if (request.headerSize > 8192) {
        PDS_LOG_HTTP_WARNING(@"Rejecting request: headers too large (%lu bytes)", 
                             (unsigned long)request.headerSize);
        return NO;
    }
    
    // 2. URI length limit (2KB)
    if (request.path.length > 2048) {
        PDS_LOG_HTTP_WARNING(@"Rejecting request: URI too long (%lu chars)", 
                             (unsigned long)request.path.length);
        return NO;
    }
    
    // 3. Body size limit (varies by endpoint)
    NSUInteger maxBodySize = [self maxBodySizeForPath:request.path];
    if (request.contentLength > maxBodySize) {
        PDS_LOG_HTTP_WARNING(@"Rejecting request: body too large (%lld > %lu)", 
                             request.contentLength, (unsigned long)maxBodySize);
        return NO;
    }
    
    return YES;
}

- (NSUInteger)maxBodySizeForPath:(NSString *)path {
    if ([path hasPrefix:@"/xrpc/com.atproto.repo.uploadBlob"]) {
        return 10 * 1024 * 1024;  // 10MB for blobs
    } else if ([path hasPrefix:@"/xrpc/"]) {
        return 1 * 1024 * 1024;   // 1MB for XRPC
    } else {
        return 100 * 1024;        // 100KB default
    }
}
```

**Request Timeouts:**

```objc
// In HttpServer.m - Timeout enforcement
- (void)handleConnection:(int)clientSocket remoteAddress:(NSString *)remoteIP {
    // 1. Set socket timeout
    struct timeval timeout;
    timeout.tv_sec = 30;  // 30 second timeout
    timeout.tv_usec = 0;
    setsockopt(clientSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(clientSocket, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    
    // 2. Start request timer
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, 
                                                     dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    dispatch_source_set_timer(timer, 
                             dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
                             DISPATCH_TIME_FOREVER, 
                             1 * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(timer, ^{
        PDS_LOG_HTTP_WARNING(@"Request timeout from %@", remoteIP);
        close(clientSocket);
    });
    
    dispatch_resume(timer);
    
    // 3. Process request
    [self processRequest:clientSocket remoteAddress:remoteIP];
    
    // 4. Cancel timer
    dispatch_source_cancel(timer);
}
```

### Layer 3: Rate Limiting

**IP-Based Rate Limiting:**

```objc
// In HttpServer.m - OAuth endpoint protection
if ([request.path hasPrefix:@"/oauth/"] && !RateLimiterIsDisabledGlobally() &&
    [RateLimiter sharedLimiter].isEnabled) {
  RateLimitResult *result =
      [[RateLimiter sharedLimiter] checkRateLimitForIP:request.remoteAddress];

  if (!result.allowed) {
    response.statusCode = 429;
    [response setJsonBody:@{
      @"error" : @"too_many_requests",
      @"message" : @"Rate limit exceeded"
    }];
    return response;
  }
}
```

**Source:** `Garazyk/Sources/Network/HttpServer.m` (lines 994-1005)

**DID-Based Rate Limiting:**

```objc
// In XRPC handlers - Authenticated request protection
- (void)handleXrpcRequest:(HttpRequest *)request response:(HttpResponse *)response {
    // 1. Verify authentication
    NSString *did = [self extractDIDFromRequest:request];
    if (!did) {
        response.statusCode = 401;
        return;
    }
    
    // 2. Check rate limit
    RateLimitResult *result = [[RateLimiter sharedLimiter] checkRateLimitForDid:did];
    if (!result.allowed) {
        response.statusCode = 429;
        [response setHeader:[NSString stringWithFormat:@"%.0f", result.retryAfter] 
                     forKey:@"Retry-After"];
        [response setJsonBody:@{
            @"error": @"RateLimitExceeded",
            @"message": @"Too many requests"
        }];
        return;
    }
    
    // 3. Process request
    [self processXrpcRequest:request response:response];
}
```

### Layer 4: Application Level

**Blob Upload Protection:**

```objc
// In PDSBlobService.m - Blob upload limits
- (void)uploadBlob:(NSData *)blobData 
            forDID:(NSString *)did
        completion:(void (^)(NSString *cid, NSError *error))completion {
    
    // 1. Check blob size
    if (blobData.length > 10 * 1024 * 1024) {  // 10MB limit
        NSError *error = [NSError errorWithDomain:@"BlobError" 
                                             code:413 
                                         userInfo:@{NSLocalizedDescriptionKey: @"Blob too large"}];
        completion(nil, error);
        return;
    }
    
    // 2. Check rate limit
    RateLimitResult *result = [[RateLimiter sharedLimiter] checkBlobUploadRateLimitForDid:did];
    if (!result.allowed) {
        NSError *error = [NSError errorWithDomain:@"BlobError" 
                                             code:429 
                                         userInfo:@{NSLocalizedDescriptionKey: @"Upload rate limit exceeded"}];
        completion(nil, error);
        return;
    }
    
    // 3. Check quota
    NSUInteger currentUsage = [self getBlobUsageForDID:did];
    if (currentUsage + blobData.length > self.maxBlobStoragePerUser) {
        NSError *error = [NSError errorWithDomain:@"BlobError" 
                                             code:507 
                                         userInfo:@{NSLocalizedDescriptionKey: @"Storage quota exceeded"}];
        completion(nil, error);
        return;
    }
    
    // 4. Process upload
    [self storeBlobData:blobData forDID:did completion:completion];
}
```

**MST Operation Limits:**

```objc
// In MST.m - Complexity limits
- (BOOL)validateMSTOperation:(MSTOperation *)operation {
    // 1. Depth limit
    if (operation.depth > 32) {
        PDS_LOG_ERROR(@"MST operation exceeds depth limit: %lu", (unsigned long)operation.depth);
        return NO;
    }
    
    // 2. Node count limit
    if (operation.nodeCount > 10000) {
        PDS_LOG_ERROR(@"MST operation exceeds node count limit: %lu", (unsigned long)operation.nodeCount);
        return NO;
    }
    
    // 3. Key length limit
    if (operation.key.length > 256) {
        PDS_LOG_ERROR(@"MST key exceeds length limit: %lu", (unsigned long)operation.key.length);
        return NO;
    }
    
    return YES;
}
```

**Database Query Limits:**

```objc
// In database layer - Query timeout enforcement
- (NSArray *)executeQuery:(NSString *)sql 
               withParams:(NSArray *)params
                  timeout:(NSTimeInterval)timeout {
    
    // 1. Set statement timeout
    sqlite3_busy_timeout(self.db, (int)(timeout * 1000));
    
    // 2. Prepare statement
    sqlite3_stmt *stmt;
    int result = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (result != SQLITE_OK) {
        return nil;
    }
    
    // 3. Bind parameters
    [self bindParams:params toStatement:stmt];
    
    // 4. Execute with timeout
    NSMutableArray *rows = [NSMutableArray array];
    NSDate *startTime = [NSDate date];
    
    while ((result = sqlite3_step(stmt)) == SQLITE_ROW) {
        // Check timeout
        if ([[NSDate date] timeIntervalSinceDate:startTime] > timeout) {
            PDS_LOG_DB_WARNING(@"Query timeout exceeded");
            sqlite3_finalize(stmt);
            return nil;
        }
        
        [rows addObject:[self rowFromStatement:stmt]];
    }
    
    sqlite3_finalize(stmt);
    return rows;
}
```

### Layer 5: WebSocket Protection

**Connection Limits:**

```objc
// In WebSocketServer.m - Connection management
@interface WebSocketServer ()
@property (nonatomic, assign) NSUInteger maxConnections;
@property (nonatomic, strong) NSMutableSet *activeConnections;
@property (nonatomic, strong) NSMutableDictionary *connectionsPerIP;
@end

- (BOOL)shouldAcceptWebSocketConnection:(NSString *)remoteIP {
    // 1. Check global limit
    if (self.activeConnections.count >= self.maxConnections) {
        PDS_LOG_WEBSOCKET_WARNING(@"Rejecting WebSocket: max connections reached");
        return NO;
    }
    
    // 2. Check per-IP limit
    NSNumber *ipConnections = self.connectionsPerIP[remoteIP] ?: @0;
    if (ipConnections.integerValue >= 5) {  // 5 WebSocket connections per IP
        PDS_LOG_WEBSOCKET_WARNING(@"Rejecting WebSocket from %@: per-IP limit reached", remoteIP);
        return NO;
    }
    
    return YES;
}
```

**Message Rate Limiting:**

```objc
// In WebSocketConnection.m - Message rate limiting
@interface WebSocketConnection ()
@property (nonatomic, assign) NSUInteger messagesReceived;
@property (nonatomic, strong) NSDate *windowStart;
@property (nonatomic, assign) NSUInteger maxMessagesPerWindow;
@property (nonatomic, assign) NSTimeInterval windowDuration;
@end

- (BOOL)shouldAcceptMessage {
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.windowStart];
    
    // Reset window if expired
    if (elapsed > self.windowDuration) {
        self.messagesReceived = 0;
        self.windowStart = [NSDate date];
    }
    
    // Check limit
    if (self.messagesReceived >= self.maxMessagesPerWindow) {
        PDS_LOG_WEBSOCKET_WARNING(@"Message rate limit exceeded");
        return NO;
    }
    
    self.messagesReceived++;
    return YES;
}
```

**Backpressure Enforcement:**

```objc
// In WebSocketConnection.m - Buffer overflow protection
- (void)sendFrame:(NSData *)frame {
  dispatch_async(self.writeQueue, ^{
    if (self.state == WebSocketConnectionStateClosing ||
        self.state == WebSocketConnectionStateClosed) {
      return;
    }
    
    // Check buffer limit
    if (self.queuedSendBytes + frame.length > WS_MAX_PENDING_SEND_BYTES) {
      [self.messageQueue removeAllObjects];
      self.queuedSendBytes = 0;
      dispatch_async(dispatch_get_main_queue(), ^{
        [self closeWithCode:1009 reason:@"Outbound queue limit exceeded"];
      });
      return;
    }

    [self.messageQueue addObject:frame];
    self.queuedSendBytes += frame.length;
    if (self.messageQueue.count == 1) {
      [self flushWriteBuffer];
    }
  });
}
```

**Source:** `Garazyk/Sources/Sync/WebSocketConnection.m` (lines 280-300)

## Monitoring and Detection

### Attack Detection

```objc
// In DoSDetector.m - Attack pattern detection
@interface DoSDetector : NSObject
@property (nonatomic, strong) NSMutableDictionary *requestCounts;
@property (nonatomic, strong) NSMutableDictionary *errorCounts;
@property (nonatomic, strong) NSMutableDictionary *suspiciousIPs;
@end

- (void)recordRequest:(NSString *)remoteIP statusCode:(NSInteger)statusCode {
    // 1. Update request count
    NSNumber *count = self.requestCounts[remoteIP] ?: @0;
    self.requestCounts[remoteIP] = @(count.integerValue + 1);
    
    // 2. Track errors
    if (statusCode >= 400) {
        NSNumber *errorCount = self.errorCounts[remoteIP] ?: @0;
        self.errorCounts[remoteIP] = @(errorCount.integerValue + 1);
    }
    
    // 3. Detect suspicious patterns
    if (count.integerValue > 1000) {  // High request volume
        [self markIPAsSuspicious:remoteIP reason:@"High request volume"];
    }
    
    NSNumber *errorCount = self.errorCounts[remoteIP] ?: @0;
    if (errorCount.integerValue > 100) {  // High error rate
        [self markIPAsSuspicious:remoteIP reason:@"High error rate"];
    }
}

- (void)markIPAsSuspicious:(NSString *)ip reason:(NSString *)reason {
    self.suspiciousIPs[ip] = @{
        @"reason": reason,
        @"timestamp": [NSDate date],
        @"action": @"monitor"
    };
    
    PDS_LOG_SECURITY_WARNING(@"Suspicious IP detected: %@ (%@)", ip, reason);
}
```

### Metrics Collection

```objc
// In PDSMetrics.m - DoS metrics
@interface PDSMetrics : NSObject
@property (nonatomic, assign) NSUInteger totalRequests;
@property (nonatomic, assign) NSUInteger rejectedRequests;
@property (nonatomic, assign) NSUInteger rateLimitedRequests;
@property (nonatomic, assign) NSUInteger timeoutRequests;
@property (nonatomic, assign) NSUInteger oversizedRequests;
@end

- (void)recordRejection:(NSString *)reason {
    self.rejectedRequests++;
    
    if ([reason isEqualToString:@"rate_limit"]) {
        self.rateLimitedRequests++;
    } else if ([reason isEqualToString:@"timeout"]) {
        self.timeoutRequests++;
    } else if ([reason isEqualToString:@"oversized"]) {
        self.oversizedRequests++;
    }
}

- (NSDictionary *)getMetrics {
    return @{
        @"total_requests": @(self.totalRequests),
        @"rejected_requests": @(self.rejectedRequests),
        @"rate_limited_requests": @(self.rateLimitedRequests),
        @"timeout_requests": @(self.timeoutRequests),
        @"oversized_requests": @(self.oversizedRequests),
        @"rejection_rate": @((double)self.rejectedRequests / self.totalRequests)
    };
}
```

## Response Strategies

### 1. Graceful Degradation

```objc
// In HttpServer.m - Load shedding
- (HttpResponse *)handleRequest:(HttpRequest *)request {
    // 1. Check server load
    double cpuUsage = [self getCurrentCPUUsage];
    NSUInteger activeConnections = self.activeConnections;
    
    // 2. Shed load if overloaded
    if (cpuUsage > 0.9 || activeConnections > self.maxConnections * 0.9) {
        // Reject non-critical requests
        if (![self isCriticalEndpoint:request.path]) {
            HttpResponse *response = [HttpResponse response];
            response.statusCode = 503;
            [response setHeader:@"60" forKey:@"Retry-After"];
            [response setJsonBody:@{
                @"error": @"ServiceUnavailable",
                @"message": @"Server overloaded, please retry later"
            }];
            return response;
        }
    }
    
    // 3. Process request
    return [self processRequest:request];
}

- (BOOL)isCriticalEndpoint:(NSString *)path {
    // Critical endpoints that should always be available
    return [path hasPrefix:@"/xrpc/com.atproto.server.describeServer"] ||
           [path hasPrefix:@"/xrpc/com.atproto.server.getSession"];
}
```

### 2. Temporary Blocking

```objc
// In IPBlockList.m - Temporary IP blocking
@interface IPBlockList : NSObject
@property (nonatomic, strong) NSMutableDictionary *blockedIPs;
@end

- (void)blockIP:(NSString *)ip duration:(NSTimeInterval)duration reason:(NSString *)reason {
    NSDate *unblockTime = [NSDate dateWithTimeIntervalSinceNow:duration];
    
    self.blockedIPs[ip] = @{
        @"unblock_time": unblockTime,
        @"reason": reason,
        @"blocked_at": [NSDate date]
    };
    
    PDS_LOG_SECURITY_WARNING(@"Blocked IP %@ for %.0f seconds (%@)", ip, duration, reason);
}

- (BOOL)isIPBlocked:(NSString *)ip {
    NSDictionary *blockInfo = self.blockedIPs[ip];
    if (!blockInfo) {
        return NO;
    }
    
    NSDate *unblockTime = blockInfo[@"unblock_time"];
    if ([[NSDate date] compare:unblockTime] == NSOrderedDescending) {
        // Block expired
        [self.blockedIPs removeObjectForKey:ip];
        return NO;
    }
    
    return YES;
}
```

### 3. CAPTCHA Challenge

```objc
// In CaptchaChallenge.m - Challenge suspicious requests
- (BOOL)shouldChallengeRequest:(HttpRequest *)request {
    NSString *ip = request.remoteAddress;
    
    // 1. Check if IP is suspicious
    if ([self.dosDetector isSuspiciousIP:ip]) {
        return YES;
    }
    
    // 2. Check request patterns
    NSUInteger recentRequests = [self.dosDetector getRecentRequestCount:ip];
    if (recentRequests > 50) {  // High request rate
        return YES;
    }
    
    return NO;
}

- (HttpResponse *)generateChallengeResponse {
    HttpResponse *response = [HttpResponse response];
    response.statusCode = 403;
    [response setJsonBody:@{
        @"error": @"ChallengeRequired",
        @"message": @"Please complete CAPTCHA verification",
        @"challenge_url": @"/challenge"
    }];
    return response;
}
```

## Configuration

### Recommended Limits

```objc
// In PDSConfiguration.m - DoS protection settings
@interface PDSConfiguration ()
@property (nonatomic, assign) NSUInteger maxConnections;
@property (nonatomic, assign) NSUInteger maxConnectionsPerIP;
@property (nonatomic, assign) NSUInteger maxRequestBodySize;
@property (nonatomic, assign) NSTimeInterval requestTimeout;
@property (nonatomic, assign) NSUInteger maxWebSocketConnections;
@property (nonatomic, assign) NSUInteger maxWebSocketConnectionsPerIP;
@end

// Default values
self.maxConnections = 1000;
self.maxConnectionsPerIP = 10;
self.maxRequestBodySize = 10 * 1024 * 1024;  // 10MB
self.requestTimeout = 30.0;  // 30 seconds
self.maxWebSocketConnections = 500;
self.maxWebSocketConnectionsPerIP = 5;
```

## Best Practices

1. **Defense in depth** — Multiple protection layers
2. **Fail closed** — Reject when uncertain
3. **Monitor continuously** — Track attack patterns
4. **Log security events** — Audit trail for analysis
5. **Rate limit aggressively** — Better safe than sorry
6. **Implement timeouts** — Prevent resource exhaustion
7. **Validate all input** — Never trust client data
8. **Test under load** — Verify protections work
9. **Update regularly** — Stay ahead of new attacks
10. **Have incident response plan** — Know what to do

## Incident Response

### Detection

1. Monitor metrics for anomalies
2. Alert on threshold violations
3. Correlate events across layers
4. Identify attack patterns

### Response

1. Confirm attack is occurring
2. Identify attack vector
3. Apply appropriate mitigation
4. Monitor effectiveness
5. Escalate if needed

### Recovery

1. Remove temporary blocks
2. Restore normal operation
3. Analyze attack logs
4. Update defenses
5. Document lessons learned

## Next Steps

- **[Rate Limiting](rate-limiting)** — Rate limiting strategies
- **[Request Throttling](request-throttling)** — Per-endpoint throttling
- **[Input Validation](input-validation)** — Input validation strategies

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

