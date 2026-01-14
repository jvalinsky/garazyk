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
*   **Synchronization:** Use serial queues (`dispatch_queue_t`) to protect mutable state.
*   **ARC Ownership:** Always use `strong` for queue properties. Using `assign` will lead to immediate deallocation and subsequent crashes when the framework attempts to use the queue.

**Queue Property Standardization:**
Use the `PDS_DISPATCH_QUEUE_STRONG` macro for consistent queue property declarations:

```objc
// Standard queue property declaration
@property (nonatomic, strong) dispatch_queue_t connectionQueue;

// Or use the macro for consistency
PDS_DISPATCH_QUEUE_STRONG dispatch_queue_t connectionQueue;
```

**Queue Naming Convention:**
```objc
// Use reverse domain notation for queue names
dispatch_queue_create("com.atproto.pds.actorstore.transaction", DISPATCH_QUEUE_SERIAL);
dispatch_queue_create("com.atproto.pds.network.events", DISPATCH_QUEUE_CONCURRENT);
```

---

## Part 2: Advanced Technical Patterns

These patterns were established during the stabilization of the PDS server to resolve complex deallocation and synchronization issues.

### 1. Synchronized Server Lifecycle

When stopping a server, you must ensure that all asynchronous callbacks have finished and the underlying system handles are truly closed before allowing the controller to be deallocated.

*   **Wait for State Changes**: Use a `dispatch_semaphore_t` to block the `stop` method until the Network listener signals it has reached the `cancelled` state.
*   **Task Tracking**: Use a `dispatch_group_t` to wrap all active requests or broadcasts. `dispatch_group_enter` when a task starts, `dispatch_group_leave` when it completes. Wait on this group during teardown.

```objective-c
- (void)stop {
    [self.listener cancel];
    // Wait for nw_listener to signal 'cancelled' state
    dispatch_semaphore_wait(self.stopSemaphore, DISPATCH_TIME_FOREVER);
    // Wait for all active async tasks to drain
    dispatch_group_wait(self.taskGroup, DISPATCH_TIME_FOREVER);
}
```

### 2. SQLite Resource Management

To prevent "Database Busy" errors or integrity warnings during teardown (especially in tests with frequent restarts), you must finalize ALL prepared statements.

*   **Aggressive Finalization**: Use `sqlite3_next_stmt` to find any dangling statements and finalize them before closing the `sqlite3` handle.

```objective-c
- (void)close {
    sqlite3_stmt *stmt;
    while ((stmt = sqlite3_next_stmt(self.db, NULL)) != NULL) {
        sqlite3_finalize(stmt);
    }
    sqlite3_close(self.db);
    self.db = NULL;
}
```

### 3. Incremental Network Parsing

When using `Network.framework`, data may arrive in small fragments. Your server must buffer this data rather than assuming a single `receive` call contains a full request.

*   **Buffer Accumulation**: Store incoming data in an `NSMutableData` property until a complete protocol message (e.g., HTTP headers + body) is recognized.

### 4. Protocol Bridging

When accepting new connections from an `nw_listener_t`, you should bridge the low-level connection to a high-level protocol handler immediately.

*   **Handler Pattern**: The server side accepts the `nw_connection_t`, wraps it in a connection object (like `WebSocketConnection`), and calls `start` to initiate the protocol handshake and read loop.

---

## Part 3: Memory Management & Safety

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

#### Core Foundation Object Ownership

When working with Core Foundation objects (SecKeyRef, CFStringRef, etc.), follow strict ownership rules:

**Ownership Contract:**
- If you create or copy a CF object, you own it and must `CFRelease` it
- If you receive a CF object from a function with "Get" or "Copy" in the name, you own it
- If you receive a CF object from a function with "Create" in the name, you own it
- Use `CFRetain` to take ownership of objects you don't own but need to keep

**Example (`KeyManager.m`):**
```objc
// KeyPair creation - we retain the SecKeyRefs
CFRetain(privateKey);
CFRetain(publicKey);

// Dealloc - we release what we retained
- (void)dealloc {
    if (_privateKey) CFRelease(_privateKey);
    if (_publicKey) CFRelease(_publicKey);
}
```

**Example (`ActorStore.m`):**
```objc
// Property declaration - assign for CFTypeRef
@property (nonatomic, assign) SecKeyRef signingKey;

// Cleanup - release if we own it
if (_signingKey) {
    CFRelease(_signingKey);
    _signingKey = NULL;
}
```

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

## Part 4: Security Best Practices

### 1. Input Validation & Bounds Checking

Always validate input data, especially when parsing binary formats or network data:

**CBOR/Binary Parsing:**
```objc
// EventFormatter.m - Bounds checking for CBOR decoding
if (*index >= length) {
    if (error) {
        *error = [NSError errorWithDomain:EventFormatterErrorDomain
                                     code:EventFormatterErrorCodeDecodingFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"Unexpected end of CBOR data"}];
    }
    return nil;
}

// Check for buffer overflow before reading
if (*index + byteLength > length) return nil;
```

**WebAuthn Credential Validation:**
```objc
// WebAuthnVerifier.m - Validate credential data structure
if (authData.length < 37) {
    if (error) *error = [self errorWithCode:1007 message:@"authData too short"];
    return nil;
}

// Check flags before accessing optional data
uint8_t flags = ((const uint8_t *)authData.bytes)[32];
BOOL hasAttestedCredentialData = (flags & 0x40) != 0;
if (!hasAttestedCredentialData) {
    if (error) *error = [self errorWithCode:1008 message:@"No attested credential data"];
    return nil;
}
```

### 2. Network Security Limits

Implement size limits to prevent resource exhaustion attacks:

**WebSocket Frame Size Limit:**
```objc
// WebSocketConnection.m - 16MB max frame size
static const NSUInteger MAX_FRAME_SIZE = 16 * 1024 * 1024; // 16MB

if (frameSize > MAX_FRAME_SIZE) {
    // Close connection with policy violation
    [self closeWithCode:1008 reason:@"Frame too large"];
    return;
}
```

### 3. Memory Safety Patterns

**Prevent Buffer Overflows:**
- Always check array bounds before access
- Use bounded string operations (`strlcpy`, `strlcat`)
- Validate input lengths before allocation

**Prevent Use-After-Free:**
- Set pointers to NULL after `CFRelease`
- Use `weak` references for delegates to avoid retain cycles
- Never access objects after `dealloc`

### 4. Cryptographic Security

**Key Management:**
- Never store private keys in code or configuration files
- Use the Keychain (`SecKeyRef`) for persistent key storage
- Generate random values with `SecRandomCopyBytes`, not `rand()`

**Constant-Time Comparisons:**
```objc
// For sensitive data comparison, use timing-safe approaches
// Note: memcmp is generally sufficient on modern systems
// For high-security contexts, consider custom constant-time implementations
```

---

## Part 5: Runtime Features

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
