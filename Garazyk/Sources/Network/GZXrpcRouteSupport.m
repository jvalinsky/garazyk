// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/GZXrpcRouteSupport.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RateLimiter.h"
#import "Network/XrpcErrorHelper.h"

@implementation GZXrpcRouteSupport

+ (BOOL)checkIPRateLimitForRequest:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response {
    RateLimiter *limiter = [RateLimiter sharedLimiter];
    RateLimitResult *rateLimit = [limiter checkRateLimitForIP:request.remoteAddress];
    if (rateLimit.allowed) return YES;

    response.statusCode = HttpStatusTooManyRequests;
    [response setJsonBody:@{
        @"error": @"RateLimitExceeded",
        @"message": @"Too many requests"
    }];
    [limiter applyRateLimitHeadersToResponse:response forDid:nil ip:request.remoteAddress];
    [response setHeader:[NSString stringWithFormat:@"%.0f", rateLimit.retryAfter] forKey:@"Retry-After"];
    return NO;
}

+ (nullable NSString *)requiredQueryParam:(NSString *)name request:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response {
    NSString *value = [request queryParamForKey:name];
    if (value.length == 0) {
        [XrpcErrorHelper setInvalidRequestError:response
                                        message:[NSString stringWithFormat:@"%@ parameter is required", name]];
        return nil;
    }
    return value;
}

+ (BOOL)parseLimitForRequest:(ATProtoHttpRequest *)request
                defaultLimit:(NSInteger)defaultLimit
                         min:(NSInteger)min
                         max:(NSInteger)max
                      output:(NSInteger *)output
                    response:(ATProtoHttpResponse *)response {
    NSInteger limit = defaultLimit;
    NSString *limitParam = [request queryParamForKey:@"limit"];
    if (limitParam.length > 0) {
        NSScanner *scanner = [NSScanner scannerWithString:limitParam];
        scanner.charactersToBeSkipped = nil;
        if (![scanner scanInteger:&limit] || !scanner.isAtEnd || limit < min || limit > max) {
            [XrpcErrorHelper setInvalidRequestError:response
                                            message:[NSString stringWithFormat:@"limit must be an integer between %ld and %ld",
                                                     (long)min,
                                                     (long)max]];
            return NO;
        }
    }
    if (output) *output = limit;
    return YES;
}

@end
