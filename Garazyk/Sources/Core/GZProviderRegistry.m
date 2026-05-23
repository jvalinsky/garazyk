// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZProviderRegistry.m

 @abstract Central registry for provider plugins.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Core/GZProviderRegistry.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Email/PDSSecretsProvider.h"

// Force emission of the GZProviderFactory protocol metadata symbol.
// Without this, classes in other libraries that conform to the protocol
// will get linker errors for __OBJC_PROTOCOL_$_GZProviderFactory.
@interface _GZProviderFactoryToken : NSObject <GZProviderFactory>
@end

@implementation _GZProviderFactoryToken

+ (nullable id)providerWithIdentifier:(NSString *)identifier
                         configuration:(ATProtoServiceConfiguration *)configuration
                        secretsProvider:(nullable id<PDSSecretsProvider>)secretsProvider
                                  error:(NSError **)error {
    return nil;
}

+ (NSArray<NSString *> *)supportedIdentifiers {
    return @[];
}

@end

NSString *const GZProviderRegistryErrorDomain = @"com.atproto.pds.providerregistry";

typedef NS_ENUM(NSInteger, GZProviderRegistryErrorCode) {
    GZProviderRegistryErrorNoFactory = 1,
    GZProviderRegistryErrorProviderCreationFailed = 2,
};

@implementation GZProviderRegistry {
    NSMutableDictionary<NSString *, Class<GZProviderFactory>> *_factories;
    dispatch_queue_t _queue;
}

+ (instancetype)sharedRegistry {
    static GZProviderRegistry *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[GZProviderRegistry alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _factories = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("com.atproto.pds.providerregistry", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)registerFactory:(Class<GZProviderFactory>)factory
             forProtocol:(Protocol *)protocol {
    NSString *key = NSStringFromProtocol(protocol);
    if (!key || !factory) return;

    dispatch_sync(_queue, ^{
        _factories[key] = factory;
    });
}

- (void)unregisterFactoryForProtocol:(Protocol *)protocol {
    NSString *key = NSStringFromProtocol(protocol);
    if (!key) return;

    dispatch_sync(_queue, ^{
        [_factories removeObjectForKey:key];
    });
}

- (nullable id)resolveProviderForProtocol:(Protocol *)protocol
                               identifier:(NSString *)identifier
                            configuration:(ATProtoServiceConfiguration *)configuration
                           secretsProvider:(nullable id<PDSSecretsProvider>)secretsProvider
                                     error:(NSError **)error {
    NSString *key = NSStringFromProtocol(protocol);

    __block Class<GZProviderFactory> factoryClass = Nil;
    dispatch_sync(_queue, ^{
        factoryClass = _factories[key];
    });

    if (!factoryClass) {
        if (error) {
            *error = [NSError errorWithDomain:GZProviderRegistryErrorDomain
                                         code:GZProviderRegistryErrorNoFactory
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:
                                                 @"No factory registered for protocol %@",
                                                 key]
                                     }];
        }
        return nil;
    }

    NSError *factoryError = nil;
    id provider = [factoryClass providerWithIdentifier:identifier
                                         configuration:configuration
                                        secretsProvider:secretsProvider
                                                  error:&factoryError];
    if (!provider) {
        if (error) {
            *error = factoryError ?: [NSError errorWithDomain:GZProviderRegistryErrorDomain
                                                          code:GZProviderRegistryErrorProviderCreationFailed
                                                      userInfo:@{
                                                          NSLocalizedDescriptionKey:
                                                              @"Provider factory returned nil"
                                                      }];
        }
        return nil;
    }

    return provider;
}

- (NSArray<NSString *> *)identifiersForProtocol:(Protocol *)protocol {
    NSString *key = NSStringFromProtocol(protocol);

    __block Class<GZProviderFactory> factoryClass = Nil;
    dispatch_sync(_queue, ^{
        factoryClass = _factories[key];
    });

    if (!factoryClass) {
        return @[];
    }

    return [factoryClass supportedIdentifiers];
}

- (void)reset {
    dispatch_sync(_queue, ^{
        [_factories removeAllObjects];
    });
}

@end
