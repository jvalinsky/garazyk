/*!
 @file PDSHttpOAuthRoutePack.h

 @abstract Registers OAuth and WebAuthn route pack on an HTTP server.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class JWTMinter;
@class PDSApplication;
@class PDSController;
@class PDSServiceDatabases;

@interface PDSHttpOAuthRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server
                serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases
                       jwtMinter:(nullable JWTMinter *)jwtMinter
                   dataDirectory:(nullable NSString *)dataDirectory
                     application:(nullable PDSApplication *)application
                      controller:(nullable PDSController *)controller;

@end

NS_ASSUME_NONNULL_END
