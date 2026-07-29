// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

typedef void (^HttpRouteHandler)(HttpRequest *request, HttpResponse *response);

/*!
 @class HttpRoute

 @abstract Represents a single HTTP route with method, pattern, and handler.

 @discussion HttpRoute encapsulates all the information needed for a route:
 the HTTP method, URL pattern, handler block, and priority for resolution order.
 */
@interface HttpRoute : NSObject

/**
 * @abstract Exposes the method value.
 */
@property (nonatomic, readonly, copy) NSString *method;
@property (nonatomic, readonly, copy) NSString *pattern;
@property (nonatomic, readonly, copy) HttpRouteHandler handler;
@property (nonatomic, readonly) NSUInteger priority;

/*!
 @method initWithMethod:pattern:handler:priority:

 @abstract Initialize a route with the specified parameters.

 @param method The HTTP method (GET, POST, etc.) or "*" for all methods.
 @param pattern The URL pattern with optional parameters (e.g., "/users/:id").
 @param handler The handler block to execute for matching requests.
 @param priority Route priority for resolution ordering (higher = more specific).

 @return An initialized HttpRoute instance.
 */
/**
 * @abstract Performs the initWithMethod operation.
 */
- (instancetype)initWithMethod:(NSString *)method
                       pattern:(NSString *)pattern
                       handler:(HttpRouteHandler)handler
                      priority:(NSUInteger)priority;

@end

NS_ASSUME_NONNULL_END
