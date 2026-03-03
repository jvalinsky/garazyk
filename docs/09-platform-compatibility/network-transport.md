# Platform-Specific Network Transport

## Overview

Network I/O is implemented differently on macOS and Linux/GNUstep. This document covers:
- Socket-level networking
- Platform-specific transport implementations
- HTTP/HTTPS handling
- WebSocket support
- Connection management

## Architecture

### Network Transport Layer

```
┌─────────────────────────────────────────────────────────┐
│              Application Code                           │
│  (HttpServer, WebSocketConnection)                      │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────▼────────────────────────────────────┐
        │      PDSNetworkTransport (Abstract)             │
        │  - sendData:                                    │
        │  - receiveData:                                 │
        │  - close                                        │
        └────────────┬─────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
   ┌────▼──────────────┐   ┌─────▼──────────────┐
   │ PDSNetworkTransport   │ PDSNetworkTransport │
   │ Mac                   │ Linux               │
   │                       │                     │
   │ - NSURLSession        │ - libcurl           │
   │ - CFNetwork           │ - OpenSSL           │
   │ - Secure Transport    │ - GnuTLS            │
   └───────────────────┘   └─────────────────────┘
```

## macOS Network Transport

### NSURLSession (Limited)

On macOS, `NSURLSession` is available but has limitations for server-side use:

```objc
// In PDSNetworkTransportMac.h
#import <Foundation/Foundation.h>

@interface PDSNetworkTransportMac : NSObject

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, strong) NSData *tlsCertificate;
@property (nonatomic, strong) NSData *tlsPrivateKey;

- (instancetype)initWithPort:(NSInteger)port;
- (void)startWithCompletion:(void (^)(NSError *error))completion;
- (void)stopWithCompletion:(void (^)(void))completion;
- (void)sendData:(NSData *)data toAddress:(NSString *)address error:(NSError **)error;
- (NSData *)receiveDataWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

@end
```

### CFNetwork Implementation

For server-side networking on macOS, use CFNetwork directly:

```objc
// In PDSNetworkTransportMac.m
#import "PDSNetworkTransportMac.h"
#import <CFNetwork/CFNetwork.h>
#import <Security/Security.h>

@interface PDSNetworkTransportMac ()
@property (nonatomic, assign) CFSocketRef serverSocket;
@property (nonatomic, strong) NSMutableArray *clientSockets;
@property (nonatomic, strong) dispatch_queue_t networkQueue;
@end

@implementation PDSNetworkTransportMac

- (instancetype)initWithPort:(NSInteger)port {
    self = [super init];
    if (!self) return nil;
    
    self.port = port;
    self.clientSockets = [NSMutableArray array];
    self.networkQueue = dispatch_queue_create("com.atproto.network.mac", 
                                              DISPATCH_QUEUE_SERIAL);
    
    return self;
}

- (void)startWithCompletion:(void (^)(NSError *error))completion {
    dispatch_async(self.networkQueue, ^{
        // 1. Create socket
        CFSocketContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
        self.serverSocket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, 
                                          IPPROTO_TCP, kCFSocketAcceptCallBack, 
                                          (CFSocketCallBack)&acceptCallback, &context);
        
        if (!self.serverSocket) {
            NSError *error = [NSError errorWithDomain:@"Network" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to create socket"}];
            completion(error);
            return;
        }
        
        // 2. Set socket options
        int optval = 1;
        setsockopt(CFSocketGetNative(self.serverSocket), SOL_SOCKET, SO_REUSEADDR, 
                  &optval, sizeof(optval));
        
        // 3. Bind to port
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_ANY);
        addr.sin_port = htons(self.port);
        
        NSData *addressData = [NSData dataWithBytes:&addr length:sizeof(addr)];
        CFSocketSetAddress(self.serverSocket, (__bridge CFDataRef)addressData);
        
        // 4. Add to run loop
        CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, 
                                                               self.serverSocket, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        CFRelease(source);
        
        completion(nil);
    });
}

static void acceptCallback(CFSocketRef socket, CFSocketCallBackType type, 
                          CFDataRef address, const void *data, void *info) {
    PDSNetworkTransportMac *transport = (__bridge PDSNetworkTransportMac *)info;
    
    if (type == kCFSocketAcceptCallBack) {
        CFSocketNativeHandle clientSocket = *(CFSocketNativeHandle *)data;
        
        // Handle client connection
        [transport handleClientSocket:clientSocket];
    }
}

- (void)handleClientSocket:(CFSocketNativeHandle)clientSocket {
    // 1. Create CFSocket for client
    CFSocketContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    CFSocketRef cfSocket = CFSocketCreateWithNative(kCFAllocatorDefault, clientSocket, 
                                                   kCFSocketDataCallBack, 
                                                   (CFSocketCallBack)&dataCallback, &context);
    
    // 2. Add to run loop
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, cfSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    CFRelease(source);
    
    // 3. Store socket
    [self.clientSockets addObject:(__bridge id)cfSocket];
}

- (void)stopWithCompletion:(void (^)(void))completion {
    dispatch_async(self.networkQueue, ^{
        if (self.serverSocket) {
            CFSocketInvalidate(self.serverSocket);
            CFRelease(self.serverSocket);
            self.serverSocket = NULL;
        }
        
        for (id socket in self.clientSockets) {
            CFSocketRef cfSocket = (__bridge CFSocketRef)socket;
            CFSocketInvalidate(cfSocket);
        }
        
        [self.clientSockets removeAllObjects];
        completion();
    });
}

@end
```

