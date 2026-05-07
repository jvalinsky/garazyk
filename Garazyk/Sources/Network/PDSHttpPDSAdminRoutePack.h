/*!
 @file PDSHttpPDSAdminRoutePack.h

 @abstract Declares PDS admin route-pack registration entry points.

 @discussion Specifies interfaces for registering operational administrative HTTP routes and integrating them with server runtime configuration.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class PDSServiceDatabases;

@interface PDSHttpPDSAdminRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server
                serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases;

@end

NS_ASSUME_NONNULL_END

