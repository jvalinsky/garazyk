// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class HttpRequest;
@class HttpResponse;

NS_ASSUME_NONNULL_BEGIN

@interface GZXrpcRouteSupport : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (BOOL)checkIPRateLimitForRequest:(HttpRequest *)request response:(HttpResponse *)response;
+ (nullable NSString *)requiredQueryParam:(NSString *)name request:(HttpRequest *)request response:(HttpResponse *)response;
+ (BOOL)parseLimitForRequest:(HttpRequest *)request
                defaultLimit:(NSInteger)defaultLimit
                         min:(NSInteger)min
                         max:(NSInteger)max
                      output:(NSInteger *)output
                    response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
