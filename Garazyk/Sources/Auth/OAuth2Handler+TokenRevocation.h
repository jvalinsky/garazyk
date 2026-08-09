// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface OAuth2Handler (TokenRevocation)
- (void)handleRevokeRequest:(ATProtoHttpRequest *)request
                   response:(ATProtoHttpResponse *)response;
- (void)handleIntrospectRequest:(ATProtoHttpRequest *)request
                       response:(ATProtoHttpResponse *)response;
@end

NS_ASSUME_NONNULL_END
