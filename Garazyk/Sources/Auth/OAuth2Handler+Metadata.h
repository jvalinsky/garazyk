// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface OAuth2Handler (Metadata)
- (void)handleAuthorizationServerMetadata:(ATProtoHttpRequest *)request
                                 response:(ATProtoHttpResponse *)response;
- (void)handleProtectedResourceMetadata:(ATProtoHttpRequest *)request
                               response:(ATProtoHttpResponse *)response;
- (void)handleJWKS:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
@end

NS_ASSUME_NONNULL_END
