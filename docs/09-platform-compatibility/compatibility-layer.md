---
title: Compatibility Layer
---

# Compatibility Layer

## Overview

The compatibility layer provides platform-agnostic abstractions for platform-specific functionality. It:
- Abstracts macOS and Linux/GNUstep differences
- Provides unified APIs for common operations
- Handles conditional compilation
- Manages platform-specific dependencies
- Enables code reuse across platforms

## Architecture

### Compatibility Shims

```

┌─────────────────────────────────────────────────────────┐
│              Application Code                           │
│  (Uses unified APIs from compatibility layer)           │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │      Compatibility Layer (Compat/)              │
        │  ┌──────────────────────────────────────────┐  │
        │  │ Logging (os/log.h shim)                  │  │
        │  │ Security (Security.framework shim)       │  │
        │  │ Crypto (CommonCrypto shim)               │  │
        │  │ Network (NSURLSession shim)              │  │
        │  └──────────────────────────────────────────┘  │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
   ┌────▼────────┐        ┌──────▼──────┐
   │   macOS     │        │   Linux/    │
   │  (Xcode)    │        │  GNUstep    │
   │             │        │             │
   │ - os/log.h  │        │ - syslog    │
   │ - Security  │        │ - OpenSSL   │
   │ - CommonCrypto       │ - GnuTLS    │
   │ - NSURLSession       │ - libcurl   │
   └─────────────┘        └─────────────┘
```

## Foundation Framework Compatibility

### Problem: Foundation Differences

macOS uses Apple's Foundation framework, while Linux/GNUstep uses GNUstep's Foundation implementation. Some APIs differ between platforms.

### Solution: Foundation Shim

The compatibility layer provides a unified Foundation import:

```objc
// In ATProtoPDS/Sources/Compat/Foundation/Foundation.h
#ifndef Foundation_h
#define Foundation_h

#ifdef __APPLE__
#import <Foundation/Foundation.h>
#else
#import <GNUstepBase/Foundation.h>
#endif

#endif /* Foundation_h */
```

### NSError Compatibility

```objc
// In ATProtoPDS/Sources/Compat/Foundation/NSErrorCompat.h
#ifdef __APPLE__
#import <Foundation/Foundation.h>
#else
#import <GNUstepBase/NSError+GNUstepBase.h>
#endif
```

### NSData Compatibility

GNUstep's NSData lacks some methods available on macOS:

```objc
// In ATProtoPDS/Sources/Compat/Foundation/NSDataCompat.h
#if !defined(__APPLE__)

typedef NSUInteger NSDataReadingOptions;

@interface NSData (GNUstepCompat)

+ (nullable NSData *)dataWithContentsOfFile:(NSString *)path
                                    options:(NSDataReadingOptions)readOptionsMask
                                      error:(NSError * _Nullable * _Nullable)errorPtr;

@end

#endif
```

### XCTest Compatibility

Linux/GNUstep doesn't have native XCTest. The compatibility layer provides XCTest-compatible testing:

```objc
// In ATProtoPDS/Sources/Compat/LinuxXCTestCompat.h
#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else

#import <Foundation/Foundation.h>

@interface XCTestCase : NSObject
- (void)setUp;
- (void)tearDown;
@end

@interface XCTestSuite : XCTestCase
+ (id)defaultTestSuite;
- (void)addTest:(XCTestCase *)test;
@end

// Assertion macros
#define XCTAssertTrue(condition) do { if (!(condition)) { NSLog(@"XCTAssertTrue failed: %s", #condition); abort(); } } while(0)
#define XCTAssertEqual(a, b) do { if ((a) != (b)) { NSLog(@"XCTAssertEqual failed: %@ != %@", @(a), @(b)); abort(); } } while(0)
#define XCTAssertEqualObjects(a, b) do { if (![(a) isEqual:(b)]) { NSLog(@"XCTAssertEqualObjects failed: %@ != %@", a, b); abort(); } } while(0)
#define XCTAssertNotNil(obj) do { if ((obj) == nil) { NSLog(@"XCTAssertNotNil failed: %s is nil", #obj); abort(); } } while(0)

#endif
```

### Type Compatibility

The compatibility layer defines platform-specific type macros:

