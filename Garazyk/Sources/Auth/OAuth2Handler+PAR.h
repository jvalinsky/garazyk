// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface OAuth2Handler (PAR)
- (void)handlePARRequest:(HttpRequest *)request
                response:(HttpResponse *)response;
- (NSDictionary *)consumePARRequestForURI:(NSString *)requestURI
                                 clientID:(NSString *)clientID
                                    error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
