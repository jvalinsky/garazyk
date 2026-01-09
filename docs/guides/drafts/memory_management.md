# Memory Management Guide

This guide outlines the memory management patterns and best practices used in the ATProtoPDS codebase. The project uses Automatic Reference Counting (ARC) for all Objective-C code.

## Automatic Reference Counting (ARC)

The PDS project relies on ARC to manage object lifecycles. Manual calls to `retain`, `release`, and `autorelease` are forbidden. However, understanding ownership semantics is crucial, especially when bridging to Core Foundation (CF) types or managing circular references.

### General Rules
1. **Ownership is strict**: Objects stay alive as long as at least one strong reference points to them.
2. **Retain cycles are fatal**: Two objects strongly referencing each other will never be deallocated.
3. **Core Foundation bridging**: Use `__bridge`, `__bridge_transfer`, or `CFRelease` when interacting with C-based APIs (like `SecKeyRef`).

---

## Retain Cycles & Block Capture

Retain cycles are the most common memory issue in Objective-C. They frequently occur in two contexts: blocks and delegates.

### Block Capture (Weak/Strong Dance)

When a block captures `self` (e.g., in a completion handler or GCD dispatch), it creates a strong reference to `self`. If `self` also owns the block (directly or indirectly), a retain cycle is created.

**Pattern:** Use `__weak` to break the cycle, and `__strong` inside the block to ensure the object stays alive during execution.

#### Example: Network Listener (HttpServer.m)
In `HttpServer.m`, the listener callback captures `self`. Without the weak reference, the server would never deallocate.

```objective-c
__weak typeof(self) weakSelf = self;
nw_listener_set_state_changed_handler(self.listener, ^(nw_listener_state_t state, nw_error_t error) {
    // Upgrade to strong reference to ensure 'self' exists while this block runs
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;

    switch (state) {
        case nw_listener_state_ready:
            strongSelf.running = YES;
            // ...
            break;
        // ...
    }
});
```

#### Example: Recursive Blocks (WebSocketConnection.m)
Recursive methods that use blocks must be especially careful. In `WebSocketConnection.m`, the reading loop re-calls `startReading` from within the block.

```objective-c
- (void)startReading {
    __weak typeof(self) weakSelf = self;
    nw_connection_receive_completion_t completion = ^(dispatch_data_t data, nw_content_context_t context, bool isComplete, nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (data) {
            // ... handle data
        }

        if (!error) {
            [strongSelf startReading]; // Safe recursive call
        }
    };

    nw_connection_receive(self.connection, 1, UINT32_MAX, completion);
}
```

### Delegates

Delegates must **always** be declared as `weak`. If a parent object holds a strong reference to a child, and the child holds a strong reference to the parent (as its delegate), neither will be deallocated.

```objective-c
@interface WebSocketConnection : NSObject
// ...
// Correct: Delegate is weak
@property (nonatomic, weak, nullable) id<WebSocketConnectionDelegate> delegate;
// ...
@end
```

---

## Property Attributes

Choosing the correct property attribute is vital for both correctness and performance.

### `assign` vs `copy` vs `strong` vs `weak`

| Attribute | Usage | Example |
|-----------|-------|---------|
| `assign` | Primitive types (`NSInteger`, `BOOL`, `float`) | `PDSMetrics` counters |
| `copy` | Value objects with mutable counterparts (`NSString`, `NSData`, `NSArray`) | `PDSDatabase` DIDs and Handles |
| `strong` | Objects the class owns | Child controllers, internal queues |
| `weak` | Objects the class refers to but does not own | Delegates |

#### Example: Primitives (PDSMetrics.h)
Use `assign` for scalars. No reference counting is involved.

```objective-c
@interface PDSMetrics : NSObject
@property (nonatomic, assign) NSInteger httpRequestsTotal;
@property (nonatomic, assign) unsigned long long blobStorageBytes;
@end
```

#### Example: Value Types (PDSDatabase.h)
Use `copy` for strings and data. This protects the object from being mutated unexpectedly if a `NSMutableString` is passed in.

```objective-c
@interface PDSDatabase : NSObject
@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, copy, nullable) NSData *passwordHash;
@end
```

---

## Autorelease Pools

Autorelease pools are used to explicitly scope the lifetime of temporary objects. This is critical in loops or long-running operations where thousands of temporary objects (like strings or error objects) might be created before the main run loop drains.

### When to use
- Inside tight loops creating many autoreleased objects.
- In custom run loops or background threads.
- At the entry point of CLI commands.

#### Example: Server Run Loop (PDSCLIServeCommand.m)
The server command runs a custom run loop to handle network events. An autorelease pool ensures that objects created during each run loop iteration are released immediately.

```objective-c
while (!shouldExit && httpServer.running) {
    @autoreleasepool {
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode 
                              beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    }
}
```

---

## Lifecycle: init and dealloc

Proper resource management extends beyond memory. `dealloc` is the last chance to release non-memory resources like file handles, database connections, or C-style allocations.

### Best Practices
- **Do not** call `[super dealloc]`. ARC does this automatically.
- **Do** invalidate timers (to break retain cycles).
- **Do** close database connections or file handles.
- **Do** release CF types (`CFRelease`).

#### Example: Resource Cleanup (ActorStore.m)
`ActorStore` manages a SQLite connection and a Core Foundation signing key. `dealloc` ensures these are closed/released cleanly.

```objective-c
- (void)dealloc {
    [self close];
}

- (void)close {
    if (!self.open) {
        return;
    }
    
    // Clear caches to release memory immediately
    [self.stmtCache removeAllObjects];
    [self.blobCache removeAllObjects];
    
    // Release C-API resources
    if (self.signingKey) {
        CFRelease(self.signingKey);
        self.signingKey = NULL;
    }
    
    // Close SQLite connection
    sqlite3_close(self.db);
    self.db = NULL;
    self.open = NO;
}
```

### Common Pitfall: Retain Cycles in Timers
**Warning:** `NSTimer` retains its target. If the target (e.g., `self`) also retains the timer, `dealloc` will never be called, and the timer will fire forever. You must explicitly invalidate the timer (e.g., in a `stop` or `close` method) to break the cycle. You cannot rely on `dealloc` to invalidate the timer because `dealloc` will never run!
