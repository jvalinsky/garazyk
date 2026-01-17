#import <Foundation/Foundation.h>

@class HttpRequest;
@class HttpResponse;
@class PDSController;

NS_ASSUME_NONNULL_BEGIN

@interface OAuthDemoHandler : NSObject

+ (instancetype)sharedHandler;

- (void)setController:(PDSController *)controller;

- (BOOL)canHandleRequest:(HttpRequest *)request;

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
