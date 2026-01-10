#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const HandleErrorDomain;

typedef NS_ENUM(NSInteger, HandleError) {
    HandleErrorInvalidFormat = 1000,
    HandleErrorResolutionFailed,
    HandleErrorNetworkError,
    HandleErrorNotFound,
    HandleErrorSSRFAttempt
};

@interface HandleResolver : NSObject

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign) BOOL skipSSRFCheck;

- (instancetype)init;

- (void)resolveHandle:(NSString *)handle
           completion:(void (^)(NSString * _Nullable did, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END