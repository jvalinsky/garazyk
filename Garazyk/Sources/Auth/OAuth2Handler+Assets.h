// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface OAuth2Handler (Assets)
- (NSString *)assetsPath;
- (NSString *)sharedCSSPath;
- (void)handleCSSRequest:(ATProtoHttpRequest *)request
                response:(ATProtoHttpResponse *)response;
- (NSString *)escapeHtml:(NSString *)input;
@end

NS_ASSUME_NONNULL_END
