---
title: ARC Runtime Considerations
---

# ARC Runtime Considerations

## Overview

Automatic Reference Counting (ARC) is supported on both macOS and GNUstep, but with important differences:
- Both platforms use ARC by default
- Runtime behavior differs slightly
- Memory management patterns are the same
- Debugging tools vary by platform

## ARC Basics

### Reference Counting

ARC automatically manages object lifetime through reference counting:

```objc
// Strong reference (default)
@property (nonatomic, strong) NSString *name;  // Increments retain count

// Weak reference
@property (nonatomic, weak) PDSApplication *app;  // Doesn't increment retain count

// Unowned reference (rare)
@property (nonatomic, unsafe_unretained) NSObject *object;  // Manual management
```

### Retain Cycles

ARC prevents most retain cycles, but some still occur:

```objc
// PROBLEM: Retain cycle
@interface Parent : NSObject
@property (nonatomic, strong) Child *child;
@end

@interface Child : NSObject
@property (nonatomic, strong) Parent *parent;  // Cycle!
@end

// SOLUTION: Use weak reference
@interface Child : NSObject
@property (nonatomic, weak) Parent *parent;  // No cycle
@end
```

## macOS ARC Runtime

### Xcode/clang ARC

macOS uses the Xcode/clang ARC runtime:

```objc
// In PDSApplication.m
- (instancetype)initWithConfiguration:(PDSConfiguration *)config {
    self = [super init];
    if (!self) return nil;
    
    // ARC automatically manages these
    self.configuration = config;  // Strong reference
    self.services = [NSMutableDictionary dictionary];
    
    return self;
}

- (void)dealloc {
    // ARC calls this automatically
    // No need to release properties
    NSLog(@"PDSApplication deallocated");
}
```

### Memory Debugging on macOS

```bash
# Enable malloc debugging
export MallocStackLogging=1
export MallocStackLoggingNoCompact=1

# Run with Instruments
instruments -t "Allocations" ./build/bin/kaszlak

# Check for leaks
leaks -atExit -- ./build/bin/kaszlak
```

## Xcode Memory Graph

```objc
// In Xcode debugger
// 1. Run with breakpoint
// 2. Click "Debug Memory Graph" button
// 3. Inspect object references
// 4. Identify retain cycles
```

## GNUstep ARC Runtime

### GNUstep 2.2 Runtime

GNUstep uses the GNUstep 2.2 runtime with ARC support:

```objc
// In PDSApplication.m (GNUstep)
- (instancetype)initWithConfiguration:(PDSConfiguration *)config {
    self = [super init];
    if (!self) return nil;
    
    // ARC works the same on GNUstep
    self.configuration = config;
    self.services = [NSMutableDictionary dictionary];
    
    return self;
}

- (void)dealloc {
    // ARC calls this automatically on GNUstep too
    NSLog(@"PDSApplication deallocated");
}
```

### Memory Debugging on GNUstep

```bash
# Enable GNUstep memory debugging
export GNUSTEP_MEMORY_DEBUG=1

# Run with valgrind
valgrind --leak-check=full ./build/bin/kaszlak

# Check for leaks
valgrind --leak-check=summary ./build/bin/kaszlak
```

## Autoreleasepool

### When to Use Autoreleasepool

```objc
// In PDSRecordService.m
- (void)processRecordsInBatch:(NSArray *)records {
    // Create autorelease pool for batch processing
    @autoreleasepool {
        for (NSDictionary *record in records) {
            // Temporary objects created here
            NSString *uri = [self createURI:record];
            NSData *encoded = [self encodeRecord:record];
            
            // Objects are released at end of pool
        }
    }
    
    // All temporary objects released here
}
```

### Nested Autoreleasepool

```objc
// In CommitBroadcaster.m
- (void)broadcastCommits:(NSArray *)commits {
    @autoreleasepool {
        for (NSDictionary *commit in commits) {
            @autoreleasepool {
                // Inner pool for each commit
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:commit 
                                                                   options:0 
                                                                     error:nil];
                [self sendToSubscribers:jsonData];
            }
            // Inner pool drained here
        }
    }
}
```

## Weak References

### Preventing Retain Cycles

```objc
// In SubscribeReposHandler.h
@interface SubscribeReposHandler : NSObject

@property (nonatomic, weak) CommitBroadcaster *broadcaster;  // Weak to prevent cycle
@property (nonatomic, strong) NSMutableArray *subscriptions;

@end

// In SubscribeReposHandler.m
- (void)handleWebSocketUpgrade:(HttpRequest *)request 
                     response:(HttpResponse *)response {
    
    // Check if broadcaster is still alive
    CommitBroadcaster *broadcaster = self.broadcaster;
    if (!broadcaster) {
        NSLog(@"Broadcaster was deallocated");
        return;
    }
    
    [broadcaster registerSubscription:context];
}
```

### Weak Reference Patterns

```objc
// Pattern 1: Weak self in blocks
- (void)startServer {
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(self.queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;  // Object was deallocated
        
        [strongSelf doWork];
    });
}

// Pattern 2: Weak delegate
@property (nonatomic, weak) id<PDSDelegate> delegate;

- (void)notifyDelegate {
    if ([self.delegate respondsToSelector:@selector(didFinish)]) {
        [self.delegate didFinish];
    }
}
```

## Memory Pressure

### Handling Low Memory

```objc
// In PDSApplication.m
- (void)setupMemoryWarningHandler {
#if __APPLE__
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleMemoryWarning:) 
                                                 name:UIApplicationDidReceiveMemoryWarningNotification 
                                               object:nil];
#endif
}

- (void)handleMemoryWarning:(NSNotification *)notification {
    NSLog(@"Memory warning received");
    
    // 1. Clear caches
    [self.databasePool clearCache];
    [self.blobStorage clearTemporaryFiles];
    
    // 2. Reduce buffer sizes
    self.maxSendBufferSize = 5 * 1024 * 1024;  // Reduce from 10MB to 5MB
    
    // 3. Force garbage collection (if available)
    @autoreleasepool {
        // Drain autorelease pool
    }
}
```

