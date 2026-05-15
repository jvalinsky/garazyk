// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSHttpNodeInfoRoutePack.h

 @abstract Declares node-info route-pack registration entry points.

 @discussion Specifies interfaces for registering node information and diagnostics HTTP routes with the server runtime.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class PDSApplication;
@class PDSConfiguration;
@class PDSController;

@interface PDSHttpNodeInfoRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server
                          issuer:(nullable NSString *)issuer
                            port:(NSUInteger)port
                   configuration:(nullable PDSConfiguration *)configuration
                     application:(nullable PDSApplication *)application
                      controller:(nullable PDSController *)controller;

@end

NS_ASSUME_NONNULL_END
