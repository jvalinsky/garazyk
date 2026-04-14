/*!
 @file PDSHttpRelayAPIRoutePack.h

 @abstract Registers relay API routes on an HTTP server.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;

@interface PDSHttpRelayAPIRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END