### TLS/SSL on macOS

```objc
// In PDSNetworkTransportMac.m
- (void)setupTLSWithCertificate:(NSData *)certData 
                     privateKey:(NSData *)keyData
                          error:(NSError **)error {
    
    // 1. Load certificate
    SecCertificateRef cert = SecCertificateCreateWithData(kCFAllocatorDefault, 
                                                         (__bridge CFDataRef)certData);
    if (!cert) {
        *error = [NSError errorWithDomain:@"Network" code:1 
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to load certificate"}];
        return;
    }
    
    // 2. Load private key
    NSDictionary *options = @{
        (__bridge id)kSecReturnRef: @YES,
        (__bridge id)kSecReturnData: @YES
    };
    
    CFArrayRef items = NULL;
    SecExternalFormat format = kSecFormatPEMSequence;
    SecExternalItemType itemType = kSecItemTypePrivateKey;
    
    OSStatus status = SecItemImport((__bridge CFDataRef)keyData, NULL, &format, 
                                   &itemType, 0, NULL, NULL, &items);
    
    if (status != errSecSuccess) {
        CFRelease(cert);
        *error = [NSError errorWithDomain:@"Network" code:2 
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to load private key"}];
        return;
    }
    
    self.tlsCertificate = certData;
    self.tlsPrivateKey = keyData;
    
    if (items) CFRelease(items);
    CFRelease(cert);
}
```

## Linux/GNUstep Network Transport

### libcurl Implementation

On Linux/GNUstep, use libcurl for HTTP/HTTPS:

```objc
// In PDSNetworkTransportLinux.h
#import <Foundation/Foundation.h>

@interface PDSNetworkTransportLinux : NSObject

@property (nonatomic, assign) NSInteger port;
@property (nonatomic, strong) NSData *tlsCertificate;
@property (nonatomic, strong) NSData *tlsPrivateKey;

- (instancetype)initWithPort:(NSInteger)port;
- (void)startWithCompletion:(void (^)(NSError *error))completion;
- (void)stopWithCompletion:(void (^)(void))completion;
- (void)sendData:(NSData *)data toAddress:(NSString *)address error:(NSError **)error;
- (NSData *)receiveDataWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

@end
```

### libcurl Implementation

