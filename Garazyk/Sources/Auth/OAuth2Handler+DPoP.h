// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface OAuth2Handler (DPoP)
- (BOOL)validateDPoPForRequest:(HttpRequest *)request
                      response:(HttpResponse *)response
                 outThumbprint:(NSString **)outThumbprint;
- (void)attachDPoPNonceToResponseIfMissing:(HttpResponse *)response;
- (NSURL *)expectedDPoPURLForRequest:(HttpRequest *)request;
- (NSString *)requestOriginForRequest:(HttpRequest *)request;
- (BOOL)requestShouldTrustForwardedHeaders:(HttpRequest *)request;
@end

NS_ASSUME_NONNULL_END
