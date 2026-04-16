#import "Services/Core/PDSPhoneVerificationProvider.h"

NSString * const PDSPhoneVerificationProviderErrorDomain = @"com.atproto.pds.phoneverificationprovider";

@interface PDSMockPhoneVerificationProvider : NSObject <PDSPhoneVerificationProvider>
@end

@implementation PDSMockPhoneVerificationProvider

- (BOOL)requestVerificationForPhoneNumber:(NSString *)phoneNumber error:(NSError **)error {
    (void)phoneNumber;
    (void)error;
    return YES;
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

+ (nullable id<PDSPhoneVerificationProvider>)providerWithName:(NSString *)providerName error:(NSError **)error {
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

@end
