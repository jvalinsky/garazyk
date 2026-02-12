#import "PDSNetworkTransportLinux.h"
#import <Foundation/Foundation.h>

#import "PDSNetworkTransportLinux.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <stdio.h>
#import <unistd.h>
#import <fcntl.h>

#ifndef __APPLE__
@implementation PDSNetworkTransportFactory

+ (id<PDSNetworkListener>)createListenerWithPort:(NSUInteger)port {
    NSString *bindHost = [[NSProcessInfo processInfo] environment][@"PDS_LISTEN_HOST"];
    return [[PDSNetworkListenerLinux alloc] initWithHost:bindHost port:port];
}

+ (id<PDSNetworkListener>)createListenerWithHost:(nullable NSString *)host port:(NSUInteger)port {
    return [[PDSNetworkListenerLinux alloc] initWithHost:host port:port];
}

+ (id<PDSNetworkConnection>)createConnectionWithHost:(NSString *)host port:(NSUInteger)port {
    return [[PDSNetworkConnectionLinux alloc] initWithHost:host port:port];
}

@end
#endif

@interface PDSReadRequest : NSObject
@property (nonatomic, assign) NSUInteger minLength;
@property (nonatomic, assign) NSUInteger maxLength;
@property (nonatomic, copy) void (^completion)(NSData * _Nullable, BOOL, NSError * _Nullable);
@end

@implementation PDSReadRequest
@end

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
	    NSString *_host;
	    NSUInteger _port;
	    struct addrinfo *_connectAddrInfo;
	    struct addrinfo *_connectAddrInfoCurrent;
	    int _connectLastError;
	}

@synthesize stateChangedHandler = _stateChangedHandler;
@synthesize remoteAddress = _remoteAddress;

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

- (instancetype)initWithSocket:(int)sockfd address:(NSString *)address {
    self = [super init];
    if (self) {
        _sockfd = sockfd;
        _remoteAddress = address;
        _inputBuffer = [NSMutableData data];
        _readRequests = [NSMutableArray array];
        _writeBuffer = [NSMutableData data];
        _writeOffset = 0;
        
        int flags = fcntl(_sockfd, F_GETFL, 0);
        fcntl(_sockfd, F_SETFL, flags | O_NONBLOCK);
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

- (void)cleanupConnectState {
    if (_connectSource) {
        dispatch_source_cancel(_connectSource);
        _connectSource = nil;
    }

    if (_connectAddrInfo) {
        freeaddrinfo(_connectAddrInfo);
        _connectAddrInfo = NULL;
    }

    _connectAddrInfoCurrent = NULL;
    _connectLastError = 0;
}

- (void)beginOutboundConnect {
    if (_queue == NULL) {
        return;
    }

    if (_connectAddrInfo) {
        [self cleanupConnectState];
    }

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
            _connectLastError = errno;
            continue;
        }

        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);

        int result = connect(fd, ai->ai_addr, (socklen_t)ai->ai_addrlen);
        if (result == 0) {
            _sockfd = fd;
            [self cleanupConnectState];
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

        _connectLastError = errno;
        close(fd);
    }

    NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:_connectLastError ?: errno userInfo:nil];
    [self cleanupConnectState];

    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkConnectionStateFailed, error);
    }
}

- (void)handleConnectCompletion {
    int error = 0;
    socklen_t len = sizeof(error);
    getsockopt(_sockfd, SOL_SOCKET, SO_ERROR, &error, &len);

    if (_connectSource) {
        dispatch_source_cancel(_connectSource);
        _connectSource = nil;
    }

    if (error != 0) {
        _connectLastError = error;
        if (_sockfd != -1) {
            close(_sockfd);
            _sockfd = -1;
        }

        [self startConnectToNextCandidate];
        return;
    }

    [self cleanupConnectState];
    [self setupSources];
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkConnectionStateReady, nil);
    }
}

- (void)setupSources {
    __weak typeof(self) weakSelf = self;
    
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _sockfd, 0, _queue);
    dispatch_source_set_event_handler(_readSource, ^{
        [weakSelf handleRead];
    });
    dispatch_resume(_readSource);
    
    _writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, _sockfd, 0, _queue);
    dispatch_source_set_event_handler(_writeSource, ^{
        [weakSelf handleWrite];
    });
    dispatch_resume(_writeSource);
    
    dispatch_source_cancel(_writeSource);
    _writeSource = nil;
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

- (void)handleWrite {
    if (_writeBuffer.length == 0) {
        dispatch_source_cancel(_writeSource);
        _writeSource = nil;
        return;
    }
    
    ssize_t sent = send(_sockfd, _writeBuffer.bytes + _writeOffset, _writeBuffer.length - _writeOffset, 0);
    
    if (sent == -1) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return;
        }
        NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        [_writeBuffer setLength:0];
        _writeOffset = 0;
        if (self.stateChangedHandler) {
            self.stateChangedHandler(PDSNetworkConnectionStateFailed, error);
        }
    } else {
        _writeOffset += sent;
        if (_writeOffset >= _writeBuffer.length) {
            [_writeBuffer setLength:0];
            _writeOffset = 0;
            dispatch_source_cancel(_writeSource);
            _writeSource = nil;
        }
    }
}

