---
title: macOS and Linux Compatibility
---

# macOS and Linux Compatibility

## Overview

The PDS targets both macOS and Linux (GNUstep). This document covers platform-specific considerations.

## Platform Differences

### macOS

**Advantages:**
- Native Objective-C runtime
- Xcode IDE support
- System frameworks (Security.framework, CommonCrypto)
- Better performance

**Disadvantages:**
- Limited to Apple hardware
- Requires Xcode for development

### Linux (GNUstep)

**Advantages:**
- Runs on any Linux distribution
- Open-source runtime
- Portable to many architectures

**Disadvantages:**
- Slower than macOS
- Fewer system frameworks
- Requires compatibility shims

## Build Configuration

### macOS Build

```bash
mkdir -p build && cd build
cmake .. \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_OBJC_COMPILER=clang \
  -DBUILD_SECP256K1=ON \
  -DBUILD_TESTS=ON

make -j$(sysctl -n hw.ncpu)
```

### Linux Build

```bash
mkdir build-linux && cd build-linux
cmake .. \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_OBJC_COMPILER=clang \
  -DBUILD_SECP256K1=ON \
  -DBUILD_TESTS=ON

make -j$(nproc)
```

## Conditional Compilation

### Platform Guards

```objc
// In PDSNetworkTransport.m
#if TARGET_OS_LINUX
    // Linux-specific code
    #include <sys/socket.h>
    #include <netinet/in.h>
#elif __APPLE__
    // macOS-specific code
    #include <sys/socket.h>
    #include <netinet/in.h>
#endif
```

### Platform-Specific Implementations

```objc
// In PDSNetworkTransport.m
#if TARGET_OS_LINUX
- (void)setupNetworkTransport {
    // Use custom network I/O for GNUstep
    self.transport = [[PDSNetworkTransportLinux alloc] init];
}
#elif __APPLE__
- (void)setupNetworkTransport {
    // Use NSURLSession on macOS
    self.transport = [[PDSNetworkTransportMac alloc] init];
}
#endif
```

## Compatibility Layer

### Compat Directory

```

ATProtoPDS/Sources/Compat/
├── os_log_compat.h      — Logging compatibility
├── Security_compat.h    — Security framework shims
├── CommonCrypto_compat.h — Crypto compatibility
└── Foundation_compat.h  — Foundation extensions
```

### Logging Compatibility

```objc
// In os_log_compat.h
#if !defined(__APPLE__)
    // GNUstep doesn't have os_log
    #define os_log(log, format, ...) NSLog(format, ##__VA_ARGS__)
    #define os_log_error(log, format, ...) NSLog(format, ##__VA_ARGS__)
#else
    // macOS has os_log
    #import <os/log.h>
#endif
```

### Deprecation Macros

To avoid macro re-definition conflicts that cause parse errors on GNUstep, the deprecated attribute macro is explicitly undefined and redefined:

```objc
// In PDSTypes.h
#ifdef DEPRECATED_MSG_ATTRIBUTE
#undef DEPRECATED_MSG_ATTRIBUTE
#endif

#if defined(__APPLE__)
#define DEPRECATED_MSG_ATTRIBUTE(s) __attribute__((deprecated(s)))
#else
#define DEPRECATED_MSG_ATTRIBUTE(s) __attribute__((deprecated(s)))
#endif
```

### Security Framework Compatibility

```objc
// In Security_compat.h
#if TARGET_OS_LINUX
    // GNUstep doesn't have Security.framework
    // Use OpenSSL instead
    #include <openssl/evp.h>
    #include <openssl/ec.h>
#else
    // macOS has Security.framework
    #import <Security/Security.h>
#endif
```

### Cryptography Compatibility

```objc
// In CommonCrypto_compat.h
#if TARGET_OS_LINUX
    // GNUstep uses OpenSSL
    #include <openssl/sha.h>
    #include <openssl/hmac.h>
    
    #define CC_SHA256_DIGEST_LENGTH SHA256_DIGEST_LENGTH
    #define CC_SHA256(data, len, md) SHA256(data, len, md)
#else
    // macOS uses CommonCrypto
    #import <CommonCrypto/CommonCrypto.h>
#endif
```

## Network I/O

### macOS Network Transport

```objc
// In PDSNetworkTransportMac.m
- (void)sendRequest:(NSURLRequest *)request 
         completion:(void (^)(NSData *data, NSError *error))completion {
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request 
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        completion(data, error);
    }];
    
    [task resume];
}
```