```objc
// In ATProtoPDS/Sources/Compat/PDSTypes.h
#if !defined(__APPLE__)
#import "Foundation/NSDataCompat.h"

// CF Bridging macros for ARC (GNUstep doesn't define these)
#ifndef CFBridgingRelease
#define CFBridgingRelease(x) ((__bridge_transfer id)(x))
#endif
#ifndef CFBridgingRetain
#define CFBridgingRetain(x) ((__bridge_retained CFTypeRef)(x))
#endif
#endif

/**
 * @def PDS_GCD_OBJC_SUPPORT
 * @brief Whether platform supports GCD Objective-C integration.
 *
 * macOS: 1 (GCD with Objective-C object support)
 * Linux: 0 (libdispatch without full Objective-C integration)
 */
#if defined(__APPLE__)
#define PDS_GCD_OBJC_SUPPORT 1
#else
#define PDS_GCD_OBJC_SUPPORT 0
#endif

/**
 * @def PDS_DISPATCH_QUEUE_STRONG
 * @brief Property attribute for dispatch queue storage.
 *
 * macOS: strong (dispatch_queue_t supports ARC)
 * Linux: assign (dispatch_queue_t is not ARC-compatible)
 */
#if PDS_GCD_OBJC_SUPPORT
#define PDS_DISPATCH_QUEUE_STRONG strong
#else
#define PDS_DISPATCH_QUEUE_STRONG assign
#endif
```

### Usage Pattern

```objc
// In source files, use the compatibility imports
#import "Compat/Foundation/Foundation.h"
#import "Compat/PDSTypes.h"

// Use platform-agnostic APIs
NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];

// Use dispatch queues with correct property attributes
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t transportQueue;
```

## Platform-Specific Network I/O

### Problem: Network APIs Differ

macOS provides the modern Network framework (NW), while Linux uses BSD sockets. Both need to be abstracted.

### Solution: Network Transport Abstraction

The compatibility layer defines a unified protocol for network operations:

```objc
// In ATProtoPDS/Sources/Network/PDSNetworkTransport.h
@protocol PDSNetworkConnection <PDSNetworkTransport>

/*! Callback invoked when connection state changes. */
@property (nonatomic, copy, nullable) void (^stateChangedHandler)(PDSNetworkConnectionState state, NSError * _Nullable error);

/*! The remote peer's IP address (for logging/rate limiting). */
@property (nonatomic, readonly, nullable) NSString *remoteAddress;

/*!
 @method sendData:completion:
 @abstract Sends data over the connection.
 @param data The bytes to transmit.
 @param completion Callback with error if transmission failed.
 */
- (void)sendData:(NSData *)data completion:(void (^ _Nullable)(NSError * _Nullable error))completion;

/*!
 @method receiveWithMinimumLength:maximumLength:completion:
 @abstract Receives data from the connection.
 @param minLength Minimum bytes to receive before calling completion.
 @param maxLength Maximum bytes to receive in a single callback.
 @param completion Callback with received data, completion flag, and error.
 */
- (void)receiveWithMinimumLength:(NSUInteger)minLength
                  maximumLength:(NSUInteger)maxLength
                     completion:(void (^)(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error))completion;

@end

@protocol PDSNetworkListener <PDSNetworkTransport>

/*! Callback invoked when listener state changes. */
@property (nonatomic, copy, nullable) void (^stateChangedHandler)(PDSNetworkListenerState state, NSError * _Nullable error);

/*! Callback invoked when a new connection is accepted. */
@property (nonatomic, copy, nullable) void (^newConnectionHandler)(id<PDSNetworkConnection> connection);

/*! The port the listener is bound to (valid after reaching Ready state). */
@property (nonatomic, readonly) NSUInteger port;

@end

@interface PDSNetworkTransportFactory : NSObject

+ (id<PDSNetworkListener>)createListenerWithPort:(NSUInteger)port;
+ (id<PDSNetworkListener>)createListenerWithHost:(nullable NSString *)host port:(NSUInteger)port;
+ (id<PDSNetworkConnection>)createConnectionWithHost:(NSString *)host port:(NSUInteger)port;

@end
```

### macOS Implementation (Network Framework)

The macOS implementation uses the modern Network framework:

