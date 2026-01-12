# Foundation & Networking Compatibility

## Networking (`NSURLSession`)

### Usage in `objpds`
- **Locations**: `DID.m`, `ExploreHandler.m`, `HandleResolver.m`, `SSLPinningManager.m`.
- **Pattern**: 
  - `[NSURLSession sharedSession]`
  - `[NSURLSession sessionWithConfiguration:...]`
  - `dataTaskWithURL:completionHandler:`
  - `NSURLSessionDelegate` for SSL pinning.

### GNUstep Status
- **NSURLSession**: **CONFIRMED IMPLEMENTED** in `gnustep-base`.
  - **Source Analysis**: Validated against `reference/gnustep-base/Source/NSURLSession.m`.
  - **Features**: Implements `dataTaskWithRequest`, `uploadTask`, `downloadTask`, and supports delegates.
  - **Backend**: Uses `libcurl` for transport and `libdispatch` (GCD) for event handling (`curl_multi_socket_action`).
  - **Concerns**: Very new implementation (Copyright 2017-2024, significant work in 2024). May have bugs, but architecture is sound.
- **NSURLConnection**: Fully supported legacy fallback.

### Recommendations
1.  **Conditional Compilation**:
    ```objc
    #if TARGET_OS_LINUX || defined(GNUSTEP)
        // Use NSURLConnection or simplified NSURLSession sans-delegate
    #else
        // Use regular NSURLSession
    #endif
    ```
2.  **SSLPinning**: `SSLPinningManager` heavily relies on `NSURLSessionDelegate`. This might need to be `#ifdef`'d out on Linux if OpenSSL configuration via `gnustep-base` handles CA certs differently.

## Grand Central Dispatch (GCD)

### Usage
- **Locations**: Pervasive (`ActorStore`, `PDSDatabase`, `PDSMetrics`).
- **Specifics**: `dispatch_queue_create`, `dispatch_sync`, `dispatch_async`, `dispatch_once`.
- **Type Safety**: Properties like `@property (strong) dispatch_queue_t queue;` are common.

### Linux Differences
- **Type**: On Apple platforms, `dispatch_queue_t` is an OS object (managed by ARC). On Linux (using `libdispatch`), it is often a raw C struct/pointer.
- **Problem**: `strong` attribute on a non-object type will compile error with Clang on Linux.
- **Fix**: Define a macro or use conditional property attributes:
    ```objc
    #if defined(GNUSTEP)
    #define DISPATCH_QUEUE_PROP assign
    #else
    #define DISPATCH_QUEUE_PROP strong
    #endif
    
    @property (nonatomic, DISPATCH_QUEUE_PROP) dispatch_queue_t queue;
    ```
    Alternatively, change all to `assign` and ensure manual `dispatch_retain`/`release` if ARC doesn't manage it (though `libobjc2` might handle it if compiled with `-DOS_OBJECT_USE_OBJC=0`).

## CoreFoundation
- **Usage**: `CFDictionary`, `CFArray` in `HandleResolver`.
- **GNUstep**: `gnustep-corebase` library provides these.
  - **Source Analysis**: `reference/gnustep-corebase/Source/CFDictionary.c` shows implementation wrapping `GSHashTable`.
  - **Bridging**: Explicitly checks `CF_IS_OBJC` and attempts to dispatch to Objective-C methods provided by the runtime, offering a level of "toll-free bridging" emulation.
- **Recommendation**: Although `CoreBase` exists, preferring pure `Foundation` types (`NSDictionary`) is safer to reduce dependency complexity.
