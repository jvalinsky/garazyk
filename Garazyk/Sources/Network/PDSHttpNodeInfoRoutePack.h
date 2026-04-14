/*!
 @file PDSHttpNodeInfoRoutePack.h

 @abstract Registers NodeInfo routes on an HTTP server.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class PDSApplication;
@class PDSConfiguration;
@class PDSController;

@interface PDSHttpNodeInfoRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server
                          issuer:(nullable NSString *)issuer
                            port:(NSUInteger)port
                   configuration:(nullable PDSConfiguration *)configuration
                     application:(nullable PDSApplication *)application
                      controller:(nullable PDSController *)controller;

@end

NS_ASSUME_NONNULL_END
