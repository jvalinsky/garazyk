// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoHttpWellKnownRoutePack.h

 @abstract Declares well-known route-pack registration entry points.

 @discussion Specifies interfaces for registering standardized discovery endpoints under well-known HTTP paths used by clients and federated services.
 */

#import <Foundation/Foundation.h>
#import "Network/ATProtoHttpRoutePackTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class ATProtoServiceConfiguration;
@class PDSController;
@class PDSServiceDatabases;

@interface ATProtoHttpWellKnownRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server
                serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases
                      controller:(nullable PDSController *)controller
                   configuration:(nullable ATProtoServiceConfiguration *)configuration
                  setCorsHeaders:(ATProtoHttpSetCorsHeadersBlock)setCorsHeaders;

@end

NS_ASSUME_NONNULL_END

