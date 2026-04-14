#import "PDSEnvironmentSecretsProvider.h"

NSString *const PDSEnvironmentSecretsProviderErrorDomain = @"PDSEnvironmentSecretsProviderErrorDomain";

@interface PDSEnvironmentSecretsProvider ()

@property (nonatomic, copy, readwrite) NSString *keyPrefix;

@end

@implementation PDSEnvironmentSecretsProvider

- (instancetype)init {
    return [self initWithPrefix:nil];
}

- (instancetype)initWithPrefix:(nullable NSString *)prefix {
    if (self = [super init]) {
        _keyPrefix = prefix ? [prefix copy] : @"";
    }
    return self;
}

- (nullable NSString *)secretForKey:(NSString *)key error:(NSError **)error {
    if (key.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSEnvironmentSecretsProviderErrorDomain
                                         code:PDSEnvironmentSecretsProviderErrorInvalidKey
                                     userInfo:@{NSLocalizedDescriptionKey: @"Key cannot be empty"}];
        }
        return nil;
    }
    
    NSString *fullKey = [self.keyPrefix stringByAppendingString:key];
    NSString *value = [[[NSProcessInfo processInfo] environment] objectForKey:fullKey];
    
    if (value == nil) {
        if (error) {
            *error = [NSError errorWithDomain:PDSEnvironmentSecretsProviderErrorDomain
                                         code:PDSEnvironmentSecretsProviderErrorKeyNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Environment variable not found: %@", fullKey]}];
        }
        return nil;
    }
    
    return value;
}

@end
