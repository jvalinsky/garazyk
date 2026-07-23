// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface OAuth2Handler (Metadata)
- (void)handleAuthorizationServerMetadata:(HttpRequest *)request
                                 response:(HttpResponse *)response;
- (void)handleProtectedResourceMetadata:(HttpRequest *)request
                               response:(HttpResponse *)response;
- (void)handleJWKS:(HttpRequest *)request response:(HttpResponse *)response;
@end

NS_ASSUME_NONNULL_END
