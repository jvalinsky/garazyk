// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class JWTMinter;
@class PDSConfiguration;
@class PDSDatabasePool;
@class PDSServiceDatabases;
@class XrpcDispatcher;
@protocol PDSAdminController;

@interface XrpcProxyInterceptor : NSObject

+ (void)installOnDispatcher:(XrpcDispatcher *)dispatcher
              configuration:(PDSConfiguration *)configuration
                  jwtMinter:(JWTMinter *)jwtMinter
            adminController:(id<PDSAdminController>)adminController
           serviceDatabases:(PDSServiceDatabases *)serviceDatabases
           userDatabasePool:(PDSDatabasePool *)userDatabasePool;

@end

NS_ASSUME_NONNULL_END

