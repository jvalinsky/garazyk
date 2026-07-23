// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface OAuth2Handler (TokenRevocation)
- (void)handleRevokeRequest:(HttpRequest *)request
                   response:(HttpResponse *)response;
- (void)handleIntrospectRequest:(HttpRequest *)request
                       response:(HttpResponse *)response;
@end

NS_ASSUME_NONNULL_END
