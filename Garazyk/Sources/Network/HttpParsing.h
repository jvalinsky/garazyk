// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HttpParsing.h

 @abstract Provides shared HTTP parsing types and helpers for protocol components.

 @discussion Declares parsing primitives and related utilities reused by parser and session code. Keeps parsing contracts explicit and avoids coupling to transport sockets or route handlers.
 */

#import <Foundation/Foundation.h>
#import "Network/HttpRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface HttpParsing : NSObject

/**
 * @abstract Performs the parseQueryString operation.
 */
+ (NSDictionary<NSString *, id> *)parseQueryString:(NSString *)queryString;
/**
 * @abstract Performs the urlDecode operation.
 */
+ (NSString *)urlDecode:(NSString *)string;
/**
 * @abstract Performs the methodFromString operation.
 */
+ (HttpMethod)methodFromString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
