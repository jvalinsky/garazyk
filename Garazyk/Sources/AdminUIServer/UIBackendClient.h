#import <Foundation/Foundation.h>

@class UIServiceConfig;

NS_ASSUME_NONNULL_BEGIN

@interface UIBackendClient : NSObject

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration;

- (NSDictionary *)fetchServiceOverview;
- (NSDictionary *)searchAccountsWithQuery:(nullable NSString *)query;
- (NSDictionary *)fetchInviteCodes;
- (NSDictionary *)disableInvitesForAccount:(NSString *)account;

@end

NS_ASSUME_NONNULL_END

