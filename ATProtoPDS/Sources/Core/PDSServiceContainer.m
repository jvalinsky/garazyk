/*!
 @file PDSServiceContainer.m
 @abstract Implementation of the service container.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "PDSServiceContainer.h"

@implementation PDSServiceContainer {
    NSMutableDictionary *_instances;
    NSMutableDictionary *_factories;
    dispatch_queue_t _lock;
}

+ (instancetype)sharedContainer {
    static PDSServiceContainer *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSServiceContainer alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _instances = [NSMutableDictionary dictionary];
        _factories = [NSMutableDictionary dictionary];
        _lock = dispatch_queue_create("com.atproto.pds.servicecontainer", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)registerInstance:(id)instance forProtocol:(Protocol *)protocol {
    NSString *key = NSStringFromProtocol(protocol);
    dispatch_sync(_lock, ^{
        _instances[key] = instance;
    });
}

- (void)registerFactory:(id (^)(PDSServiceContainer *))factory forProtocol:(Protocol *)protocol {
    NSString *key = NSStringFromProtocol(protocol);
    dispatch_sync(_lock, ^{
        _factories[key] = [factory copy];
        [_instances removeObjectForKey:key]; // Invalidate cache
    });
}

- (nullable id)resolveProtocol:(Protocol *)protocol {
    NSString *key = NSStringFromProtocol(protocol);
    __block id instance = nil;
    
    dispatch_sync(_lock, ^{
        instance = _instances[key];
        
        if (!instance) {
            id (^factory)(PDSServiceContainer *) = _factories[key];
            if (factory) {
                instance = factory(self);
                if (instance) {
                    _instances[key] = instance;
                }
            }
        }
    });
    
    return instance;
}

- (void)reset {
    dispatch_sync(_lock, ^{
        [_instances removeAllObjects];
        [_factories removeAllObjects];
    });
}

@end
