// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

@interface AppViewXRpcRoutePack (Actor)

- (void)handleGetProfile:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetProfiles:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleSearchActors:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleSearchActorsTypeahead:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetPreferences:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handlePutPreferences:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetSuggestions:(HttpRequest *)request response:(HttpResponse *)response;

@end