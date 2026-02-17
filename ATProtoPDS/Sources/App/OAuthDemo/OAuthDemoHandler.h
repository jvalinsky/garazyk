#import <Foundation/Foundation.h>

@class HttpRequest;
@class HttpResponse;
NS_ASSUME_NONNULL_BEGIN

@class PDSController;

@interface OAuthDemoHandler : NSObject

+ (instancetype)sharedHandler;

- (void)setDataDirectory:(NSString *)dataDirectory;

- (void)setController:(PDSController *)controller
    DEPRECATED_MSG_ATTRIBUTE("Use setDataDirectory: instead");

- (BOOL)canHandleRequest:(HttpRequest *)request;

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
