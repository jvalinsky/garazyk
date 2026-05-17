// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class HttpRequest;
@class HttpResponse;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Defines the VideoAuthProvider protocol contract.
 */
@protocol VideoAuthProvider <NSObject>

/**
 * @abstract Performs the authenticateRequest operation.
 */
- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                   response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
