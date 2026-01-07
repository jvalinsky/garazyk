#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

typedef NS_ENUM(NSInteger, RateLimitType) {
    RateLimitTypeDID,
    RateLimitTypeIP,
    RateLimitTypeBlob
};

@interface RateLimitResult : NSObject

@property (nonatomic, assign) BOOL allowed;
@property (nonatomic, assign) NSInteger limit;
@property (nonatomic, assign) NSInteger remaining;
@property (nonatomic, assign) NSTimeInterval resetSeconds;
@property (nonatomic, assign) NSTimeInterval retryAfter;

+ (instancetype)resultAllowed:(BOOL)allowed
                        limit:(NSInteger)limit
                    remaining:(NSInteger)remaining
                  resetSeconds:(NSTimeInterval)resetSeconds
                   retryAfter:(NSTimeInterval)retryAfter;

@end

@interface RateLimiter : NSObject

@property (nonatomic, assign) NSInteger didLimit;
@property (nonatomic, assign) NSTimeInterval didWindowSeconds;
@property (nonatomic, assign) NSInteger ipLimit;
@property (nonatomic, assign) NSTimeInterval ipWindowSeconds;
@property (nonatomic, assign) NSInteger blobLimit;
@property (nonatomic, assign) NSTimeInterval blobWindowSeconds;

+ (instancetype)sharedLimiter;

- (instancetype)initWithDatabasePath:(NSString *)path;

- (RateLimitResult *)checkRateLimitForDid:(NSString *)did;
- (RateLimitResult *)checkRateLimitForIP:(NSString *)ip;
- (RateLimitResult *)checkBlobUploadRateLimitForDid:(NSString *)did;

- (NSDictionary<NSString *, NSString *> *)rateLimitHeadersForDid:(NSString *)did;
- (NSDictionary<NSString *, NSString *> *)rateLimitHeadersForIP:(NSString *)ip;
- (NSDictionary<NSString *, NSString *> *)blobRateLimitHeadersForDid:(NSString *)did;

- (void)applyRateLimitHeadersToResponse:(HttpResponse *)response
                                  forDid:(nullable NSString *)did
                                    ip:(nullable NSString *)ip;

@end

NS_ASSUME_NONNULL_END
