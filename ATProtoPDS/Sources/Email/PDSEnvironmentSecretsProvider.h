#import "PDSSecretsProvider.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PDSEnvironmentSecretsProviderError) {
    PDSEnvironmentSecretsProviderErrorInvalidKey = 1,
    PDSEnvironmentSecretsProviderErrorKeyNotFound = 2
};

@interface PDSEnvironmentSecretsProvider : NSObject <PDSSecretsProvider>

@property (nonatomic, copy, readonly) NSString *keyPrefix;

- (instancetype)initWithPrefix:(nullable NSString *)prefix NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
