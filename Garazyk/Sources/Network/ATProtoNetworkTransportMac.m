// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoNetworkTransportMac.m

 @abstract Implements macOS network transport integration for server connection handling.

 @discussion Provides platform-specific transport wiring for macOS using system networking facilities and forwards connection data into protocol/session layers. Keeps business and routing logic out of transport code.
 */

#import "ATProtoNetworkTransportMac.h"
#import "Debug/GZLogger.h"
#import <Foundation/Foundation.h>

static BOOL ATProtoNetworkTransportMacUsesPlainTCP(NSUInteger port) {
    return port == 0 || port == 80 || port == 2583 || port == 2584 ||
           port == 2582 || port == 3200 || port == 3210 || port == 8082;
}

@implementation ATProtoNetworkTransportFactory

+ (id<ATProtoNetworkListener>)createListenerWithPort:(NSUInteger)port {
    NSString *bindHost = [[NSProcessInfo processInfo] environment][@"PDS_LISTEN_HOST"];
    return [self createListenerWithHost:bindHost port:port];
}

+ (id<ATProtoNetworkListener>)createListenerWithHost:(nullable NSString *)host port:(NSUInteger)port {
    if (host.length == 0) {
        return [[ATProtoNetworkListenerMac alloc] initWithPort:port];
    }
    return [[ATProtoNetworkListenerMac alloc] initWithHost:host port:port];
}

+ (id<ATProtoNetworkConnection>)createConnectionWithHost:(NSString *)host port:(NSUInteger)port {
    return [[ATProtoNetworkConnectionMac alloc] initWithHost:host port:port];
}

@end

@implementation ATProtoNetworkConnectionMac {
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
        nw_parameters_t parameters;
        
        BOOL isLoopback = [host isEqualToString:@"127.0.0.1"] || 
                          [host isEqualToString:@"::1"] || 
                          [host isEqualToString:@"localhost"];
        
        // Use plain TCP for loopback or known plain ports
        if (isLoopback || ATProtoNetworkTransportMacUsesPlainTCP(port)) {
            parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
        } else {
            parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DEFAULT_CONFIGURATION, NW_PARAMETERS_DEFAULT_CONFIGURATION);
        }
        
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
        
        void (^handler)(ATProtoNetworkConnectionState, NSError * _Nullable) = strongSelf.stateChangedHandler;
        if (handler) {
            ATProtoNetworkConnectionState pdsState;
            NSError *nsError = nil;
            if (error) {
                nsError = (__bridge_transfer NSError *)nw_error_copy_cf_error(error);
            }
            switch (state) {
                case nw_connection_state_waiting: 
                    pdsState = ATProtoNetworkConnectionStateWaiting;
                    if (nsError) {
                        GZ_LOG_WARN(@"[Network] Connection waiting: %@", nsError.localizedDescription);
                    }
                    break;
                case nw_connection_state_preparing: pdsState = ATProtoNetworkConnectionStatePreparing; break;
                case nw_connection_state_ready: pdsState = ATProtoNetworkConnectionStateReady; break;
                case nw_connection_state_failed: pdsState = ATProtoNetworkConnectionStateFailed; break;
                case nw_connection_state_cancelled: pdsState = ATProtoNetworkConnectionStateCancelled; break;
                default: pdsState = ATProtoNetworkConnectionStateWaiting; break;
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
        if (completion) completion(nil, NO, [NSError errorWithDomain:@"ATProtoNetwork" code:-1 userInfo:nil]);
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

@implementation ATProtoNetworkListenerMac {
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
        nw_parameters_t parameters;
        if (ATProtoNetworkTransportMacUsesPlainTCP(port)) {
            parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
        } else {
            parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DEFAULT_CONFIGURATION, NW_PARAMETERS_DEFAULT_CONFIGURATION);
        }
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
            void (^handler)(ATProtoNetworkListenerState, NSError * _Nullable) = strongSelf.stateChangedHandler;
            if (handler) {
                ATProtoNetworkListenerState pdsState;
                switch (state) {
                    case nw_listener_state_waiting: pdsState = ATProtoNetworkListenerStateWaiting; break;
                    case nw_listener_state_ready: 
                        pdsState = ATProtoNetworkListenerStateReady;
                        strongSelf->_port = nw_listener_get_port(strongSelf->_listener);
                        break;
                    case nw_listener_state_failed: pdsState = ATProtoNetworkListenerStateFailed; break;
                    case nw_listener_state_cancelled: pdsState = ATProtoNetworkListenerStateCancelled; break;
                    default: pdsState = ATProtoNetworkListenerStateWaiting; break;
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
            void (^handler)(id<ATProtoNetworkConnection>) = strongSelf.newConnectionHandler;
            if (handler) {
                ATProtoNetworkConnectionMac *pdsConn = [[ATProtoNetworkConnectionMac alloc] initWithConnection:connection];
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
