/*!
 @file PDSHttpCappuccinoUIRoutePack.h

 @abstract Registers Cappuccino UI routes on an HTTP server.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class PDSController;

@interface PDSHttpCappuccinoUIRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server
                   dataDirectory:(nullable NSString *)dataDirectory
                      controller:(nullable PDSController *)controller;

@end

NS_ASSUME_NONNULL_END