```objc
// In ATProtoPDS/Sources/Network/PDSNetworkTransportMac.m
@implementation PDSNetworkConnectionMac {
    nw_connection_t _connection;
}

- (instancetype)initWithHost:(NSString *)host port:(NSUInteger)port {
    self = [super init];
    if (self) {
        nw_endpoint_t endpoint = nw_endpoint_create_host(host.UTF8String, 
                                                         [[NSString stringWithFormat:@"%lu", (unsigned long)port] UTF8String]);
        nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, 
                                                                     NW_PARAMETERS_DEFAULT_CONFIGURATION);
        _connection = nw_connection_create(endpoint, parameters);
        [self setupHandlers];
    }
    return self;
}

- (void)setupHandlers {
    __weak typeof(self) weakSelf = self;
    nw_connection_set_state_changed_handler(_connection, ^(nw_connection_state_t state, nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        void (^handler)(PDSNetworkConnectionState, NSError * _Nullable) = strongSelf.stateChangedHandler;
        if (handler) {
            PDSNetworkConnectionState pdsState;
            switch (state) {
                case nw_connection_state_waiting: pdsState = PDSNetworkConnectionStateWaiting; break;
                case nw_connection_state_preparing: pdsState = PDSNetworkConnectionStatePreparing; break;
                case nw_connection_state_ready: pdsState = PDSNetworkConnectionStateReady; break;
                case nw_connection_state_failed: pdsState = PDSNetworkConnectionStateFailed; break;
                case nw_connection_state_cancelled: pdsState = PDSNetworkConnectionStateCancelled; break;
                default: pdsState = PDSNetworkConnectionStateWaiting; break;
            }
            NSError *nsError = nil;
            if (error) {
                nsError = (__bridge_transfer NSError *)nw_error_copy_cf_error(error);
            }
            handler(pdsState, nsError);
        }
    });
}

- (void)sendData:(NSData *)data completion:(void (^ _Nullable)(NSError * _Nullable error))completion {
    dispatch_data_t ddata = dispatch_data_create(data.bytes, data.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    nw_connection_send(_connection, ddata, _nw_content_context_default_message, true, ^(nw_error_t sendError) {
        if (completion) {
            NSError *nsError = nil;
            if (sendError) {
                nsError = (__bridge_transfer NSError *)nw_error_copy_cf_error(sendError);
            }
            completion(nsError);
        }
    });
}

@end

@implementation PDSNetworkListenerMac {
    nw_listener_t _listener;
}

- (instancetype)initWithHost:(NSString * _Nullable)host port:(NSUInteger)port {
    self = [super init];
    if (self) {
        _port = port;
        nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, 
                                                                     NW_PARAMETERS_DEFAULT_CONFIGURATION);
        char portStr[16];
        snprintf(portStr, sizeof(portStr), "%lu", (unsigned long)port);
        if (host.length > 0) {
            nw_endpoint_t localEndpoint = nw_endpoint_create_host(host.UTF8String, portStr);
            nw_parameters_set_local_endpoint(parameters, localEndpoint);
            _listener = nw_listener_create(parameters);
        } else {
            _listener = nw_listener_create_with_port(portStr, parameters);
        }

        if (!_listener) {
            return nil;
        }
        
        __weak typeof(self) weakSelf = self;
        nw_listener_set_state_changed_handler(_listener, ^(nw_listener_state_t state, nw_error_t error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            void (^handler)(PDSNetworkListenerState, NSError * _Nullable) = strongSelf.stateChangedHandler;
            if (handler) {
                PDSNetworkListenerState pdsState;
                switch (state) {
                    case nw_listener_state_waiting: pdsState = PDSNetworkListenerStateWaiting; break;
                    case nw_listener_state_ready: 
                        pdsState = PDSNetworkListenerStateReady;
                        strongSelf->_port = nw_listener_get_port(strongSelf->_listener);
                        break;
                    case nw_listener_state_failed: pdsState = PDSNetworkListenerStateFailed; break;
                    case nw_listener_state_cancelled: pdsState = PDSNetworkListenerStateCancelled; break;
                    default: pdsState = PDSNetworkListenerStateWaiting; break;
                }
                NSError *nsError = nil;
                if (error) {
                    nsError = (__bridge_transfer NSError *)nw_error_copy_cf_error(error);
                }
                handler(pdsState, nsError);
            }
        });

        nw_listener_set_new_connection_handler(_listener, ^(nw_connection_t connection) {
            if (!connection) return;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            void (^handler)(id<PDSNetworkConnection>) = strongSelf.newConnectionHandler;
            if (handler) {
                PDSNetworkConnectionMac *pdsConn = [[PDSNetworkConnectionMac alloc] initWithConnection:connection];
                handler(pdsConn);
            }
        });
    }
    return self;
}

@end
```

