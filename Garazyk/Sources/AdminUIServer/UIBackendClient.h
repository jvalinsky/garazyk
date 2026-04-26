#import <Foundation/Foundation.h>

@class UIServiceConfig;

NS_ASSUME_NONNULL_BEGIN

@interface UIBackendClient : NSObject

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration;

- (NSDictionary *)fetchServiceOverview;
- (NSDictionary *)searchAccountsWithQuery:(nullable NSString *)query;
- (NSDictionary *)fetchInviteCodes;
- (NSDictionary *)disableInvitesForAccount:(NSString *)account;

// AppView Admin Operations
- (NSDictionary *)fetchAppViewMetrics;
- (NSDictionary *)fetchIngestHealth;
- (NSDictionary *)fetchBackfillQueueWithStatus:(nullable NSString *)status limit:(NSUInteger)limit cursor:(nullable NSString *)cursor;
- (NSDictionary *)retryBackfillForDID:(NSString *)did;
- (NSDictionary *)cancelBackfillForDID:(NSString *)did;
- (NSDictionary *)enqueueBackfillDIDs:(NSArray<NSString *> *)dids;
- (NSDictionary *)rebuildBackfillScope;

// Relay Admin Operations
- (NSDictionary *)fetchRelayMetrics;

@end

NS_ASSUME_NONNULL_END

