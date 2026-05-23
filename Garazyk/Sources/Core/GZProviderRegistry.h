// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZProviderRegistry.h

 @abstract Central registry for provider plugins.

 @discussion
    Maps (protocol, identifier) pairs to factory classes, enabling
    config-driven provider resolution. All provider factories conform
    to GZProviderFactory and are registered at startup.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class ATProtoServiceConfiguration;
/**
 * @abstract Defines the PDSSecretsProvider protocol contract.
 */
@protocol PDSSecretsProvider;

NS_ASSUME_NONNULL_BEGIN

/*!
 @protocol GZProviderFactory

 @abstract Factory protocol for creating provider instances.

 @discussion
    Each provider domain (email, phone verification, blob, etc.)
    implements this protocol to create provider instances from
    configuration and secrets.
 */
@protocol GZProviderFactory <NSObject>

/*!
 @method providerWithIdentifier:configuration:secretsProvider:error:
 @abstract Create a provider instance for the given identifier.
 @param identifier Provider identifier (e.g. "resend", "twilio", "mock").
 @param configuration The PDS configuration.
 @param secretsProvider The secrets provider for resolving API keys.
 @param error On failure, set to a factory error.
 @return A provider instance, or nil on failure.
 */
+ (nullable id)providerWithIdentifier:(NSString *)identifier
                         configuration:(ATProtoServiceConfiguration *)configuration
                        secretsProvider:(nullable id<PDSSecretsProvider>)secretsProvider
                                  error:(NSError **)error;

/*!
 @method supportedIdentifiers
 @abstract Returns the list of provider identifiers this factory supports.
 */
+ (NSArray<NSString *> *)supportedIdentifiers;

@end

/*!
 @class GZProviderRegistry

 @abstract Central registry for provider plugins.

 @discussion
    Maps (protocol, identifier) pairs to factory classes. Providers
    are resolved by protocol and identifier, with configuration and
    secrets passed through. Thread-safe via serial dispatch queue.
 */
@interface GZProviderRegistry : NSObject

/*! Returns the shared registry. */
+ (instancetype)sharedRegistry;

/*!
 @method registerFactory:forProtocol:
 @abstract Register a factory for a protocol.
 @param factory Factory class conforming to GZProviderFactory.
 @param protocol The protocol this factory creates providers for.
 */
- (void)registerFactory:(Class<GZProviderFactory>)factory
             forProtocol:(Protocol *)protocol;

/*!
 @method unregisterFactoryForProtocol:
 @abstract Remove a previously registered factory.
 */
- (void)unregisterFactoryForProtocol:(Protocol *)protocol;

/*!
 @method resolveProviderForProtocol:identifier:configuration:secretsProvider:error:
 @abstract Resolve a provider instance.
 @param protocol The protocol to resolve.
 @param identifier The provider identifier (e.g. "resend", "twilio").
 @param configuration The PDS configuration.
 @param secretsProvider The secrets provider for resolving API keys.
 @param error On failure, set to a resolution error.
 @return A provider instance, or nil on failure.
 */
- (nullable id)resolveProviderForProtocol:(Protocol *)protocol
                               identifier:(NSString *)identifier
                            configuration:(ATProtoServiceConfiguration *)configuration
                           secretsProvider:(nullable id<PDSSecretsProvider>)secretsProvider
                                     error:(NSError **)error;

/*!
 @method identifiersForProtocol:
 @abstract List all registered identifiers for a protocol.
 */
- (NSArray<NSString *> *)identifiersForProtocol:(Protocol *)protocol;

/*! Remove all registrations. Useful for testing. */
- (void)reset;

@end

NS_ASSUME_NONNULL_END
