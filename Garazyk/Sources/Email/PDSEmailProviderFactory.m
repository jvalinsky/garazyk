// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSEmailProviderFactory.m

 @abstract Factory for creating email provider instances.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Email/PDSEmailProviderFactory.h"
#import "Email/PDSEmailProvider.h"
#import "Email/PDSMockEmailProvider.h"
#import "Email/PDSSMTPEmailProvider.h"
#import "Email/PDSResendEmailProvider.h"
#import "Email/PDSSecretsProvider.h"
#import "Email/PDSKeychainSecretsProvider.h"
#import "Email/PDSEnvironmentSecretsProvider.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Debug/GZLogger.h"

NSString *const PDSEmailProviderFactoryErrorDomain = @"com.atproto.pds.emailproviderfactory";

typedef NS_ENUM(NSInteger, PDSEmailProviderFactoryErrorCode) {
    PDSEmailProviderFactoryErrorNotConfigured = 1,
    PDSEmailProviderFactoryErrorUnsupportedProvider = 2,
    PDSEmailProviderFactoryErrorCreationFailed = 3,
};

static NSMutableDictionary<NSString *, Class> *sCustomProviders = nil;
static dispatch_queue_t sRegistryQueue = nil;

@implementation PDSEmailProviderFactory

+ (void)initialize {
    if (self == [PDSEmailProviderFactory class]) {
        sCustomProviders = [NSMutableDictionary dictionary];
        sRegistryQueue = dispatch_queue_create("com.atproto.pds.emailproviderfactory.registry",
                                                DISPATCH_QUEUE_SERIAL);
    }
}

#pragma mark - PDSProviderFactory

+ (NSArray<NSString *> *)supportedIdentifiers {
    return @[@"mock", @"smtp", @"resend"];
}

+ (nullable id)providerWithIdentifier:(NSString *)identifier
                         configuration:(ATProtoServiceConfiguration *)configuration
                        secretsProvider:(nullable id<PDSSecretsProvider>)secretsProvider
                                  error:(NSError **)error {
    return [self providerWithName:identifier
                    configuration:configuration
                   secretsProvider:secretsProvider
                             error:error];
}

#pragma mark - Public API

+ (nullable id<PDSEmailProvider>)providerWithName:(NSString *)name
                                    configuration:(ATProtoServiceConfiguration *)configuration
                                   secretsProvider:(nullable id<PDSSecretsProvider>)secretsProvider
                                             error:(NSError **)error {
    NSString *provider = [self normalizedProviderName:name];

    if (provider.length == 0 || [provider isEqualToString:@"none"]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSEmailProviderFactoryErrorDomain
                                         code:PDSEmailProviderFactoryErrorNotConfigured
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Email provider is not configured"
                                     }];
        }
        return nil;
    }

    // Built-in providers
    if ([provider isEqualToString:@"mock"]) {
        return [[PDSMockEmailProvider alloc] init];
    }

    if ([provider isEqualToString:@"smtp"]) {
        PDSSMTPEmailProvider *smtp = [[PDSSMTPEmailProvider alloc]
            initWithHost:configuration.emailSmtpHost ?: @"localhost"
                    port:configuration.emailSmtpPort
                username:configuration.emailSmtpUsername
                password:configuration.emailSmtpPassword
                  useTLS:configuration.emailSmtpUseTLS];
        GZ_LOG_WARN(@"SMTP email provider is configured, but SMTP delivery is not implemented. "
                      @"All sends will fail closed with PDSSMTPEmailProviderErrorNotImplemented. "
                      @"Use PDSResendEmailProvider for working email delivery.");
        return smtp;
    }

    if ([provider isEqualToString:@"resend"]) {
        return [self createResendProviderWithConfiguration:configuration
                                            secretsProvider:secretsProvider
                                                      error:error];
    }

    // Custom providers
    __block Class providerClass = Nil;
    dispatch_sync(sRegistryQueue, ^{
        providerClass = sCustomProviders[provider];
    });
    if (providerClass) {
        id instance = [[providerClass alloc] init];
        if ([instance conformsToProtocol:@protocol(PDSEmailProvider)]) {
            return instance;
        }
        if (error) {
            *error = [NSError errorWithDomain:PDSEmailProviderFactoryErrorDomain
                                         code:PDSEmailProviderFactoryErrorCreationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             @"Custom email provider failed to initialize"
                                     }];
        }
        return nil;
    }

    if (error) {
        *error = [NSError errorWithDomain:PDSEmailProviderFactoryErrorDomain
                                     code:PDSEmailProviderFactoryErrorUnsupportedProvider
                                 userInfo:@{
                                     NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:
                                             @"Unsupported email provider: %@", provider]
                                 }];
    }
    return nil;
}

