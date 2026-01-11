#import "Network/PDSNetworkTransportMac.h"
#import <Foundation/Foundation.h>

@implementation PDSNetworkTransportFactory

+ (id<PDSNetworkListener>)createListenerWithPort:(NSUInteger)port {
    return [[PDSNetworkListenerMac alloc] initWithPort:port];
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
        if (strongSelf.stateChangedHandler) {
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
            strongSelf.stateChangedHandler(pdsState, nsError);
        }
    });
}

- (void)startWithQueue:(dispatch_queue_t)queue {
    nw_connection_set_queue(_connection, queue);
    nw_connection_start(_connection);
}

- (void)cancel {
    nw_connection_cancel(_connection);
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
        completion(data, isComplete, nsError);
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
    self = [super init];
    if (self) {
        _port = port;
        nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
        char portStr[16];
        snprintf(portStr, sizeof(portStr), "%lu", (unsigned long)port);
        _listener = nw_listener_create_with_port(portStr, parameters);
        
        __weak typeof(self) weakSelf = self;
        nw_listener_set_state_changed_handler(_listener, ^(nw_listener_state_t state, nw_error_t error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (strongSelf.stateChangedHandler) {
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
                strongSelf.stateChangedHandler(pdsState, nsError);
            }
        });

        nw_listener_set_new_connection_handler(_listener, ^(nw_connection_t connection) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (strongSelf.newConnectionHandler) {
                PDSNetworkConnectionMac *pdsConn = [[PDSNetworkConnectionMac alloc] initWithConnection:connection];
                strongSelf.newConnectionHandler(pdsConn);
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
    nw_listener_cancel(_listener);
}

@end
