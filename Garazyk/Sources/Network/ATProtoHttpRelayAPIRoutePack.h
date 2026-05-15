// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSHttpRelayAPIRoutePack.h

 @abstract Declares relay API route-pack registration entry points.

 @discussion Specifies interfaces for registering relay-facing API routes used by sync and operational relay surfaces.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;

@interface PDSHttpRelayAPIRoutePack : NSObject

+ (void)registerRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END
