// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HttpRequestDispatcher.m

 @abstract Implements request-dispatch flow from routed request to handler execution.

 @discussion Performs dispatch-time control flow that invokes selected handlers and coordinates response completion semantics. Owns dispatch mechanics rather than protocol parsing or transport I/O.
 */

#import "Network/HttpRequestDispatcher.h"

#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"

@implementation HttpRequestDispatcher

- (instancetype)initWithRouteLookupHandler:(HttpRouteLookupHandler)routeLookupHandler {
  self = [super init];
  if (self) {
    _routeLookupHandler = [routeLookupHandler copy];
  }
  return self;
}

- (HttpResponse *)dispatchRequest:(HttpRequest *)request {
  NSString *logPath = request.queryString.length > 0
                          ? [NSString stringWithFormat:@"%@?%@", request.path,
                                                       request.queryString]
                          : request.path;
  PDS_LOG_HTTP_INFO(@"[%@] %@ %@", request.remoteAddress, request.methodString,
                    logPath);

  HttpResponse *response = [HttpResponse response];
  if ([request.path hasPrefix:@"/oauth/"] && !RateLimiterIsDisabledGlobally() &&
      [RateLimiter sharedLimiter].isEnabled) {
    RateLimitResult *result =
        [[RateLimiter sharedLimiter] checkRateLimitForIP:request.remoteAddress];
    if (!result.allowed) {
      response.statusCode = 429;
      [response setJsonBody:@{
        @"error" : @"too_many_requests",
        @"message" : @"Rate limit exceeded"
      }];
      return response;
    }
  }

  if (self.requestHandler) {
    self.requestHandler(request, response);
    return response;
  }

  NSDictionary<NSString *, NSString *> *pathParameters = nil;
  HttpServerRequestHandler handler = self.routeLookupHandler
                                         ? self.routeLookupHandler(request.path, request.methodString, &pathParameters)
                                         : nil;
  request.pathParameters = pathParameters;
  if (handler) {
    handler(request, response);
  } else {
    response.statusCode = HttpStatusNotFound;
    [response setJsonBody:@{
      @"error" : @"Not Found",
      @"message" : [NSString stringWithFormat:@"No handler for %@ %@",
                                             request.methodString, request.path]
    }];
  }
  return response;
}

@end
