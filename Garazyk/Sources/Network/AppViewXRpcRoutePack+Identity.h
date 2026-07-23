// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

@interface AppViewXRpcRoutePack (Identity)

- (void)handleResolveHandle:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetRecord:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleQueryLabels:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetAccountInfos:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetSubjectStatus:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleProxyWrite:(HttpRequest *)request response:(HttpResponse *)response nsid:(NSString *)nsid;

@end