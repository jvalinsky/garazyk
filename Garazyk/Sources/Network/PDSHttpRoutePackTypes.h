// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSHttpRoutePackTypes.h

 @abstract Declares shared types used by HTTP route-pack registration components.

 @discussion Provides common type definitions and contracts used across route-pack modules to ensure consistent registration signatures and wiring behavior.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

typedef void (^PDSHttpSetCorsHeadersBlock)(HttpResponse *response,
                                           HttpRequest *request);

NS_ASSUME_NONNULL_END

