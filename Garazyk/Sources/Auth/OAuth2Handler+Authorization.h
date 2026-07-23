// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface OAuth2Handler (Authorization)
- (void)handleAuthorizeRequest:(HttpRequest *)request
                      response:(HttpResponse *)response;
- (void)handleAuthorizeConfirm:(HttpRequest *)request
                      response:(HttpResponse *)response;
- (void)handleAuthorizeSignIn:(HttpRequest *)request
                     response:(HttpResponse *)response;
- (void)serveAuthorizePage:(HttpResponse *)response
                    params:(NSDictionary *)params
                    client:(NSDictionary *)client;
@end

NS_ASSUME_NONNULL_END
