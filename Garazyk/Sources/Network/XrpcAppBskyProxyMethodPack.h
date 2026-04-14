#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class XrpcDispatcher;

@interface XrpcAppBskyProxyMethodPack : NSObject

+ (void)registerProxyOnlyMethodsWithDispatcher:(XrpcDispatcher *)dispatcher;

@end

NS_ASSUME_NONNULL_END

