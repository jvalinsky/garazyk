#import "PDSNetworkTransportLinux.h"
#import <Foundation/Foundation.h>

#import "PDSNetworkTransportLinux.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <fcntl.h>

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

@interface PDSReadRequest : NSObject
@property (nonatomic, assign) NSUInteger minLength;
@property (nonatomic, assign) NSUInteger maxLength;
@property (nonatomic, copy) void (^completion)(NSData * _Nullable, BOOL, NSError * _Nullable);
@end

@implementation PDSReadRequest
@end

@implementation PDSNetworkConnectionLinux {
    int _sockfd;
    dispatch_source_t _readSource;
    dispatch_source_t _writeSource;
    dispatch_queue_t _queue;
    NSMutableData *_inputBuffer;
    NSMutableArray<PDSReadRequest *> *_readRequests;
    NSMutableData *_writeBuffer;
    NSUInteger _writeOffset;
    NSString *_host;
    NSUInteger _port;
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
        _sockfd = socket(AF_INET, SOCK_STREAM, 0);
        if (_sockfd == -1) {
            dispatch_async(queue, ^{
                if (self.stateChangedHandler) {
                    self.stateChangedHandler(PDSNetworkConnectionStateFailed, [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
                }
            });
            return;
        }
        
        int flags = fcntl(_sockfd, F_GETFL, 0);
        fcntl(_sockfd, F_SETFL, flags | O_NONBLOCK);
        
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons((uint16_t)_port);
        
        struct in_addr sin_addr;
        if (inet_pton(AF_INET, [_host UTF8String], &sin_addr) == 1) {
            addr.sin_addr = sin_addr;
        } else {
            dispatch_async(queue, ^{
                if (self.stateChangedHandler) {
                    self.stateChangedHandler(PDSNetworkConnectionStateFailed, [NSError errorWithDomain:@"PDSNetworkTransport" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid host address"}]);
                }
            });
            close(_sockfd);
            _sockfd = -1;
            return;
        }
        
        int result = connect(_sockfd, (struct sockaddr *)&addr, sizeof(addr));
        if (result == 0) {
            [self setupSources];
            dispatch_async(queue, ^{
                if (self.stateChangedHandler) {
                    self.stateChangedHandler(PDSNetworkConnectionStateReady, nil);
                }
            });
            return;
        }
        
        if (errno != EINPROGRESS) {
            dispatch_async(queue, ^{
                if (self.stateChangedHandler) {
                    self.stateChangedHandler(PDSNetworkConnectionStateFailed, [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
                }
            });
            close(_sockfd);
            _sockfd = -1;
            return;
        }
        
        __weak typeof(self) weakSelf = self;
        dispatch_source_t connectSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, _sockfd, 0, queue);
        dispatch_source_set_event_handler(connectSource, ^{
            int error = 0;
            socklen_t len = sizeof(error);
            getsockopt(_sockfd, SOL_SOCKET, SO_ERROR, &error, &len);
            
            dispatch_source_cancel(connectSource);
            
            if (error != 0) {
                close(_sockfd);
                _sockfd = -1;
                if (self.stateChangedHandler) {
                    self.stateChangedHandler(PDSNetworkConnectionStateFailed, [NSError errorWithDomain:NSPOSIXErrorDomain code:error userInfo:nil]);
                }
                return;
            }
            
            [weakSelf setupSources];
            if (self.stateChangedHandler) {
                self.stateChangedHandler(PDSNetworkConnectionStateReady, nil);
            }
        });
        dispatch_resume(connectSource);
        return;
    }
    
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
}

@synthesize stateChangedHandler = _stateChangedHandler;
@synthesize newConnectionHandler = _newConnectionHandler;
@synthesize port = _port;

- (instancetype)initWithPort:(NSUInteger)port {
    self = [super init];
    if (self) {
        _port = port;
        _listenfd = -1;
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
        addr.sin_addr.s_addr = INADDR_ANY;
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