### Linux Implementation (BSD Sockets)

The Linux implementation uses BSD sockets with dispatch sources for async I/O:

```objc
// In ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m
@implementation PDSNetworkConnectionLinux {
    int _sockfd;
    dispatch_source_t _connectSource;
    dispatch_source_t _readSource;
    dispatch_source_t _writeSource;
    dispatch_queue_t _queue;
    NSMutableData *_inputBuffer;
    NSMutableArray<PDSReadRequest *> *_readRequests;
    NSMutableData *_writeBuffer;
    NSUInteger _writeOffset;
}

- (instancetype)initWithHost:(NSString *)host port:(NSUInteger)port {
    self = [super init];
    if (self) {
        _sockfd = -1;
        _host = [host copy];
        _port = port;
        _remoteAddress = [NSString stringWithFormat:@"%@:%lu", host, (unsigned long)port];
        _inputBuffer = [NSMutableData data];
        _readRequests = [NSMutableArray array];
        _writeBuffer = [NSMutableData data];
        _writeOffset = 0;
    }
    return self;
}

- (void)startWithQueue:(dispatch_queue_t)queue {
    _queue = queue;
    if (_sockfd == -1) {
        dispatch_async(queue, ^{
            [self beginOutboundConnect];
        });
        return;
    }
    [self setupSources];
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkConnectionStateReady, nil);
    }
}

- (void)beginOutboundConnect {
    char portString[16];
    snprintf(portString, sizeof(portString), "%lu", (unsigned long)_port);

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    hints.ai_family = AF_UNSPEC;

    struct addrinfo *res = NULL;
    int gai = getaddrinfo([_host UTF8String], portString, &hints, &res);
    if (gai != 0 || res == NULL) {
        if (self.stateChangedHandler) {
            NSString *message = gai != 0 ? [NSString stringWithUTF8String:gai_strerror(gai)] : @"No address candidates";
            self.stateChangedHandler(PDSNetworkConnectionStateFailed,
                                     [NSError errorWithDomain:@"PDSNetworkTransport"
                                                         code:-2
                                                     userInfo:@{NSLocalizedDescriptionKey: message ?: @"Address resolution failed"}]);
        }
        return;
    }

    _connectAddrInfo = res;
    _connectAddrInfoCurrent = res;
    [self startConnectToNextCandidate];
}

- (void)startConnectToNextCandidate {
    while (_connectAddrInfoCurrent != NULL) {
        struct addrinfo *ai = _connectAddrInfoCurrent;
        _connectAddrInfoCurrent = ai->ai_next;

        int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd == -1) {
            continue;
        }

        int flags = fcntl(fd, F_GETFL, 0);
        if (flags == -1 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1) {
            close(fd);
            continue;
        }

        int result = connect(fd, ai->ai_addr, (socklen_t)ai->ai_addrlen);
        if (result == 0) {
            _sockfd = fd;
            [self setupSources];
            if (self.stateChangedHandler) {
                self.stateChangedHandler(PDSNetworkConnectionStateReady, nil);
            }
            return;
        }

        if (errno == EINPROGRESS) {
            _sockfd = fd;
            __weak typeof(self) weakSelf = self;
            _connectSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, _sockfd, 0, _queue);
            dispatch_source_set_event_handler(_connectSource, ^{
                [weakSelf handleConnectCompletion];
            });
            dispatch_resume(_connectSource);
            return;
        }

        close(fd);
    }

    NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno 
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to connect"}];
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkConnectionStateFailed, error);
    }
}

- (void)setupSources {
    __weak typeof(self) weakSelf = self;
    
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _sockfd, 0, _queue);
    dispatch_source_set_event_handler(_readSource, ^{
        [weakSelf handleRead];
    });
    dispatch_resume(_readSource);
}

- (void)handleRead {
    uint8_t buffer[4096];
    ssize_t received = recv(_sockfd, buffer, sizeof(buffer), 0);
    
    if (received > 0) {
        [_inputBuffer appendBytes:buffer length:received];
        [self processReadRequests:NO error:nil];
    } else if (received == 0) {
        [self processReadRequests:YES error:nil];
        [self cancel];
    } else {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return;
        }
        NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        [self processReadRequests:YES error:error];
        [self cancel];
    }
}

- (void)sendData:(NSData *)data completion:(void (^ _Nullable)(NSError * _Nullable error))completion {
    if (![self isOnTransportQueue] && _queue != NULL) {
        NSData *copiedData = [data copy];
        void (^copiedCompletion)(NSError * _Nullable) = completion ? [completion copy] : nil;
        dispatch_async(_queue, ^{
            [self sendData:copiedData completion:copiedCompletion];
        });
        return;
    }

    if (_sockfd == -1) {
        if (completion) {
            completion([NSError errorWithDomain:NSPOSIXErrorDomain
                                           code:ENOTCONN
                                       userInfo:@{NSLocalizedDescriptionKey: @"Socket is not connected"}]);
        }
        return;
    }

    ssize_t sent = send(_sockfd, data.bytes, data.length, 0);
    
    if (sent == -1) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            [_writeBuffer setData:data];
            _writeOffset = 0;
            [self ensureWriteSource];
            return;
        }
        NSError *sendError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        if (completion) completion(sendError);
        return;
    } else if ((NSUInteger)sent < data.length) {
        [_writeBuffer setData:data];
        _writeOffset = sent;
        [self ensureWriteSource];
        return;
    }

    if (completion) completion(nil);
}

@end

@implementation PDSNetworkListenerLinux {
    int _listenfd;
    dispatch_source_t _source;
    dispatch_queue_t _queue;
}

- (void)startWithQueue:(dispatch_queue_t)queue {
    _queue = queue;
    
    _listenfd = socket(AF_INET, SOCK_STREAM, 0);
    if (_listenfd == -1) {
        [self failWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]];
        return;
    }
    
    int opt = 1;
    setsockopt(_listenfd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons((uint16_t)_port);
    
    if (bind(_listenfd, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
        NSError *bindError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        close(_listenfd);
        _listenfd = -1;
        [self failWithError:bindError];
        return;
    }
    
    if (listen(_listenfd, 128) == -1) {
        [self failWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]];
        return;
    }
    
    // Set non-blocking
    int flags = fcntl(_listenfd, F_GETFL, 0);
    fcntl(_listenfd, F_SETFL, flags | O_NONBLOCK);
    
    __weak typeof(self) weakSelf = self;
    _source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _listenfd, 0, _queue);
    dispatch_source_set_event_handler(_source, ^{
        [weakSelf handleAccept];
    });
    
    dispatch_resume(_source);
    
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkListenerStateReady, nil);
    }
}

- (void)handleAccept {
    struct sockaddr_in addr;
    socklen_t addrlen = sizeof(addr);
    int clientfd = accept(_listenfd, (struct sockaddr *)&addr, &addrlen);
    if (clientfd == -1) return;
    
    if (self.newConnectionHandler) {
        NSString *address = [NSString stringWithUTF8String:inet_ntoa(addr.sin_addr)];
        PDSNetworkConnectionLinux *conn = [[PDSNetworkConnectionLinux alloc] initWithSocket:clientfd address:address];
        self.newConnectionHandler(conn);
    } else {
        close(clientfd);
    }
}

@end
```

