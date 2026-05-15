// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoHttpMSTViewerRoutePack.h

 @abstract Declares MST viewer route-pack registration entry points.

 @discussion Specifies interfaces used to register MST viewer HTTP endpoints with the server router. Defines registration contracts, not MST data processing behavior.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class PDSController;

@interface ATProtoHttpMSTViewerRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server
                      controller:(nullable PDSController *)controller;

@end

NS_ASSUME_NONNULL_END