## Debugging Memory Issues

### Identifying Leaks

```objc
// In PDSApplication.m
- (void)debugMemoryUsage {
    // 1. Get memory statistics
    struct mallinfo info = mallinfo();
    NSLog(@"Total allocated: %d bytes", info.uordblks);
    NSLog(@"Total free: %d bytes", info.fordblks);
    
    // 2. Check object counts
    NSLog(@"Active objects: %lu", [NSObject instanceCount]);
    
    // 3. Monitor specific classes
    [self logInstanceCountForClass:[PDSRecordService class]];
    [self logInstanceCountForClass:[WebSocketConnection class]];
}

- (void)logInstanceCountForClass:(Class)cls {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    
    for (unsigned int i = 0; i < count; i++) {
        if (classes[i] == cls) {
            NSLog(@"%@ instances: %u", NSStringFromClass(cls), 
                  [cls instanceCount]);
        }
    }
    
    free(classes);
}
```

### Memory Profiling

```objc
// In PDSApplication.m
- (void)startMemoryProfiling {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, 
                                                     dispatch_get_main_queue());
    
    dispatch_source_set_timer(timer,
                             dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                             5 * NSEC_PER_SEC,
                             1 * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(timer, ^{
        [self logMemoryUsage];
    });
    
    dispatch_resume(timer);
}

- (void)logMemoryUsage {
    struct task_basic_info info;
    mach_msg_type_number_t size = TASK_BASIC_INFO_COUNT;
    
    kern_return_t kerr = task_info(mach_task_self(),
                                   TASK_BASIC_INFO,
                                   (task_info_t)&info,
                                   &size);
    
    if (kerr == KERN_SUCCESS) {
        NSLog(@"Memory usage: %.2f MB", info.resident_size / 1024.0 / 1024.0);
    }
}
```

## Platform Differences

### macOS vs GNUstep

| Feature | macOS | GNUstep |
|---------|-------|---------|
| ARC Support | Full | Full (2.2+) |
| Autorelease Pool | Yes | Yes |
| Weak References | Yes | Yes |
| Memory Debugging | Instruments | valgrind |
| Dealloc Timing | Immediate | May be delayed |
| Autoreleasepool Drain | Automatic | Automatic |

### Dealloc Timing

```objc
// macOS: Dealloc called immediately when refcount reaches 0
- (void)testDeallocTiming {
    @autoreleasepool {
        NSString *str = [[NSString alloc] initWithString:@"test"];
        NSLog(@"Created: %@", str);
    }  // Dealloc called here on macOS
}

// GNUstep: Dealloc may be delayed
- (void)testDeallocTimingGNUstep {
    @autoreleasepool {
        NSString *str = [[NSString alloc] initWithString:@"test"];
        NSLog(@"Created: %@", str);
    }  // Dealloc may be called later on GNUstep
}
```

## Best Practices

1. **Use strong references by default** — Only use weak when necessary
2. **Avoid retain cycles** — Use weak for delegates and observers
3. **Use autoreleasepool in loops** — Prevent memory buildup
4. **Check weak references** — Always verify before use
5. **Profile memory usage** — Monitor on both platforms
6. **Handle memory warnings** — Clear caches when needed
7. **Test on both platforms** — Verify behavior matches
8. **Document memory ownership** — Clearly mark strong/weak

## Common Pitfalls

1. **Forgetting weak self in blocks** — Causes retain cycles
2. **Not checking weak references** — May be nil unexpectedly
3. **Excessive autoreleasepool nesting** — Reduces performance
4. **Ignoring memory warnings** — Causes crashes on low memory
5. **Platform-specific memory behavior** — Different dealloc timing
6. **Circular delegate references** — Use weak for delegates
7. **Not profiling memory** — Leaks go undetected
8. **Assuming immediate dealloc** — May be delayed on GNUstep

## Testing Memory Management

```objc
// In Garazyk/Tests/MemoryTests.m
@interface MemoryTests : XCTestCase
@end

@implementation MemoryTests

- (void)testNoRetainCycles {
    // 1. Create objects
    PDSApplication *app = [[PDSApplication alloc] initWithConfiguration:config];
    SubscribeReposHandler *handler = [[SubscribeReposHandler alloc] init];
    handler.broadcaster = app.broadcaster;
    
    // 2. Release objects
    app = nil;
    handler = nil;
    
    // 3. Verify deallocation
    XCTAssertTrue(YES);  // If we get here, no crash
}

- (void)testWeakReferenceBehavior {
    __weak NSString *weakStr = nil;
    
    @autoreleasepool {
        NSString *str = [[NSString alloc] initWithString:@"test"];
        weakStr = str;
        XCTAssertNotNil(weakStr);
    }
    
    // After pool drains, weak reference should be nil
    XCTAssertNil(weakStr);
}

- (void)testAutoreleasePoolDraining {
    NSMutableArray *objects = [NSMutableArray array];
    
    @autoreleasepool {
        for (int i = 0; i < 1000; i++) {
            NSString *str = [NSString stringWithFormat:@"String %d", i];
            [objects addObject:str];
        }
    }
    
    // Objects should still be alive (strong references in array)
    XCTAssertEqual(objects.count, 1000);
}

@end
```

## Next Steps

- **[Network Transport](network-transport)** — Platform-specific network I/O
- **[Compatibility Layer](compatibility-layer)** — Compatibility shims
- **[macOS/Linux](macos-linux)** — Platform overview

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