```objc
// In PDSNetworkTransportLinux.m
#import "PDSNetworkTransportLinux.h"
#import <curl/curl.h>
#import <openssl/ssl.h>

@interface PDSNetworkTransportLinux ()
@property (nonatomic, assign) int serverSocket;
@property (nonatomic, strong) dispatch_queue_t networkQueue;
@property (nonatomic, strong) NSMutableArray *clientSockets;
@end

@implementation PDSNetworkTransportLinux

- (instancetype)initWithPort:(NSInteger)port {
    self = [super init];
    if (!self) return nil;
    
    self.port = port;
    self.clientSockets = [NSMutableArray array];
    self.networkQueue = dispatch_queue_create("com.atproto.network.linux", 
                                              DISPATCH_QUEUE_SERIAL);
    
    return self;
}

- (void)startWithCompletion:(void (^)(NSError *error))completion {
    dispatch_async(self.networkQueue, ^{
        // 1. Create socket
        self.serverSocket = socket(AF_INET, SOCK_STREAM, 0);
        if (self.serverSocket < 0) {
            NSError *error = [NSError errorWithDomain:@"Network" code:1 
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to create socket"}];
            completion(error);
            return;
        }
        
        // 2. Set socket options
        int optval = 1;
        setsockopt(self.serverSocket, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));
        
        // 3. Bind to port
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_ANY);
        addr.sin_port = htons(self.port);
        
        if (bind(self.serverSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            NSError *error = [NSError errorWithDomain:@"Network" code:2 
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to bind socket"}];
            completion(error);
            return;
        }
        
        // 4. Listen for connections
        listen(self.serverSocket, SOMAXCONN);
        
        // 5. Accept connections in background
        dispatch_async(self.networkQueue, ^{
            [self acceptConnections];
        });
        
        completion(nil);
    });
}

- (void)acceptConnections {
    while (self.serverSocket >= 0) {
        struct sockaddr_in clientAddr;
        socklen_t clientAddrLen = sizeof(clientAddr);
        
        int clientSocket = accept(self.serverSocket, (struct sockaddr *)&clientAddr, 
                                 &clientAddrLen);
        
        if (clientSocket < 0) {
            if (errno != EINTR) {
                NSLog(@"Accept error: %s", strerror(errno));
            }
            continue;
        }
        
        // Handle client connection
        [self handleClientSocket:clientSocket];
    }
}

- (void)handleClientSocket:(int)clientSocket {
    // 1. Create wrapper
    NSNumber *socketWrapper = @(clientSocket);
    [self.clientSockets addObject:socketWrapper];
    
    // 2. Handle in background
    dispatch_async(self.networkQueue, ^{
        [self processClientSocket:clientSocket];
    });
}

- (void)processClientSocket:(int)clientSocket {
    // 1. Read HTTP request
    char buffer[4096];
    ssize_t bytesRead = read(clientSocket, buffer, sizeof(buffer) - 1);
    
    if (bytesRead < 0) {
        NSLog(@"Read error: %s", strerror(errno));
        close(clientSocket);
        return;
    }
    
    buffer[bytesRead] = '\0';
    
    // 2. Parse request
    NSString *request = [NSString stringWithUTF8String:buffer];
    NSLog(@"Received request: %@", request);
    
    // 3. Send response
    const char *response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n";
    write(clientSocket, response, strlen(response));
    
    // 4. Close connection
    close(clientSocket);
}

- (void)stopWithCompletion:(void (^)(void))completion {
    dispatch_async(self.networkQueue, ^{
        if (self.serverSocket >= 0) {
            close(self.serverSocket);
            self.serverSocket = -1;
        }
        
        for (NSNumber *socketNum in self.clientSockets) {
            close([socketNum intValue]);
        }
        
        [self.clientSockets removeAllObjects];
        completion();
    });
}

@end
```

### OpenSSL/GnuTLS on Linux

