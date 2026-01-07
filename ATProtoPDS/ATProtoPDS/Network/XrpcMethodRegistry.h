#import <Foundation/Foundation.h>
#import "XrpcHandler.h"
#import "../PDSController.h"
#import "HttpRequest.h"
#import "HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface XrpcMethodRegistry : NSObject

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller;

@end

NS_ASSUME_NONNULL_END
