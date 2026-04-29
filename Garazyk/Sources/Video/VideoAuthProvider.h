#import <Foundation/Foundation.h>

@class HttpRequest;
@class HttpResponse;

NS_ASSUME_NONNULL_BEGIN

@protocol VideoAuthProvider <NSObject>

- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                   response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
