#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PDSPhoneVerificationProviderErrorDomain;

typedef NS_ENUM(NSInteger, PDSPhoneVerificationProviderErrorCode) {
    PDSPhoneVerificationProviderErrorNotConfigured = 1,
    PDSPhoneVerificationProviderErrorUnsupportedProvider = 2,
    PDSPhoneVerificationProviderErrorRequestFailed = 3,
};

@protocol PDSPhoneVerificationProvider <NSObject>

- (BOOL)requestVerificationForPhoneNumber:(NSString *)phoneNumber error:(NSError **)error;

@end

@interface PDSPhoneVerificationProviderFactory : NSObject

+ (nullable id<PDSPhoneVerificationProvider>)providerWithName:(NSString *)providerName error:(NSError **)error;
+ (void)registerProviderClass:(Class)providerClass forName:(NSString *)providerName;
+ (void)unregisterProviderWithName:(NSString *)providerName;
+ (void)resetCustomProviders;

@end

NS_ASSUME_NONNULL_END
