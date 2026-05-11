// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Services/Core/PDSPhoneVerificationProvider.h"
#import "PhoneVerification/PDSTwilioPhoneVerificationProvider.h"
#import "PhoneVerification/PDSVonagePhoneVerificationProvider.h"
#import "PhoneVerification/PDSPlivoPhoneVerificationProvider.h"
#import "PhoneVerification/PDSTelegramGatewayPhoneVerificationProvider.h"

NSString * const PDSPhoneVerificationProviderErrorDomain = @"com.atproto.pds.phoneverificationprovider";

@interface PDSMockPhoneVerificationProvider : NSObject <PDSPhoneVerificationProvider>
@end

@implementation PDSMockPhoneVerificationProvider

- (nullable NSString *)requestVerificationForPhoneNumber:(NSString *)phoneNumber error:(NSError **)error {
    (void)phoneNumber;
    (void)error;
    return @"";
}

@end

@implementation PDSPhoneVerificationProviderFactory

+ (NSString *)normalizedProviderName:(NSString *)providerName {
    if (![providerName isKindOfClass:[NSString class]]) {
        return @"";
    }
    return [[providerName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
}

+ (dispatch_queue_t)registryQueue {
    static dispatch_queue_t queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.atproto.pds.phoneverificationprovider.registry", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

+ (NSMutableDictionary<NSString *, Class> *)customProviderRegistry {
    static NSMutableDictionary<NSString *, Class> *registry = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [NSMutableDictionary dictionary];
    });
    return registry;
}

+ (void)registerProviderClass:(Class)providerClass forName:(NSString *)providerName {
    NSString *provider = [self normalizedProviderName:providerName];
    if (provider.length == 0 || [provider isEqualToString:@"none"] || [provider isEqualToString:@"mock"]) {
        return;
    }
    if (!providerClass || ![providerClass conformsToProtocol:@protocol(PDSPhoneVerificationProvider)]) {
        return;
    }

    dispatch_sync([self registryQueue], ^{
        [self customProviderRegistry][provider] = providerClass;
    });
}

+ (void)unregisterProviderWithName:(NSString *)providerName {
    NSString *provider = [self normalizedProviderName:providerName];
    if (provider.length == 0) {
        return;
    }

    dispatch_sync([self registryQueue], ^{
        [[self customProviderRegistry] removeObjectForKey:provider];
    });
}

+ (void)resetCustomProviders {
    dispatch_sync([self registryQueue], ^{
        [[self customProviderRegistry] removeAllObjects];
    });
}

+ (nullable id<PDSPhoneVerificationProvider>)providerWithName:(NSString *)providerName
                                                 configuration:(NSDictionary *)configuration
                                                secretsProvider:(nullable id)secretsProvider
                                                          error:(NSError **)error {
    NSString *provider = [self normalizedProviderName:providerName];
    if (provider.length == 0 || [provider isEqualToString:@"none"]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSPhoneVerificationProviderErrorDomain
                                         code:PDSPhoneVerificationProviderErrorNotConfigured
                                     userInfo:@{NSLocalizedDescriptionKey: @"Phone verification provider is not configured"}];
        }
        return nil;
    }

    if ([provider isEqualToString:@"mock"]) {
        return [[PDSMockPhoneVerificationProvider alloc] init];
    }

    // Built-in providers that require secrets
    if ([provider isEqualToString:@"twilio"]) {
        if (!secretsProvider) {
            if (error) {
                *error = [NSError errorWithDomain:PDSPhoneVerificationProviderErrorDomain
                                             code:PDSPhoneVerificationProviderErrorNotConfigured
                                         userInfo:@{NSLocalizedDescriptionKey: @"Twilio provider requires a secrets provider"}];
            }
            return nil;
        }
        return [[PDSTwilioPhoneVerificationProvider alloc] initWithSecretsProvider:secretsProvider
                                                                   configuration:configuration ?: @{}];
    }

    if ([provider isEqualToString:@"vonage"]) {
        if (!secretsProvider) {
            if (error) {
                *error = [NSError errorWithDomain:PDSPhoneVerificationProviderErrorDomain
                                             code:PDSPhoneVerificationProviderErrorNotConfigured
                                         userInfo:@{NSLocalizedDescriptionKey: @"Vonage provider requires a secrets provider"}];
            }
            return nil;
        }
        return [[PDSVonagePhoneVerificationProvider alloc] initWithSecretsProvider:secretsProvider
                                                                   configuration:configuration ?: @{}];
    }

    if ([provider isEqualToString:@"plivo"]) {
        if (!secretsProvider) {
            if (error) {
                *error = [NSError errorWithDomain:PDSPhoneVerificationProviderErrorDomain
                                             code:PDSPhoneVerificationProviderErrorNotConfigured
                                         userInfo:@{NSLocalizedDescriptionKey: @"Plivo provider requires a secrets provider"}];
            }
            return nil;
        }
        return [[PDSPlivoPhoneVerificationProvider alloc] initWithSecretsProvider:secretsProvider
                                                                  configuration:configuration ?: @{}];
    }

    if ([provider isEqualToString:@"telegram"]) {
        if (!secretsProvider) {
            if (error) {
                *error = [NSError errorWithDomain:PDSPhoneVerificationProviderErrorDomain
                                             code:PDSPhoneVerificationProviderErrorNotConfigured
                                         userInfo:@{NSLocalizedDescriptionKey: @"Telegram Gateway provider requires a secrets provider"}];
            }
            return nil;
        }
        return [[PDSTelegramGatewayPhoneVerificationProvider alloc] initWithSecretsProvider:secretsProvider
                                                                             configuration:configuration ?: @{}];
    }

    // Custom providers registered via registerProviderClass:forName:
    __block Class providerClass = Nil;
    dispatch_sync([self registryQueue], ^{
        providerClass = [self customProviderRegistry][provider];
    });
    if (providerClass) {
        id providerInstance = [[providerClass alloc] init];
        if ([providerInstance conformsToProtocol:@protocol(PDSPhoneVerificationProvider)]) {
            return providerInstance;
        }

        if (error) {
            *error = [NSError errorWithDomain:PDSPhoneVerificationProviderErrorDomain
                                         code:PDSPhoneVerificationProviderErrorRequestFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Custom phone verification provider failed to initialize"}];
        }
        return nil;
    }

    if (error) {
        *error = [NSError errorWithDomain:PDSPhoneVerificationProviderErrorDomain
                                     code:PDSPhoneVerificationProviderErrorUnsupportedProvider
                                 userInfo:@{
                                     NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported phone verification provider: %@", provider],
                                     @"provider": provider
                                 }];
    }
    return nil;
}

+ (nullable id<PDSPhoneVerificationProvider>)providerWithName:(NSString *)providerName error:(NSError **)error {
    return [self providerWithName:providerName
                    configuration:nil
                   secretsProvider:nil
                             error:error];
}

@end
