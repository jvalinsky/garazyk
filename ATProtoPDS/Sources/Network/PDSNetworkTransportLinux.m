#import "PDSNetworkTransportLinux.h"
#import <Foundation/Foundation.h>

@implementation PDSNetworkTransportFactory

+ (id<PDSNetworkListener>)createListenerWithPort:(NSUInteger)port {
    return [[PDSNetworkListenerLinux alloc] initWithPort:port];
}

+ (id<PDSNetworkConnection>)createConnectionWithHost:(NSString *)host port:(NSUInteger)port {
    return [[PDSNetworkConnectionLinux alloc] initWithHost:host port:port];
}

@end

@implementation PDSNetworkConnectionLinux
@synthesize stateChangedHandler = _stateChangedHandler;
@synthesize remoteAddress = _remoteAddress;

- (instancetype)initWithHost:(NSString *)host port:(NSUInteger)port {
    self = [super init];
    if (self) {
        NSLog(@"PDSNetworkConnectionLinux: robust implementation not yet available");
    }
    return self;
}

- (void)startWithQueue:(dispatch_queue_t)queue {
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkConnectionStateFailed, [NSError errorWithDomain:@"PDSNetworkTransport" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Linux transport not implemented"}]);
    }
}

- (void)cancel {}

- (void)sendData:(NSData *)data completion:(void (^ _Nullable)(NSError * _Nullable error))completion {
    if (completion) completion([NSError errorWithDomain:@"PDSNetworkTransport" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Linux transport not implemented"}]);
}

- (void)receiveWithMinimumLength:(NSUInteger)minLength maximumLength:(NSUInteger)maxLength completion:(void (^)(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error))completion {
    completion(nil, NO, [NSError errorWithDomain:@"PDSNetworkTransport" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Linux transport not implemented"}]);
}

@end

@implementation PDSNetworkListenerLinux
@synthesize stateChangedHandler = _stateChangedHandler;
@synthesize newConnectionHandler = _newConnectionHandler;
@synthesize port = _port;

- (instancetype)initWithPort:(NSUInteger)port {
    self = [super init];
    if (self) {
        _port = port;
        NSLog(@"PDSNetworkListenerLinux: robust implementation not yet available");
    }
    return self;
}

- (void)startWithQueue:(dispatch_queue_t)queue {
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkListenerStateFailed, [NSError errorWithDomain:@"PDSNetworkTransport" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Linux transport not implemented"}]);
    }
}

- (void)cancel {}

@end
