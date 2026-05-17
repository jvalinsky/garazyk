// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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

/**
 * @abstract Performs the registerRoutesWithServer operation.
 */
+ (void)registerRoutesWithServer:(HttpServer *)server
                serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases;

@end

NS_ASSUME_NONNULL_END

