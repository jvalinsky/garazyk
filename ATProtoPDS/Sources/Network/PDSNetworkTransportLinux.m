#import "PDSNetworkTransportLinux.h"
#import <Foundation/Foundation.h>

#import "PDSNetworkTransportLinux.h"
#import <Foundation/Foundation.h>
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

@implementation PDSNetworkConnectionLinux {
    int _sockfd;
    dispatch_source_t _readSource;
    dispatch_source_t _writeSource;
    dispatch_queue_t _queue;
    BOOL _cancelled;
    NSMutableArray *_receiveRequests;
}

@synthesize stateChangedHandler = _stateChangedHandler;
@synthesize remoteAddress = _remoteAddress;

- (instancetype)initWithHost:(NSString *)host port:(NSUInteger)port {
    self = [super init];
    if (self) {
        _sockfd = -1;
        _remoteAddress = [NSString stringWithFormat:@"%@:%lu", host, (unsigned long)port];
        _receiveRequests = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithSocket:(int)sockfd address:(NSString *)address {
    self = [super init];
    if (self) {
        _sockfd = sockfd;
        _remoteAddress = address;
        _receiveRequests = [NSMutableArray array];
        
        // Set non-blocking
        int flags = fcntl(_sockfd, F_GETFL, 0);
        fcntl(_sockfd, F_SETFL, flags | O_NONBLOCK);
    }
    return self;
}

- (void)startWithQueue:(dispatch_queue_t)queue {
    _queue = queue;
    
    if (_sockfd == -1) {
        // Connect logic would go here for client connections
        if (self.stateChangedHandler) {
            self.stateChangedHandler(PDSNetworkConnectionStateFailed, [NSError errorWithDomain:@"PDSNetworkTransport" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Client connection not implemented"}]);
        }
        return;
    }
    
    // Server-side connection already has a socket
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
    dispatch_source_set_cancel_handler(_readSource, ^{
        // Socket closed
    });
    dispatch_resume(_readSource);
}

- (void)handleRead {
    if (_cancelled) return;

    size_t bytesAvailable = dispatch_source_get_data(_readSource);
    if (bytesAvailable == 0) {
        // EOF or error
        [self cancel];
        return;
    }

    // Process pending receive requests
    @synchronized (_receiveRequests) {
        if (_receiveRequests.count > 0) {
            NSDictionary *request = _receiveRequests[0];
            [_receiveRequests removeObjectAtIndex:0];
            
            NSUInteger maxLength = [request[@"max"] unsignedIntegerValue];
            void (^completion)(NSData *, BOOL, NSError *) = request[@"completion"];
            
            uint8_t *buffer = malloc(maxLength);
            ssize_t received = recv(_sockfd, buffer, maxLength, 0);
            
            if (received > 0) {
                NSData *data = [NSData dataWithBytesNoCopy:buffer length:received freeWhenDone:YES];
                completion(data, NO, nil);
            } else if (received == 0) {
                // Connection closed
                free(buffer);
                completion(nil, YES, nil);
                [self cancel];
            } else {
                free(buffer);
                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    // Put it back
                    [_receiveRequests insertObject:request atIndex:0];
                } else {
                    completion(nil, NO, [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
                }
            }
        }
    }
}

- (void)cancel {
    if (_cancelled) return;
    _cancelled = YES;

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
    // Basic send implementation
    ssize_t sent = send(_sockfd, data.bytes, data.length, 0);
    if (sent == -1) {
        if (completion) completion([NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
    } else {
        if (completion) completion(nil);
    }
}

- (void)receiveWithMinimumLength:(NSUInteger)minLength maximumLength:(NSUInteger)maxLength completion:(void (^)(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error))completion {
    NSDictionary *request = @{
        @"min": @(minLength),
        @"max": @(maxLength),
        @"completion": [completion copy]
    };
    
    @synchronized (_receiveRequests) {
        [_receiveRequests addObject:request];
    }
    
    // Trigger a read check immediately in case data is already there
    dispatch_async(_queue, ^{
        [self handleRead];
    });
}

@end

@implementation PDSNetworkListenerLinux {
    int _listenfd;
    dispatch_source_t _source;
    dispatch_queue_t _queue;
    BOOL _cancelled;
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
        [self failWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]];
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

- (void)failWithError:(NSError *)error {
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkListenerStateFailed, error);
    }
    [self cancel];
}

- (void)cancel {
    if (_cancelled) return;
    _cancelled = YES;

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
