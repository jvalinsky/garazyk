/*!
 @file PDSHttpMSTViewerRoutePack.h

 @abstract Declares MST viewer route-pack registration entry points.

 @discussion Specifies interfaces used to register MST viewer HTTP endpoints with the server router. Defines registration contracts, not MST data processing behavior.
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
