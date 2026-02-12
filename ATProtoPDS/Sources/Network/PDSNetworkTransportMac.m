#import "PDSNetworkTransportMac.h"
#import <Foundation/Foundation.h>

@implementation PDSNetworkTransportFactory

+ (id<PDSNetworkListener>)createListenerWithPort:(NSUInteger)port {
    NSString *bindHost = [[NSProcessInfo processInfo] environment][@"PDS_LISTEN_HOST"];
    return [self createListenerWithHost:bindHost port:port];
}

+ (id<PDSNetworkListener>)createListenerWithHost:(nullable NSString *)host port:(NSUInteger)port {
    if (host.length == 0) {
        return [[PDSNetworkListenerMac alloc] initWithPort:port];
    }
    return [[PDSNetworkListenerMac alloc] initWithHost:host port:port];
}

+ (id<PDSNetworkConnection>)createConnectionWithHost:(NSString *)host port:(NSUInteger)port {
    return [[PDSNetworkConnectionMac alloc] initWithHost:host port:port];
}

@end

@implementation PDSNetworkConnectionMac {
    nw_connection_t _connection;
}

@synthesize stateChangedHandler = _stateChangedHandler;

- (instancetype)initWithConnection:(nw_connection_t)connection {
    self = [super init];
    if (self) {
        _connection = connection;
        [self setupHandlers];
    }
    return self;
}

- (instancetype)initWithHost:(NSString *)host port:(NSUInteger)port {
    self = [super init];
    if (self) {
        nw_endpoint_t endpoint = nw_endpoint_create_host(host.UTF8String, [[NSString stringWithFormat:@"%lu", (unsigned long)port] UTF8String]);
        nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
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

- (void)startWithQueue:(dispatch_queue_t)queue {
    nw_connection_set_queue(_connection, queue);
    nw_connection_start(_connection);
}

- (void)cancel {
    if (_connection) {
        nw_connection_cancel(_connection);
    }
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

- (void)receiveWithMinimumLength:(NSUInteger)minLength maximumLength:(NSUInteger)maxLength completion:(void (^)(NSData * _Nullable data, BOOL isComplete, NSError * _Nullable error))completion {
    if (!_connection) {
        if (completion) completion(nil, NO, [NSError errorWithDomain:@"PDSNetwork" code:-1 userInfo:nil]);
        return;
    }
    nw_connection_receive(_connection, (uint32_t)minLength, (uint32_t)maxLength, ^(dispatch_data_t content, nw_content_context_t context, bool isComplete, nw_error_t receiveError) {
        NSData *data = nil;
        if (content) {
            __block NSMutableData *mutableData = [NSMutableData dataWithCapacity:dispatch_data_get_size(content)];
            dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
                [mutableData appendBytes:buffer length:size];
                return true;
            });
            data = mutableData;
        }
        NSError *nsError = nil;
        if (receiveError) {
            nsError = (__bridge_transfer NSError *)nw_error_copy_cf_error(receiveError);
        }
        if (completion) {
            completion(data, isComplete, nsError);
        }
    });
}

- (NSString *)remoteAddress {
    nw_endpoint_t endpoint = nw_connection_copy_endpoint(_connection);
    if (!endpoint) return nil;
    char *addressStr = nw_endpoint_copy_address_string(endpoint);
    NSString *result = addressStr ? [NSString stringWithUTF8String:addressStr] : nil;
    if (addressStr) free(addressStr);
    return result;
}

@end

@implementation PDSNetworkListenerMac {
    nw_listener_t _listener;
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
        nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
        char portStr[16];
        snprintf(portStr, sizeof(portStr), "%lu", (unsigned long)port);
        if (host.length > 0) {
            nw_endpoint_t localEndpoint = nw_endpoint_create_host(host.UTF8String, portStr);
            nw_parameters_set_local_endpoint(parameters, localEndpoint);
        }
        _listener = nw_listener_create_with_port(portStr, parameters);
        
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

- (void)startWithQueue:(dispatch_queue_t)queue {
    nw_listener_set_queue(_listener, queue);
    nw_listener_start(_listener);
}

- (void)cancel {
    if (_listener) {
        nw_listener_cancel(_listener);
    }
}
@end
