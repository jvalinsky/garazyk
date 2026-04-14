/*!
 @file PDSHttpExploreRoutePack.h

 @abstract Registers Explore UI and API routes on an HTTP server.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ExploreHandler;
@class HttpServer;
@class PDSController;

@interface PDSHttpExploreRoutePack : NSObject

+ (nullable ExploreHandler *)registerRoutesWithServer:(HttpServer *)server
                                           controller:(nullable PDSController *)controller;

@end

NS_ASSUME_NONNULL_END