- (void)processReadRequests:(BOOL)isComplete error:(NSError *)error {
    while (_readRequests.count > 0) {
        PDSReadRequest *request = _readRequests.firstObject;
        
        if (error) {
            request.completion(nil, NO, error);
            [_readRequests removeObjectAtIndex:0];
            continue;
        }
        
        if (_inputBuffer.length >= request.minLength || (isComplete && _inputBuffer.length > 0)) {
            NSUInteger length = MIN(_inputBuffer.length, request.maxLength);
            NSData *data = [_inputBuffer subdataWithRange:NSMakeRange(0, length)];
            
            // Remove processed data from buffer
            // Optimization: if we consumed everything, just set length to 0
            if (length == _inputBuffer.length) {
                [_inputBuffer setLength:0];
            } else {
                NSData *remaining = [_inputBuffer subdataWithRange:NSMakeRange(length, _inputBuffer.length - length)];
                _inputBuffer = [remaining mutableCopy];
            }
            
            request.completion(data, isComplete, nil);
            [_readRequests removeObjectAtIndex:0];
        } else if (isComplete) {
            // EOF and buffer empty (or less than minLength but minLength logic implies we should probably return what we have? 
            // The protocol says "data has minLength bytes: Partial data available".
            // If EOF, we might return less than minLength with isComplete=YES.
            
            request.completion([NSData data], YES, nil);
            [_readRequests removeObjectAtIndex:0];
        } else {
            // Not enough data yet
            break;
        }
    }
}

- (void)cancel {
    [self cleanupConnectState];

    if (_readSource) {
        dispatch_source_cancel(_readSource);
        _readSource = nil;
    }
    if (_writeSource) {
        dispatch_source_cancel(_writeSource);
        _writeSource = nil;
    }
    if (_sockfd != -1) {
        close(_sockfd);
        _sockfd = -1;
    }
    
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkConnectionStateCancelled, nil);
    }
}

- (void)sendData:(NSData *)data completion:(void (^ _Nullable)(NSError * _Nullable error))completion {
    if (_writeBuffer.length > 0 || _writeOffset > 0) {
        [_writeBuffer appendData:data];
        return;
    }
    
    ssize_t sent = send(_sockfd, data.bytes, data.length, 0);
    if (sent == -1) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            [_writeBuffer setData:data];
            _writeOffset = 0;
            
            __weak typeof(self) weakSelf = self;
            _writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, _sockfd, 0, _queue);
            dispatch_source_set_event_handler(_writeSource, ^{
                [weakSelf handleWrite];
            });
            dispatch_resume(_writeSource);
            return;
        }
        if (completion) {
            completion([NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
        }
    } else if ((NSUInteger)sent < data.length) {
        [_writeBuffer setData:data];
        _writeOffset = sent;
        
        __weak typeof(self) weakSelf = self;
        _writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, _sockfd, 0, _queue);
        dispatch_source_set_event_handler(_writeSource, ^{
            [weakSelf handleWrite];
        });
        dispatch_resume(_writeSource);
    } else {
        if (completion) {
            completion(nil);
        }
    }
}

- (void)receiveWithMinimumLength:(NSUInteger)minLength maximumLength:(NSUInteger)maxLength completion:(void (^)(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error))completion {
    PDSReadRequest *request = [[PDSReadRequest alloc] init];
    request.minLength = minLength;
    request.maxLength = maxLength;
    request.completion = completion;
    
    // We must access _readRequests on the queue to be thread-safe if called from outside?
    // PDSNetworkTransport protocol doesn't enforce thread safety but it's good practice.
    // However, usually these methods are called from the same queue or we should dispatch.
    // Assuming single-threaded event loop for now or caller respects queue.
    
    [_readRequests addObject:request];
    
    // Check if we can satisfy immediately
    [self processReadRequests:NO error:nil];
}

@end

@implementation PDSNetworkListenerLinux {
    int _listenfd;
    dispatch_source_t _source;
    dispatch_queue_t _queue;
    NSString *_bindHost;
}

@synthesize stateChangedHandler = _stateChangedHandler;
@synthesize newConnectionHandler = _newConnectionHandler;
@synthesize port = _port;

- (instancetype)initWithPort:(NSUInteger)port {
    return [self initWithHost:nil port:port];
}

- (instancetype)initWithHost:(NSString * _Nullable)host port:(NSUInteger)port {
    self = [super init];
    if (self) {
        _port = port;
        _listenfd = -1;
        _bindHost = [host copy];
    }
    return self;
}

- (void)startWithQueue:(dispatch_queue_t)queue {
    _queue = queue;
    
    NSUInteger portToBind = _port;
    for (int attempt = 0; attempt < 2; attempt++) {
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
        if (_bindHost.length > 0) {
            struct in_addr parsed;
            if (inet_pton(AF_INET, [_bindHost UTF8String], &parsed) == 1) {
                addr.sin_addr = parsed;
            } else if ([_bindHost isEqualToString:@"localhost"]) {
                inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
            } else {
                addr.sin_addr.s_addr = INADDR_ANY;
            }
        } else {
            addr.sin_addr.s_addr = INADDR_ANY;
        }
        addr.sin_port = htons((uint16_t)portToBind);
        
        if (bind(_listenfd, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
            NSError *bindError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            close(_listenfd);
            _listenfd = -1;
            if (errno == EADDRINUSE && attempt == 0) {
                portToBind = 0;
                continue;
            }
            [self failWithError:bindError];
            return;
        }
        
        socklen_t len = sizeof(addr);
        if (getsockname(_listenfd, (struct sockaddr *)&addr, &len) == 0) {
            _port = ntohs(addr.sin_port);
        }
        
        if (listen(_listenfd, 128) == -1) {
            [self failWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]];
            return;
        }
        break;
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

- (void)failWithError:(NSError *)error {
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkListenerStateFailed, error);
    }
    [self cancel];
}

- (void)cancel {
    if (_source) {
        dispatch_source_cancel(_source);
        _source = nil;
    }
    if (_listenfd != -1) {
        close(_listenfd);
        _listenfd = -1;
    }
    
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkListenerStateCancelled, nil);
    }
}

@end
