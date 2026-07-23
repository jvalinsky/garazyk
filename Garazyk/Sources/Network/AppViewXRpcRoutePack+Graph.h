// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

@interface AppViewXRpcRoutePack (Graph)

- (void)handleGetFollows:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetFollowers:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetBlocks:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetMutes:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetRelationships:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetStarterPack:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetStarterPacks:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetLists:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetList:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleMuteActor:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleUnmuteActor:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetStarterPacksBulk:(HttpRequest *)request response:(HttpResponse *)response;

@end