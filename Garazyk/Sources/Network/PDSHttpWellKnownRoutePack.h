/*!
 @file PDSHttpWellKnownRoutePack.h

 @abstract Declares well-known route-pack registration entry points.

 @discussion Specifies interfaces for registering standardized discovery endpoints under well-known HTTP paths used by clients and federated services.
 */

#import <Foundation/Foundation.h>
#import "Network/PDSHttpRoutePackTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class PDSConfiguration;
@class PDSController;
@class PDSServiceDatabases;

@interface PDSHttpWellKnownRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server
                serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases
                      controller:(nullable PDSController *)controller
                   configuration:(nullable PDSConfiguration *)configuration
                  setCorsHeaders:(PDSHttpSetCorsHeadersBlock)setCorsHeaders;

@end

NS_ASSUME_NONNULL_END

