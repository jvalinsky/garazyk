// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

@interface AppViewXRpcRoutePack (Search)

- (void)handleSearchActorsSkeleton:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleSearchPostsSkeleton:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleSearchStarterPacksSkeleton:(HttpRequest *)request response:(HttpResponse *)response;

@end