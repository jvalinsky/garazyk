// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSHttpOAuthDemoRoutePack.h

 @abstract Declares OAuth demo route-pack registration entry points.

 @discussion Specifies interfaces for registering OAuth demonstration endpoints in the HTTP router for interactive or local demo usage.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class PDSController;

@interface PDSHttpOAuthDemoRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server
                   dataDirectory:(nullable NSString *)dataDirectory
                      controller:(nullable PDSController *)controller;

@end

NS_ASSUME_NONNULL_END
