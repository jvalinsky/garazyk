# Plan to Fix HTTP Server Concurrency/Timeout Issues

## Problem Summary
The HTTP server intermittently hangs after serving some requests. Symptoms:
- Server works initially after restart
- After a few requests, certain endpoints stop responding (timeout)
- Server doesn't crash - just stops responding to specific requests
- Restarting the service temporarily fixes the issue

## Root Cause Analysis

### Likely Issues Identified:

#### 1. **Dispatch Source Suspension Bug** (HIGH PROBABILITY)
In `PDSNetworkTransportLinux.m`, the write source management has a potential issue:

```objc
// In handleWrite:
if (_writeRequests.count == 0 && _writeSource) {
    dispatch_suspend(_writeSource);
}
```

And in `sendData`:
```objc
if (wasEmpty && _writeSource) {
    dispatch_resume(_writeSource);
}
```

**Problem**: If `dispatch_suspend` is called multiple times without matching `dispatch_resume`, the source becomes permanently suspended. GCD dispatch sources have a suspension count - each suspend increments it, each resume decrements it. If we suspend twice and resume once, the source stays suspended.

#### 2. **Read Source Never Resumed After Initial Read** (HIGH PROBABILITY)
The `_readSource` is created and resumed in `setupSources`, but if the connection uses keep-alive and we read the next request, we call `readRequestFromConnection:` which queues another receive request. However, if the read source was suspended or the completion handler wasn't called, the connection can hang.

#### 3. **@synchronized Deadlock Potential** (MEDIUM PROBABILITY)
Multiple `@synchronized` blocks on `_receiveRequests` and `_writeRequests` could cause deadlocks if callbacks execute synchronously and try to acquire locks in different orders.

#### 4. **Keep-Alive Connection Starvation** (MEDIUM PROBABILITY)
In `sendResponse:onConnection:`, if `shouldKeepAlive` is YES, we call `readRequestFromConnection:` again. But if the client doesn't send another request immediately, the connection may hold resources indefinitely.

#### 5. **Memory Pressure / Retain Cycle** (LOW PROBABILITY)
The `__weak`/`__strong` dance in blocks could have subtle retain cycle issues causing connections to not be properly cleaned up.

## Fix Plan

### Phase 1: Fix Dispatch Source Suspension (Priority: CRITICAL)

**File**: `ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m`

1. Add a boolean flag to track write source suspension state:
```objc
@implementation PDSNetworkConnectionLinux {
    // ... existing ivars ...
    BOOL _writeSourceSuspended;
}
```

2. Modify `setupSources` to initialize the flag:
```objc
- (void)setupSources {
    // ... existing code ...
    _writeSourceSuspended = YES;  // Starts suspended (not resumed)
}
```

3. Fix `handleWrite` to properly track state:
```objc
- (void)handleWrite {
    if (_cancelled) return;

    @synchronized (_writeRequests) {
        // ... existing write logic ...
        
        if (_writeRequests.count == 0 && _writeSource && !_writeSourceSuspended) {
            dispatch_suspend(_writeSource);
            _writeSourceSuspended = YES;
        }
    }
}
```

4. Fix `sendData` to properly track state:
```objc
- (void)sendData:(NSData *)data completion:(void (^)(NSError *))completion {
    // ... existing code ...
    
    @synchronized (_writeRequests) {
        [_writeRequests addObject:request];
        
        if (_writeSourceSuspended && _writeSource) {
            dispatch_resume(_writeSource);
            _writeSourceSuspended = NO;
        }
    }
}
```

### Phase 2: Add Connection Timeout (Priority: HIGH)

1. Add timeout handling to prevent connections from hanging indefinitely:
```objc
- (void)startWithQueue:(dispatch_queue_t)queue {
    // ... existing code ...
    
    // Add connection timeout
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, 
        dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
        DISPATCH_TIME_FOREVER, 
        1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        NSLog(@"Connection timed out: %@", self.remoteAddress);
        [self cancel];
    });
    dispatch_resume(timer);
    _timeoutSource = timer;
}
```

2. Reset timeout on activity:
```objc
- (void)resetTimeout {
    if (_timeoutSource) {
        dispatch_source_set_timer(_timeoutSource,
            dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
            DISPATCH_TIME_FOREVER,
            1 * NSEC_PER_SEC);
    }
}
```

### Phase 3: Add Request-Level Logging (Priority: MEDIUM)

Add logging to track request lifecycle for debugging:

```objc
- (void)readRequestFromConnection:(id<PDSNetworkConnection>)connection {
    NSString *connId = [NSString stringWithFormat:@"%p", connection];
    NSLog(@"[%@] Waiting for request data...", connId);
    
    // ... existing code with added logging ...
}
```

### Phase 4: Improve Keep-Alive Handling (Priority: MEDIUM)

1. Set a maximum number of requests per keep-alive connection
2. Add idle timeout for keep-alive connections (shorter than the main timeout)
3. Consider disabling keep-alive for simplicity if issues persist

### Phase 5: Add Health Monitoring (Priority: LOW)

1. Add endpoint to report active connection count
2. Add periodic logging of server state
3. Consider adding watchdog timer to detect hung state

## Testing Plan

1. **Load test**: Use `ab` or `wrk` to send many concurrent requests
2. **Sequence test**: Send specific sequence that triggers the hang
3. **Long-running test**: Keep server running and periodically test endpoints
4. **Connection leak test**: Monitor file descriptor count over time

## Implementation Order

1. Phase 1 (dispatch source fix) - Most likely root cause
2. Phase 2 (timeouts) - Safety net
3. Phase 3 (logging) - Helps debug remaining issues
4. Phase 4 (keep-alive) - If issues persist
5. Phase 5 (monitoring) - Long-term health

## Quick Verification

After Phase 1, run:
```bash
for i in {1..100}; do
    curl -s --max-time 2 http://localhost:8000/.well-known/did.json > /dev/null && echo "OK $i" || echo "FAIL $i"
done
```

All 100 requests should succeed without timeouts.
