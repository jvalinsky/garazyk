// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file UITileExecutionPolicy.h

 @abstract Web Tiles execution-policy headers.

 @discussion Provides the exact restrictive response policy required by the
 DASL Web Tiles specification. The policy is additive and is not used for the
 existing authenticated Admin UI shell. It is not, by itself, a network
 boundary on a normal origin; unique-origin tile hosting remains required
 before arbitrary tile execution is enabled.

 @see https://dasl.ing/tiles.html
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Returns the normative Content-Security-Policy for a Web Tile execution context. */
FOUNDATION_EXPORT NSString *UITileExecutionContentSecurityPolicy(void);

/** Returns the complete non-CSP security header set required for a Web Tile. */
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *UITileExecutionSecurityHeaders(void);

NS_ASSUME_NONNULL_END
