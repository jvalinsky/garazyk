/*!
 @file PDSHttpOAuthDemoRoutePack.h

 @abstract Registers OAuth demo routes on an HTTP server.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class PDSController;

@interface PDSHttpOAuthDemoRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server
                   dataDirectory:(nullable NSString *)dataDirectory
                      controller:(nullable PDSController *)controller;

@end

NS_ASSUME_NONNULL_END
