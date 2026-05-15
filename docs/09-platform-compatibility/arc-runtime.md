---
title: ARC Runtime Considerations
---

# ARC Runtime Considerations

Automatic Reference Counting (ARC) is supported on both macOS and GNUstep. While the memory management patterns are identical, the underlying runtime behavior and debugging tools differ.

## ARC Basics

ARC manages object lifetimes by tracking references. When the last strong reference to an object is removed, the runtime deallocates it.

### Reference Types

- **Strong** (default): Increments the retain count. The object stays alive as long as a strong reference exists.
- **Weak**: Does not increment the retain count. If the object is deallocated, the reference automatically becomes `nil`.
- **Unsafe Unretained**: Similar to weak but does not zero out when the object is deallocated. Use this only for legacy or specialized low-level code.

### Retain Cycles

Cycles occur when two objects hold strong references to each other, preventing either from being deallocated. We break these by using weak references for child-to-parent links or delegates.

```objc
// Pattern: Weak delegate to prevent cycles
@interface PDSService : NSObject
@property (nonatomic, weak) id<PDSServiceDelegate> delegate;
@end
```

## Platform Runtimes

### macOS (Xcode/Clang)

On macOS, the runtime handles deallocation immediately when the reference count reaches zero. 

#### Memory Debugging
- Enable `MallocStackLogging` to track allocations.
- Use `leaks -atExit` to identify memory that wasn't cleaned up.
- The Xcode Memory Graph provides a visual way to find retain cycles during active debugging.

### GNUstep (Linux)

GNUstep uses the GNUstep 2.2 runtime. While ARC works the same way for developers, the actual `dealloc` call might be slightly delayed compared to macOS.

#### Memory Debugging
- Use `valgrind --leak-check=full` to find leaks on Linux.
- Set `GNUSTEP_MEMORY_DEBUG=1` for additional runtime checks.

## Autoreleasepool

Use `@autoreleasepool` blocks to manage temporary objects in tight loops. This prevents memory spikes by draining temporary objects immediately rather than waiting for the next runloop cycle.

```objc
- (void)processLargeBatch:(NSArray *)items {
    for (id item in items) {
        @autoreleasepool {
            // Temporary objects created here are released at the end of the block.
            [self handleItem:item];
        }
    }
}
```

## Block Memory Management

Blocks capture variables from their surrounding scope. To avoid capturing `self` strongly (which creates a retain cycle if the block is stored in a property of `self`), use the weak-strong dance:

```objc
__weak typeof(self) weakSelf = self;
[self.queue addOperationWithBlock:^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    
    [strongSelf performAction];
}];
```

## Memory Pressure

The server responds to memory warnings by clearing non-essential caches.

- **macOS**: Responds to `UIApplicationDidReceiveMemoryWarningNotification` (or equivalent system events).
- **GNUstep**: Usually requires manual monitoring of RSS or responding to custom signals.

The `PDSApplication` class centralizes this by calling `clearCache` on `databasePool` and `blobStorage`.

## Best Practices

1. Prefer strong references for ownership and weak references for observation or delegation.
2. Always verify a weak reference isn't `nil` before use if the object might have been deallocated.
3. Use autorelease pools inside loops that create many small objects.
4. Profile memory on both platforms; a leak on Linux might not show up clearly on macOS and vice versa.
5. Document ownership in header files if a relationship isn't standard.

## Related

- [Compatibility Layer](./compatibility-layer)
- [macOS vs GNUstep Boundary](./macos-vs-gnustep-boundary)
- [Network Transport](./network-transport)
- [Documentation Map](../11-reference/documentation-map.md)
- [Testing Map](../11-reference/testing-map.md)