### Linux Network Transport

```objc
// In PDSNetworkTransportLinux.m
- (void)sendRequest:(NSURLRequest *)request 
         completion:(void (^)(NSData *data, NSError *error))completion {
    
    // Use custom socket implementation
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    
    // Connect to host
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(80);
    
    connect(sock, (struct sockaddr *)&addr, sizeof(addr));
    
    // Send request
    NSString *requestStr = [self formatRequest:request];
    send(sock, [requestStr UTF8String], requestStr.length, 0);
    
    // Receive response
    char buffer[4096];
    ssize_t n = recv(sock, buffer, sizeof(buffer), 0);
    NSData *data = [NSData dataWithBytes:buffer length:n];
    
    close(sock);
    
    completion(data, nil);
}
```

## ARC Runtime

### Automatic Reference Counting

Both platforms support ARC:

```objc
// ARC is enabled on both macOS and GNUstep
@interface MyClass : NSObject
@property (nonatomic, strong) NSString *name;  // Strong reference
@property (nonatomic, weak) MyDelegate *delegate;  // Weak reference
@end

// Memory is automatically managed
MyClass *obj = [[MyClass alloc] init];  // Retained
obj = nil;  // Released automatically
```

### Memory Management

```objc
// Avoid manual retain/release
// BAD (manual memory management)
MyClass *obj = [[MyClass alloc] init];
[obj retain];
[obj release];

// GOOD (ARC)
MyClass *obj = [[MyClass alloc] init];
// Automatically released when out of scope
```

## Testing

### Platform-Specific Tests

```objc
// In PDSNetworkTransportTests.m
#if TARGET_OS_LINUX
- (void)testLinuxNetworkTransport {
    PDSNetworkTransportLinux *transport = [[PDSNetworkTransportLinux alloc] init];
    // Test Linux-specific implementation
}
#elif __APPLE__
- (void)testMacNetworkTransport {
    PDSNetworkTransportMac *transport = [[PDSNetworkTransportMac alloc] init];
    // Test macOS-specific implementation
}
#endif
```

### Cross-Platform Tests

```objc
// Tests that run on both platforms
- (void)testRecordCreation {
    // This test runs on both macOS and Linux
    PDSRecordService *service = [[PDSRecordService alloc] initWithApplication:self.app];
    
    [service createRecord:@{@"text": @"Hello"}
              collection:@"app.bsky.feed.post"
                     did:@"did:plc:test123"
              completion:^(NSString *uri, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(uri);
    }];
}
```

## Performance Considerations

### macOS Performance

- Faster due to native runtime
- Better system integration
- More efficient memory management

### Linux Performance

- Slower due to GNUstep overhead
- More memory usage
- Longer startup time

### Optimization Tips

1. **Profile on both platforms** — Performance characteristics differ
2. **Use platform-specific optimizations** — Leverage native features
3. **Test thoroughly** — Ensure compatibility
4. **Monitor resource usage** — Track memory and CPU

## Deployment

### macOS Deployment

```bash
# Build for macOS
mkdir -p build && cd build
cmake ..
make -j$(sysctl -n hw.ncpu)

# Binary location
./bin/kaszlak
```

## Linux Deployment

```bash
# Build for Linux
mkdir build-linux && cd build-linux
cmake ..
make -j$(nproc)

# Binary location
./bin/september

# Or use Docker
docker build -f docker/Dockerfile.gnustep -t atprotopds:latest .
docker run -p 2583:2583 atprotopds:latest
```

## Troubleshooting

### macOS Issues

**Issue:** Xcode not found
```bash
xcode-select --install
```

**Issue:** CMake not found
```bash
brew install cmake
```

### Linux Issues

**Issue:** GNUstep not found
```bash
sudo apt-get install gnustep-make libgnustep-base-dev
```

**Issue:** Clang not found
```bash
sudo apt-get install clang
```

## Best Practices

1. **Use conditional compilation** — Guard platform-specific code
2. **Test on both platforms** — Ensure compatibility
3. **Use compatibility layer** — Abstract platform differences
4. **Document platform differences** — Help developers understand
5. **Monitor performance** — Track metrics on both platforms

## Related Deep Dives

- [macOS vs GNUstep Boundary](./macos-vs-gnustep-boundary)

## Next Steps

- **[Compatibility Layer](compatibility-layer)** — Compat shims
- **[Network Transport](network-transport)** — Network I/O
- **[ARC Runtime](arc-runtime)** — Memory management