```objc
// In PDSNetworkTransportLinux.m
- (void)setupTLSWithCertificate:(NSData *)certData 
                     privateKey:(NSData *)keyData
                          error:(NSError **)error {
    
    // 1. Initialize OpenSSL
    SSL_library_init();
    SSL_load_error_strings();
    
    // 2. Create SSL context
    SSL_CTX *ctx = SSL_CTX_new(TLS_server_method());
    if (!ctx) {
        *error = [NSError errorWithDomain:@"Network" code:1 
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to create SSL context"}];
        return;
    }
    
    // 3. Load certificate
    BIO *certBio = BIO_new_mem_buf((void *)certData.bytes, (int)certData.length);
    X509 *cert = PEM_read_bio_X509(certBio, NULL, NULL, NULL);
    BIO_free(certBio);
    
    if (!cert) {
        SSL_CTX_free(ctx);
        *error = [NSError errorWithDomain:@"Network" code:2 
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to load certificate"}];
        return;
    }
    
    if (SSL_CTX_use_certificate(ctx, cert) <= 0) {
        X509_free(cert);
        SSL_CTX_free(ctx);
        *error = [NSError errorWithDomain:@"Network" code:3 
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to use certificate"}];
        return;
    }
    
    // 4. Load private key
    BIO *keyBio = BIO_new_mem_buf((void *)keyData.bytes, (int)keyData.length);
    EVP_PKEY *pkey = PEM_read_bio_PrivateKey(keyBio, NULL, NULL, NULL);
    BIO_free(keyBio);
    
    if (!pkey) {
        X509_free(cert);
        SSL_CTX_free(ctx);
        *error = [NSError errorWithDomain:@"Network" code:4 
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to load private key"}];
        return;
    }
    
    if (SSL_CTX_use_PrivateKey(ctx, pkey) <= 0) {
        EVP_PKEY_free(pkey);
        X509_free(cert);
        SSL_CTX_free(ctx);
        *error = [NSError errorWithDomain:@"Network" code:5 
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to use private key"}];
        return;
    }
    
    self.tlsCertificate = certData;
    self.tlsPrivateKey = keyData;
    
    EVP_PKEY_free(pkey);
    X509_free(cert);
}
```

## Unified Network Interface

### Abstract Transport

```objc
// In PDSNetworkTransport.h
#import <Foundation/Foundation.h>

@protocol PDSNetworkTransport <NSObject>

- (void)startWithCompletion:(void (^)(NSError *error))completion;
- (void)stopWithCompletion:(void (^)(void))completion;
- (void)sendData:(NSData *)data toAddress:(NSString *)address error:(NSError **)error;
- (NSData *)receiveDataWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;
- (void)setupTLSWithCertificate:(NSData *)certData 
                     privateKey:(NSData *)keyData
                          error:(NSError **)error;

@end
```

### Factory

```objc
// In PDSNetworkTransportFactory.m
#import "PDSNetworkTransportFactory.h"

#if __APPLE__
    #import "PDSNetworkTransportMac.h"
#else
    #import "PDSNetworkTransportLinux.h"
#endif

@implementation PDSNetworkTransportFactory

+ (id<PDSNetworkTransport>)createTransportWithPort:(NSInteger)port {
#if __APPLE__
    return [[PDSNetworkTransportMac alloc] initWithPort:port];
#else
    return [[PDSNetworkTransportLinux alloc] initWithPort:port];
#endif
}

@end
```

## Best Practices

1. **Use platform-specific APIs** — Don't force cross-platform APIs
2. **Handle platform differences** — Test on both macOS and Linux
3. **Implement proper error handling** — Different errors on each platform
4. **Use dispatch queues** — Manage concurrency properly
5. **Clean up resources** — Close sockets and free memory
6. **Monitor performance** — Track throughput and latency
7. **Test under load** — Verify behavior with many connections
8. **Document platform-specific behavior** — Clearly mark differences

## Next Steps

- **[ARC Runtime](./arc-runtime)** — ARC considerations
- **[Compatibility Layer](./compatibility-layer)** — Compatibility shims
- **[macOS/Linux](./macos-linux)** — Platform overview

