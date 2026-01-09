# Objective-C Coding Guidelines & Tips

> **Status:** Draft
> **Scope:** ATProtoPDS Project

This comprehensive guide aggregates best practices for Objective-C development within the `ATProtoPDS` project. It covers modern syntax, memory management, architectural patterns, and runtime features.

---

## Part 1: Modern Objective-C

Adopting "Modern" Objective-C features improves code safety, readability, and Swift interoperability.

### 1. Nullability Annotations

Nullability annotations help the compiler enforce nil-safety and improve interoperability with Swift.

*   `nonnull` (or `_Nonnull`): The value cannot be nil.
*   `nullable` (or `_Nullable`): The value can be nil.
*   `null_unspecified` (or `_Null_unspecified`): The compiler makes no assumptions (legacy behavior).

**Recommendation:** Wrap all new headers in `NS_ASSUME_NONNULL_BEGIN` and `NS_ASSUME_NONNULL_END`. This allows you to assume `nonnull` by default and only annotate `nullable` items.

**Example (`HandleResolver.h`):**
```objective-c
NS_ASSUME_NONNULL_BEGIN

@interface HandleResolver : NSObject
// ... methods here are assumed to return nonnull and take nonnull arguments
@end

NS_ASSUME_NONNULL_END
```

### 2. Lightweight Generics

Generics provide compile-time type checking for collections.

**Syntax:** `NSArray<NSString *> *`, `NSDictionary<NSString *, NSNumber *> *`

**Example (`PDSDatabase.m`):**
```objective-c
// Returns an array of dictionaries, not just raw objects
- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql error:(NSError **)error;
```

### 3. Literals

Use concise syntax for creating immutable data structures.

*   **Array:** `@[ obj1, obj2 ]` (vs `[NSArray arrayWithObjects:...]`)
*   **Dictionary:** `@{ key : value }` (vs `[NSDictionary dictionaryWithObjects:...]`)
*   **Number:** `@(123)`, `@(YES)`

### 4. Blocks and Typedefs

Use `typedef` to define block signatures for readability.

**Example (`XrpcHandler.h`):**
```objective-c
typedef void (^XrpcMethodHandler)(HttpRequest *request, HttpResponse *response);
```

### 5. Grand Central Dispatch (GCD)

*   **Singletons:** Use `dispatch_once`.
*   **Synchronization:** Use serial queues (`dispatch_queue_create`) and `dispatch_sync` to protect mutable state instead of `@synchronized(self)`.

---

## Part 2: Memory Management & Safety

The project uses Automatic Reference Counting (ARC).

### 1. Retain Cycles: Blocks vs Delegates

**Block Capture (Weak/Strong Dance):**
When a block captures `self`, it creates a strong reference. If `self` owns the block, this creates a retain cycle.

```objective-c
__weak typeof(self) weakSelf = self;
self.completionBlock = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    [strongSelf doSomething];
};
```

**Delegates:**
Delegates must **always** be `weak`.

```objective-c
@property (nonatomic, weak, nullable) id<MyDelegate> delegate;
```

### 2. Property Attributes

| Attribute | Usage | Example |
|-----------|-------|---------|
| `assign` | Primitives (`NSInteger`, `BOOL`) | `NSInteger count` |
| `copy` | Value objects (`NSString`, `NSArray`) | `NSString *name` |
| `strong` | Owned objects | `NSMutableArray *items` |
| `weak` | Non-owned references | `id<Delegate> delegate` |

### 3. Autorelease Pools

Use `@autoreleasepool` inside tight loops to keep memory footprint low.

```objective-c
while (serverRunning) {
    @autoreleasepool {
        [self handleNextRequest];
    }
}
```

### 4. Lifecycle (init/dealloc)

*   **`dealloc`**: Use this to release resources like `sqlite3` handles, `CFTypeRef` objects (`CFRelease`), or to invalidate `NSTimer`s.
*   **Do not** call `[super dealloc]`.

---

## Part 3: Foundation Patterns

### 1. Singleton Pattern

Thread-safe implementation using `dispatch_once`.

```objective-c
+ (instancetype)sharedInstance {
    static MyClass *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[MyClass alloc] init];
    });
    return shared;
}
```

### 2. Error Handling (`NSError **`)

Follow the standard Cocoa pattern:
1.  Accept `NSError **` as the last argument.
2.  Return `BOOL` or nullable object.
3.  Check `if (error)` before dereferencing.

```objective-c
- (BOOL)performAction:(NSError **)error {
    if (failureCondition) {
        if (error) {
            *error = [NSError errorWithDomain:@"MyDomain" code:1 userInfo:nil];
        }
        return NO;
    }
    return YES;
}
```

### 3. Class Extensions

Use Class Extensions in the `.m` file to declare private properties and read-write overrides of public read-only properties.

```objective-c
// In .m file
@interface MyClass ()
@property (nonatomic, readwrite) NSString *status;
@property (nonatomic, strong) NSMutableArray *internalQueue;
@end
```

---

## Part 4: Runtime Features

While rarely needed for day-to-day coding, understanding the runtime is useful for debugging.

### 1. Introspection

Prefer high-level methods over runtime hacks:
*   `isKindOfClass:`: Check class inheritance.
*   `conformsToProtocol:`: Check capability.
*   `respondsToSelector:`: Check if a method exists.

### 2. Method Swizzling

**Warning:** modifying global behavior is dangerous. If you must swizzle (e.g. for analytics), do it in `+load` using `dispatch_once`.

### 3. Associated Objects

Use `objc_setAssociatedObject` to attach data to categories when you cannot subclass.

```objective-c
objc_setAssociatedObject(self, &kKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
```

---
*Generated by OpenCode Research Agents - Jan 2026*
