/*!
 @file PDSServiceContainer.m
 @abstract Implementation of the service container.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "PDSServiceContainer.h"

@implementation PDSServiceContainer {
    NSMutableDictionary *_instances;
    NSMutableDictionary *_factories;
    NSRecursiveLock *_lock;
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
        _lock = [[NSRecursiveLock alloc] init];
    }
    return self;
}

- (void)registerInstance:(id)instance forProtocol:(Protocol *)protocol {
    NSString *key = NSStringFromProtocol(protocol);
    [_lock lock];
    _instances[key] = instance;
    [_lock unlock];
}

- (void)registerFactory:(id (^)(PDSServiceContainer *))factory forProtocol:(Protocol *)protocol {
    NSString *key = NSStringFromProtocol(protocol);
    [_lock lock];
    _factories[key] = [factory copy];
    [_instances removeObjectForKey:key]; // Invalidate cache
    [_lock unlock];
}

- (nullable id)resolveProtocol:(Protocol *)protocol {
    NSString *key = NSStringFromProtocol(protocol);
    __block id instance = nil;
    
    [_lock lock];
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
    [_lock unlock];
    
    return instance;
}

- (void)reset {
    [_lock lock];
    [_instances removeAllObjects];
    [_factories removeAllObjects];
    [_lock unlock];
}

@end
