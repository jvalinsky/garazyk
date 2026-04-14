/*!
 @file PDSHttpAdminRoutePack.h

 @abstract Registers admin and admin UI route packs.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;

@interface PDSHttpAdminRoutePack : NSObject

+ (void)registerAdminRoutesWithServer:(HttpServer *)server;
+ (void)registerAdminUIRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END

