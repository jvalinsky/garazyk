#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const HandleErrorDomain;

typedef NS_ENUM(NSInteger, HandleError) {
    HandleErrorInvalidFormat = 1000,
    HandleErrorResolutionFailed,
    HandleErrorNetworkError,
    HandleErrorNotFound,
    HandleErrorSSRFAttempt,
    HandleErrorRateLimitExceeded
};

@interface HandleResolver : NSObject

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign) BOOL skipSSRFCheck;
@property (nonatomic, strong) NSCache<NSString *, NSString *> *resolutionCache;
@property (nonatomic, assign) NSTimeInterval cacheExpirationInterval;
@property (nonatomic, assign) NSUInteger rateLimitPerMinute;
@property (nonatomic, strong) NSMutableArray<NSDate *> *requestTimestamps;

- (instancetype)init;

- (void)resolveHandle:(NSString *)handle
            completion:(void (^)(NSString * _Nullable did, NSError * _Nullable error))completion;

- (void)resolveHandles:(NSArray<NSString *> *)handles
             completion:(void (^)(NSDictionary<NSString *, NSString *> * _Nullable results, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END