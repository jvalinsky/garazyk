/*!
 @file PDSHttpMSTViewerRoutePack.h

 @abstract Registers MST viewer routes on an HTTP server.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class PDSController;

@interface PDSHttpMSTViewerRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server
                      controller:(nullable PDSController *)controller;

@end

NS_ASSUME_NONNULL_END
