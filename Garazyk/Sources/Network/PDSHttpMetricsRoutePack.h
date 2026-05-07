/*!
 @file PDSHttpMetricsRoutePack.h

 @abstract Declares metrics route-pack registration entry points.

 @discussion Specifies interfaces for attaching metrics and observability endpoints to HTTP routing. Owns route registration surface definition only.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;

@interface PDSHttpMetricsRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END