### Factory Pattern

Both implementations are created through a factory that selects the appropriate implementation:

```objc
// In ATProtoPDS/Sources/Network/PDSNetworkTransport.h
@interface PDSNetworkTransportFactory : NSObject

+ (id<PDSNetworkListener>)createListenerWithPort:(NSUInteger)port;
+ (id<PDSNetworkListener>)createListenerWithHost:(nullable NSString *)host port:(NSUInteger)port;
+ (id<PDSNetworkConnection>)createConnectionWithHost:(NSString *)host port:(NSUInteger)port;

@end
```

The factory implementation is platform-specific:

```objc
// macOS version (in PDSNetworkTransportMac.m)
@implementation PDSNetworkTransportFactory

+ (id<PDSNetworkListener>)createListenerWithPort:(NSUInteger)port {
    return [[PDSNetworkListenerMac alloc] initWithPort:port];
}

+ (id<PDSNetworkConnection>)createConnectionWithHost:(NSString *)host port:(NSUInteger)port {
    return [[PDSNetworkConnectionMac alloc] initWithHost:host port:port];
}

@end

// Linux version (in PDSNetworkTransportLinux.m)
#ifndef __APPLE__
@implementation PDSNetworkTransportFactory

+ (id<PDSNetworkListener>)createListenerWithPort:(NSUInteger)port {
    return [[PDSNetworkListenerLinux alloc] initWithPort:port];
}

+ (id<PDSNetworkConnection>)createConnectionWithHost:(NSString *)host port:(NSUInteger)port {
    return [[PDSNetworkConnectionLinux alloc] initWithHost:host port:port];
}

@end
#endif
```

