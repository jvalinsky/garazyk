#import "PDSSecretsProvider.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PDSKeychainSecretsProviderError) {
    PDSKeychainSecretsProviderErrorInvalidKey = 1,
    PDSKeychainSecretsProviderErrorItemNotFound = 2,
    PDSKeychainSecretsProviderErrorKeychainFailure = 3,
    PDSKeychainSecretsProviderErrorInvalidInput = 4,
    PDSKeychainSecretsProviderErrorStorageFailed = 5,
    PDSKeychainSecretsProviderErrorDeletionFailed = 6
};

@interface PDSKeychainSecretsProvider : NSObject <PDSSecretsProvider>

@property (nonatomic, copy, readonly) NSString *service;

- (instancetype)initWithService:(NSString *)service NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

- (BOOL)storeSecret:(NSString *)secret forKey:(NSString *)key error:(NSError **)error;
- (BOOL)deleteSecretForKey:(NSString *)key error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
