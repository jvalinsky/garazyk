// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class ATProtoHttpRequest;
@class ATProtoHttpResponse;

NS_ASSUME_NONNULL_BEGIN

@interface GZXrpcRouteSupport : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (BOOL)checkIPRateLimitForRequest:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
+ (nullable NSString *)requiredQueryParam:(NSString *)name request:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
+ (BOOL)parseLimitForRequest:(ATProtoHttpRequest *)request
                defaultLimit:(NSInteger)defaultLimit
                         min:(NSInteger)min
                         max:(NSInteger)max
                      output:(NSInteger *)output
                    response:(ATProtoHttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
