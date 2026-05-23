// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSEmailProviderFactory.h

 @abstract Factory for creating email provider instances.

 @discussion
    Extracts the email provider initialization logic from PDSApplication.m
    into a proper factory class. Supports "mock", "smtp", and "resend"
    providers, plus custom providers registered via registerProviderClass:forName:.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Core/GZProviderRegistry.h"

/**
 * @abstract Defines the PDSEmailProvider protocol contract.
 */
@protocol PDSEmailProvider;
@protocol PDSSecretsProvider;

@class ATProtoServiceConfiguration;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSEmailProviderFactory

 @abstract Factory for creating email provider instances from configuration.
 */
@interface PDSEmailProviderFactory : NSObject <GZProviderFactory>

/*!
 @method providerWithName:configuration:secretsProvider:error:
 @abstract Create an email provider from configuration.
 @param name Provider identifier ("mock", "smtp", "resend", or custom).
 @param configuration The PDS configuration.
 @param secretsProvider The secrets provider for resolving API keys.
 @param error On failure, set to a factory error.
 @return An email provider instance, or nil on failure.
 */
+ (nullable id<PDSEmailProvider>)providerWithName:(NSString *)name
                                    configuration:(ATProtoServiceConfiguration *)configuration
                                   secretsProvider:(nullable id<PDSSecretsProvider>)secretsProvider
                                             error:(NSError **)error;

/*!
 @method registerProviderClass:forName:
 @abstract Register a custom email provider class for lookup by name.
 */
+ (void)registerProviderClass:(Class)providerClass forName:(NSString *)name;

/*!
 @method unregisterProviderWithName:
 @abstract Remove a previously registered custom provider.
 */
+ (void)unregisterProviderWithName:(NSString *)name;

/*! Clear all registered custom providers. */
+ (void)resetCustomProviders;

@end

NS_ASSUME_NONNULL_END