+ (void)registerProviderClass:(Class)providerClass forName:(NSString *)name {
    NSString *provider = [self normalizedProviderName:name];
    if (provider.length == 0 || [provider isEqualToString:@"none"] ||
        [provider isEqualToString:@"mock"] || [provider isEqualToString:@"smtp"] ||
        [provider isEqualToString:@"resend"]) {
        return;
    }
    if (!providerClass || ![providerClass conformsToProtocol:@protocol(PDSEmailProvider)]) {
        return;
    }
    dispatch_sync(sRegistryQueue, ^{
        sCustomProviders[provider] = providerClass;
    });
}

+ (void)unregisterProviderWithName:(NSString *)name {
    NSString *provider = [self normalizedProviderName:name];
    if (provider.length == 0) return;
    dispatch_sync(sRegistryQueue, ^{
        [sCustomProviders removeObjectForKey:provider];
    });
}

+ (void)resetCustomProviders {
    dispatch_sync(sRegistryQueue, ^{
        [sCustomProviders removeAllObjects];
    });
}

#pragma mark - Private

+ (NSString *)normalizedProviderName:(NSString *)name {
    if (![name isKindOfClass:[NSString class]]) return @"";
    return [[name stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
}

+ (nullable PDSResendEmailProvider *)createResendProviderWithConfiguration:(ATProtoServiceConfiguration *)configuration
                                                            secretsProvider:(nullable id<PDSSecretsProvider>)secretsProvider
                                                                      error:(NSError **)error {
    if (!configuration.resendFromAddress || configuration.resendFromAddress.length == 0) {
        GZ_LOG_WARN(@"Resend email provider requested but no from address configured "
                      @"(set PDS_EMAIL_RESEND_FROM).");
        if (error) {
            *error = [NSError errorWithDomain:PDSEmailProviderFactoryErrorDomain
                                         code:PDSEmailProviderFactoryErrorNotConfigured
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             @"Resend from address not configured"
                                     }];
        }
        return nil;
    }

    // Resolve secrets provider
    id<PDSSecretsProvider> resolvedProvider = secretsProvider;
    if (!resolvedProvider) {
        NSString *source = configuration.resendAPIKeySource ?: @"env";
        if ([source isEqualToString:@"keychain"]) {
            resolvedProvider = [[PDSKeychainSecretsProvider alloc]
                initWithService:configuration.resendKeychainService ?: @"com.atproto.pds.resend"];
        } else {
            resolvedProvider = [[PDSEnvironmentSecretsProvider alloc] init];
        }
    }

    PDSResendEmailProvider *provider = [[PDSResendEmailProvider alloc]
        initWithSecretsProvider:resolvedProvider
                    fromAddress:configuration.resendFromAddress
                    apiEndpoint:configuration.resendAPIEndpoint];

    GZ_LOG_INFO(@"Initialized Resend email provider (source: %@, from: %@)",
                 configuration.resendAPIKeySource ?: @"env",
                 configuration.resendFromAddress);

    return provider;
}

@end
