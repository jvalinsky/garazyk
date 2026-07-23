// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

@interface AppViewXRpcRoutePack (DraftsAndBookmarks)

- (void)handleGetDrafts:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetBookmarks:(HttpRequest *)request response:(HttpResponse *)response;

@end