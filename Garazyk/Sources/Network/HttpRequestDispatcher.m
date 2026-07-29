// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HttpRequestDispatcher.m

 @abstract Implements request-dispatch flow from routed request to handler execution.

 @discussion Performs dispatch-time control flow that invokes selected handlers and coordinates response completion semantics. Owns dispatch mechanics rather than protocol parsing or transport I/O.
 */

#import "Network/HttpRequestDispatcher.h"

#import "Debug/GZLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"

/*!
 @brief Logs and converts an uncaught NSException at a dispatch site into a
 500 InternalServerError response.
 @discussion Defined after @end so the helper is file-local. Forward-declared
 here so @catch blocks inside @implementation can call it without producing
 -Wimplicit-function-declaration. Parity with XrpcHandler.m:372-402.
 */
static void HttpRequestDispatcherHandleException(NSException *exception,
                                                  HttpRequest *request,
                                                  HttpResponse *response,
                                                  NSString *context);

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
  GZ_LOG_HTTP_INFO(@"[%@] %@ %@", request.remoteAddress, request.methodString,
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
  }  if (self.requestHandler) {
    @try {
      self.requestHandler(request, response);
    } @catch (NSException *exception) {
      HttpRequestDispatcherHandleException(exception, request, response,
                                            @"requestHandler");
    }
    return response;
  }

  NSDictionary<NSString *, NSString *> *pathParameters = nil;
  HttpServerRequestHandler handler = self.routeLookupHandler
                                         ? self.routeLookupHandler(request.path, request.methodString, &pathParameters)
                                         : nil;
  request.pathParameters = pathParameters;
  if (handler) {
    @try {
      handler(request, response);
    } @catch (NSException *exception) {
      HttpRequestDispatcherHandleException(exception, request, response,
                                            @"route handler");
    }
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

static void HttpRequestDispatcherHandleException(NSException *exception,
                                                  HttpRequest *request,
                                                  HttpResponse *response,
                                                  NSString *context) {
  NSString *name = exception.name ?: @"(null)";
  NSString *reason = exception.reason ?: @"(null)";
  NSArray<NSString *> *stack = exception.callStackSymbols ?: @[];
  GZ_LOG_ERROR(@"[HTTP] Unhandled exception in %@ (%@ %@): %@ (%@)\n%@",
                context, request.methodString, request.path, name, reason,
                [stack componentsJoinedByString:@"\n"]);
  response.statusCode = HttpStatusInternalServerError;
  [response setJsonBody:@{
    @"error": @"InternalServerError",
    @"message": @"Unhandled exception"
  }];
}

@end