### Usage Pattern

Application code uses the factory without knowing the platform:

```objc
// In application code
id<PDSNetworkListener> listener = [PDSNetworkTransportFactory createListenerWithPort:2583];

listener.stateChangedHandler = ^(PDSNetworkListenerState state, NSError *error) {
    if (state == PDSNetworkListenerStateReady) {
        NSLog(@"Listening on port %lu", listener.port);
    }
};

listener.newConnectionHandler = ^(id<PDSNetworkConnection> connection) {
    connection.stateChangedHandler = ^(PDSNetworkConnectionState state, NSError *error) {
        if (state == PDSNetworkConnectionStateReady) {
            NSLog(@"Connection from %@", connection.remoteAddress);
        }
    };
    
    [connection receiveWithMinimumLength:1 maximumLength:4096 
                              completion:^(NSData *data, BOOL isComplete, NSError *error) {
        if (data) {
            NSLog(@"Received %lu bytes", data.length);
        }
    }];
};

[listener startWithQueue:dispatch_get_main_queue()];
```

## CommonCrypto Compatibility

### Problem: CommonCrypto on GNUstep

macOS provides `CommonCrypto` for cryptographic operations, but GNUstep uses OpenSSL.

### Solution: Crypto Shim

```objc
// In ATProtoPDS/Sources/Compat/PDSCrypto.h
#ifndef PDS_CRYPTO_H
#define PDS_CRYPTO_H

#import <Foundation/Foundation.h>

@interface PDSCryptoManager : NSObject

+ (NSData *)sha256:(NSData *)data;
+ (NSData *)sha1:(NSData *)data;
+ (NSData *)hmacSHA256:(NSData *)data withKey:(NSData *)key;
+ (NSData *)generateECDSAP256KeyPair:(NSData **)publicKey error:(NSError **)error;
+ (NSData *)signData:(NSData *)data withPrivateKey:(NSData *)privateKey error:(NSError **)error;
+ (BOOL)verifySignature:(NSData *)signature 
               forData:(NSData *)data 
          withPublicKey:(NSData *)publicKey 
                 error:(NSError **)error;

@end

#endif
```

### Implementation

