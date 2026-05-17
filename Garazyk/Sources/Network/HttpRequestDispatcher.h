// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HttpRequestDispatcher.h

 @abstract Defines request-dispatch contracts that bind parsed HTTP requests to route handlers.

 @discussion Declares dispatcher interfaces for handing normalized request objects to routing components and returning response outcomes. Keeps dispatch orchestration separate from endpoint business logic.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

typedef void (^HttpServerRequestHandler)(HttpRequest *request, HttpResponse *response);
typedef HttpServerRequestHandler _Nullable (^HttpRouteLookupHandler)(
    NSString *path,
    NSString *method,
    NSDictionary<NSString *, NSString *> *_Nullable *_Nullable parameters);

@interface HttpRequestDispatcher : NSObject

/**
 * @abstract Exposes the request handler value.
 */
@property(nonatomic, copy, nullable) HttpServerRequestHandler requestHandler;
@property(nonatomic, copy) HttpRouteLookupHandler routeLookupHandler;

/**
 * @abstract Performs the initWithRouteLookupHandler operation.
 */
- (instancetype)initWithRouteLookupHandler:(HttpRouteLookupHandler)routeLookupHandler;
/**
 * @abstract Performs the dispatchRequest operation.
 */
- (HttpResponse *)dispatchRequest:(HttpRequest *)request;

@end

NS_ASSUME_NONNULL_END
