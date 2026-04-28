/*!
 @file PDSHttpPDSAdminRoutePack.h

 @abstract Registers private PDS operational admin routes.
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