```objc
// In ATProtoPDS/Sources/Compat/PDSCrypto.m
#import "PDSCrypto.h"

#if __APPLE__
    #import <CommonCrypto/CommonCrypto.h>
#else
    #import <openssl/sha.h>
    #import <openssl/hmac.h>
    #import <openssl/ec.h>
    #import <openssl/ecdsa.h>
#endif

@implementation PDSCryptoManager

+ (NSData *)sha256:(NSData *)data {
#if __APPLE__
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
#else
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256_CTX ctx;
    SHA256_Init(&ctx);
    SHA256_Update(&ctx, data.bytes, data.length);
    SHA256_Final(digest, &ctx);
    return [NSData dataWithBytes:digest length:SHA256_DIGEST_LENGTH];
#endif
}

+ (NSData *)hmacSHA256:(NSData *)data withKey:(NSData *)key {
#if __APPLE__
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
#else
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digestLength = 0;
    
    HMAC(EVP_sha256(), key.bytes, (int)key.length, data.bytes, (int)data.length, 
         digest, &digestLength);
    
    return [NSData dataWithBytes:digest length:digestLength];
#endif
}

+ (NSData *)generateECDSAP256KeyPair:(NSData **)publicKey 
                               error:(NSError **)error {
#if __APPLE__
    // Use Security.framework on macOS
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256
    };
    
    SecKeyRef privateKeyRef = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, 
                                                    (CFErrorRef *)error);
    if (!privateKeyRef) {
        return nil;
    }
    
    SecKeyRef publicKeyRef = SecKeyCopyPublicKey(privateKeyRef);
    
    NSData *privateKeyData = (__bridge_transfer NSData *)SecKeyCopyExternalRepresentation(privateKeyRef, 
                                                                                          (CFErrorRef *)error);
    *publicKey = (__bridge_transfer NSData *)SecKeyCopyExternalRepresentation(publicKeyRef, 
                                                                              (CFErrorRef *)error);
    
    CFRelease(privateKeyRef);
    CFRelease(publicKeyRef);
    
    return privateKeyData;
#else
    // Use OpenSSL on GNUstep
    EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
    if (!ecKey) {
        *error = [NSError errorWithDomain:@"PDSCrypto" code:1 
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to create EC key"}];
        return nil;
    }
    
    if (!EC_KEY_generate_key(ecKey)) {
        EC_KEY_free(ecKey);
        *error = [NSError errorWithDomain:@"PDSCrypto" code:2 
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate key"}];
        return nil;
    }
    
    // Extract private key
    const BIGNUM *priv = EC_KEY_get0_private_key(ecKey);
    int privLen = BN_num_bytes(priv);
    unsigned char *privBytes = malloc(privLen);
    BN_bn2bin(priv, privBytes);
    NSData *privateKeyData = [NSData dataWithBytes:privBytes length:privLen];
    free(privBytes);
    
    // Extract public key
    const EC_POINT *pub = EC_KEY_get0_public_key(ecKey);
    int pubLen = EC_POINT_point2oct(EC_KEY_get0_group(ecKey), pub, 
                                    POINT_CONVERSION_UNCOMPRESSED, NULL, 0, NULL);
    unsigned char *pubBytes = malloc(pubLen);
    EC_POINT_point2oct(EC_KEY_get0_group(ecKey), pub, POINT_CONVERSION_UNCOMPRESSED, 
                       pubBytes, pubLen, NULL);
    *publicKey = [NSData dataWithBytes:pubBytes length:pubLen];
    free(pubBytes);
    
    EC_KEY_free(ecKey);
    
    return privateKeyData;
#endif
}

@end
```

## Conditional Compilation

### Platform Detection

```objc
// In ATProtoPDS/Sources/Compat/PDSPlatform.h
#ifndef PDS_PLATFORM_H
#define PDS_PLATFORM_H

#if __APPLE__
    #define PDS_PLATFORM_MACOS 1
    #define PDS_PLATFORM_LINUX 0
#elif TARGET_OS_LINUX
    #define PDS_PLATFORM_MACOS 0
    #define PDS_PLATFORM_LINUX 1
#else
    #error "Unsupported platform"
#endif

// Platform-specific macros
#if PDS_PLATFORM_MACOS
    #define PDS_AVAILABLE_MACOS(version) __attribute__((availability(macos, introduced=version)))
    #define PDS_AVAILABLE_LINUX(version)
#else
    #define PDS_AVAILABLE_MACOS(version)
    #define PDS_AVAILABLE_LINUX(version)
#endif

#endif
```

### Usage

```objc
// In source files
#import "PDSPlatform.h"

#if PDS_PLATFORM_MACOS
    // macOS-specific code
    [self setupMacOSSpecificFeatures];
#elif PDS_PLATFORM_LINUX
    // Linux/GNUstep-specific code
    [self setupLinuxSpecificFeatures];
#endif
```

## ARC Runtime Compatibility

### Problem: ARC on GNUstep

Both macOS and GNUstep support ARC, but with different runtime implementations.

### Solution: ARC Shim

