#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;
@class PDSServiceDatabases;

typedef NS_ENUM(NSInteger, PDSHealthStatus) {
    PDSHealthStatusHealthy = 0,
    PDSHealthStatusWarning,
    PDSHealthStatusCritical,
};

@interface PDSHealthCheck : NSObject

+ (instancetype)sharedInstance;

- (NSDictionary<NSString *, id> *)performHealthCheck;

- (PDSHealthStatus)checkDatabaseIntegrity:(NSError **)error;
- (BOOL)checkForeignKeys:(NSError **)error;
- (NSDictionary<NSString *, NSNumber *> *)getTableSizes;
- (NSUInteger)getFragmentationPercent;

- (NSDictionary<NSString *, id> *)collectMetrics;

- (NSArray<NSString *> *)getWarnings;
- (NSArray<NSString *> *)getErrors;

@end

NS_ASSUME_NONNULL_END
