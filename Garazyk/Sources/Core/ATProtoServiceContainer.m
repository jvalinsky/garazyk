// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoServiceContainer.m
 @abstract Implementation of the service container.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "ATProtoServiceContainer.h"

@implementation ATProtoServiceContainer {
    NSMutableDictionary *_instances;
    NSMutableDictionary *_factories;
    NSRecursiveLock *_lock;
}

+ (instancetype)sharedContainer {
    static ATProtoServiceContainer *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ATProtoServiceContainer alloc] init];
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

- (void)registerFactory:(id (^)(ATProtoServiceContainer *))factory forProtocol:(Protocol *)protocol {
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
        id (^factory)(ATProtoServiceContainer *) = _factories[key];
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