```objc
// In ATProtoPDS/Sources/Compat/PDSMemory.h
#ifndef PDS_MEMORY_H
#define PDS_MEMORY_H

#import <Foundation/Foundation.h>

@interface PDSMemoryManager : NSObject

+ (void)autoreleasePool:(void (^)(void))block;
+ (void)retainObject:(id)object;
+ (void)releaseObject:(id)object;
+ (NSUInteger)retainCount:(id)object;

@end

#endif
```

### Implementation

```objc
// In ATProtoPDS/Sources/Compat/PDSMemory.m
#import "PDSMemory.h"

@implementation PDSMemoryManager

+ (void)autoreleasePool:(void (^)(void))block {
    @autoreleasepool {
        block();
    }
}

+ (void)retainObject:(id)object {
    // ARC handles this automatically
    // This is for explicit reference counting if needed
    #if !__has_feature(objc_arc)
        [object retain];
    #endif
}

+ (void)releaseObject:(id)object {
    // ARC handles this automatically
    #if !__has_feature(objc_arc)
        [object release];
    #endif
}

+ (NSUInteger)retainCount:(id)object {
    #if !__has_feature(objc_arc)
        return [object retainCount];
    #else
        // ARC: return 1 (simplified)
        return 1;
    #endif
}

@end
```

## Framework Availability

### Checking Framework Availability

```objc
// In PDSApplication.m
- (void)initializeCompatibilityLayer {
    // Check for macOS-specific frameworks
    #if __APPLE__
        if (@available(macOS 10.15, *)) {
            // Use os/log.h
            [self setupOSLogging];
        } else {
            // Fall back to NSLog
            [self setupNSLogging];
        }
    #else
        // GNUstep: use syslog
        [self setupSyslogLogging];
    #endif
}
```

## Testing Compatibility

### Platform-Specific Tests

```objc
// In ATProtoPDS/Tests/CompatibilityTests.m
@interface CompatibilityTests : XCTestCase
@end

@implementation CompatibilityTests

- (void)testLoggingShim {
    // Test logging on both platforms
    PDSLog("Test message");
    XCTAssertTrue(YES);  // If we get here, logging works
}

- (void)testCryptoShim {
    NSData *randomData = [PDSCryptoManager generateRandomBytes:32];
    XCTAssertEqual(randomData.length, 32);
}

- (void)testSecurityShim {
    NSData *encrypted = [PDSSecurityManager encryptData:[@"test" dataUsingEncoding:NSUTF8StringEncoding]
                                                withKey:[@"key" dataUsingEncoding:NSUTF8StringEncoding]
                                                  error:nil];
    XCTAssertNotNil(encrypted);
}

#if PDS_PLATFORM_MACOS
- (void)testMacOSSpecificFeatures {
    // macOS-specific tests
}
#endif

#if PDS_PLATFORM_LINUX
- (void)testLinuxSpecificFeatures {
    // Linux-specific tests
}
#endif

@end
```

## Best Practices

1. **Use compatibility shims** — Never use platform-specific APIs directly
2. **Centralize platform detection** — Use PDSPlatform.h for all checks
3. **Test on both platforms** — Verify code works on macOS and Linux
4. **Document platform differences** — Clearly mark platform-specific behavior
5. **Minimize conditional compilation** — Keep #if blocks small and focused
6. **Provide fallbacks** — Always have a fallback for unsupported features
7. **Use feature detection** — Check for features, not just platform
8. **Keep shims simple** — Avoid complex logic in compatibility layer

## Common Pitfalls

1. **Forgetting GNUstep limitations** — NSURLSession is declarations-only
2. **Using macOS-only frameworks** — Security.framework, os/log.h
3. **Assuming CommonCrypto availability** — Use OpenSSL on GNUstep
4. **Incorrect conditional compilation** — Use TARGET_OS_LINUX, not __linux__
5. **Memory management differences** — ARC works differently on GNUstep
6. **Missing error handling** — Platform-specific code may fail differently

## Related Deep Dives

- [macOS vs GNUstep Boundary](./macos-vs-gnustep-boundary)

## Next Steps

- **[Network Transport](network-transport)** — Platform-specific network I/O
- **[ARC Runtime](arc-runtime)** — ARC considerations
- **[macOS/Linux](macos-linux)** — Platform overview
